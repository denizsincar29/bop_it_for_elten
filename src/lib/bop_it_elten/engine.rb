# encoding: utf-8
# frozen_string_literal: true

module BopItElten
  # Pure game logic of Bop It — a faithful port of the Elten 2 original by
  # Deniz Sincar (bomberman29). No Elten calls live here: everything the
  # engine needs from the outside flows through a small `platform` facade, so
  # the whole game can be unit-tested with a scripted double and no runtime.
  #
  # Platform contract (the UI layer in __app.rb implements it against Elten 3):
  #
  #   p.now            Float monotonic seconds. The engine never reads the
  #                    wall clock, so a fake clock makes tests deterministic.
  #   p.sleep_s(sec)   Block for sec while pumping the event loop (Elten stays
  #                    responsive). Any key edges seen during the wait queue
  #                    up for take_pressed.
  #   p.take_pressed   Array<Symbol> of key edges seen since the last call, in
  #                    order: :bop :twist :pull :level :reset :escape :help
  #                    :help_full. A held key yields a single edge — the toy
  #                    must be re-pressed for every action. (The original read
  #                    held state and needed `while twist end` release-waits;
  #                    edge semantics make those unnecessary.)
  #   p.play(name, volume:)
  #                    Start sound asset `name` (basename, no extension),
  #                    non-blocking, layered over whatever plays.
  #   p.play_wait(name, volume:, extra:)
  #                    Play `name` and block until it has finished plus `extra`
  #                    seconds (edges keep queuing). Only for announcements.
  #   p.alert(text)    Speak text immediately (TTS), non-blocking.
  #   p.open_help      Open the full written manual (a modal markdown Form)
  #                    and block until the player closes it. Outside Elten a
  #                    scripted double just records the call.
  class Engine
    TOTAL_COMMANDS = 100    # the toy is beaten at 100 correct moves
    IDLE_TIMEOUT_S = 20.0   # start screen "goes to sleep" after this silence
    R_WINDOW_S = 5.0        # R then type the test-mode combo within this
    COMBO = %i[pull bop twist twist twist].freeze # "pbttt" in actions
    SPAM_WINDOW_S = 15.0    # test mode: each key restarts this replay window
    POLL_S = 0.02           # input poll step inside the loops

    COMMAND_SOUND = %i[bopit twistit poolit].freeze # spoken/toy ask variants
    SUCCESS_SOUND = { bop: :bopit2, twist: :twistit2, pull: :poolit2 }.freeze
    ACTIONS = %i[bop twist pull].freeze

    # Spoken with alert on H (there is no built-in Elten F1 help for programs
    # — see the port notes), for a player who does not know the keys yet.
    # F1 opens the full written help page instead of speaking.
    HELP_TEXT = "Space bops, Enter twists, Tab pulls. Press Space to start. " \
                "A wrong key ends the round; Escape turns the toy off. " \
                "On the start screen, Enter changes the volume, M changes the " \
                "level, and Tab switches to Pass It mode. " \
                "Press F1 for the full help page.".freeze

    # The full clip tour the hidden test mode plays once its replay window
    # lapses — mirrors the original testmode.rb list verbatim.
    TEST_MODE_SOUNDS = %i[
      bopit1 bopit2 twistit1 twistit2 poolit1 poolit2 win
      bopit0 twistit0 poolit0 yaw0 yaw1 yaw2 yaw3
      score high wow youbeet
      bopittogo bopittostart solo passit quiet loud blasting
      1 2 3 4 5 6 7 8 9 10 11 12 thir fif teen twen tee hundred
      lose1 lose2 lose3 lose4 lose5 lose0 amgoinasleep
      beetw beets11 beets12 beets13 beetw beets12
      pass1 pass2 pass3 pass4 pass5
      beets20 beets21
    ].freeze

    # Solo high scores are slots 0..2, pass-it slots 3..5, by level.
    SCORE_SLOT = { solo: [0, 1, 2], passit: [3, 4, 5] }.freeze

    def initialize(platform, store, base_speed_ms: 250)
      @p = platform
      @store = store
      @base_speed_ms = base_speed_ms
      @scores = Array.new(6, 0)
      @mode = :solo
      @level = 0
      @ulevel = 0
      @vol = 1.0
      @go_intro = false # start screen says "…to start", or "…to go" after a win / pass-it round
      @stayscore = 0    # pass-it survivors resume from the failed command's index
    end

    # Top-level session. Returns :sleep when the toy was turned off or went to
    # sleep — the caller then closes the program.
    def run
      loop do
        action = start_screen
        if action.nil?
          # True idle timeout (no escape): say goodnight, like the original's
          # "amgoinasleep" before it closed itself.
          cue(:amgoinasleep) unless @quit
          return :sleep
        end

        play_round
        return :sleep if @quit
      end
    end

    # --- persistence --------------------------------------------------------

    def section
      @mode == :passit ? 'passit' : 'bopit'
    end

    def slot
      SCORE_SLOT.fetch(@mode)[@level]
    end

    def refresh_scores
      %w[bopit passit].each_with_index do |sec, base|
        3.times { |i| @scores[base * 3 + i] = @store.read(sec, "hs#{i}").to_i }
      end
      @ulevel = 0
      @ulevel = 1 if @scores[0] == 100 || @scores[3] == 100
      @ulevel = 2 if @scores[1] == 100 || @scores[4] == 100
      @level = @ulevel if @level > @ulevel
    end

    def save_current_score
      @store.write(section, "hs#{@level}", @scores[slot].to_s)
    end

    # --- sound helpers (the volume toggle scales every play) ----------------

    def sfx(name)
      @p.play(name, volume: @vol)
    end

    def cue(name, extra: 0.0)
      @p.play_wait(name, volume: @vol, extra: extra)
    end

    # --- start screen -------------------------------------------------------

    # The toy is "on". Commands on the start screen:
    #   bop    -> start a round
    #   pull   -> toggle solo / pass it
    #   twist  -> cycle volume (blasting -> quiet -> loud, like the toy switch)
    #   M      -> cycle level (only up to what is unlocked)
    #   R      -> hidden developer test mode
    #   H      -> speak the short key help (alert)
    #   F1     -> open the full markdown help page
    #   escape -> turn the toy off (back to the Elten menu)
    # Idle for IDLE_TIMEOUT_S and the toy "goes to sleep" (returns nil).
    def start_screen
      refresh_scores
      sfx(@go_intro ? :bopittogo : :bopittostart)
      wake = @p.now
      loop do
        @p.take_pressed.each do |k|
          case k
          when :reset
            return nil unless reset_window  # nil => session ended by escape
          when :escape
            @quit = true
            return nil
          when :bop
            return :play
          when :pull
            toggle_mode
          when :twist
            cycle_volume
          when :level
            cycle_level
          when :help
            @p.alert(HELP_TEXT)
          when :help_full
            @p.open_help # blocks until the player closes the help page
          end
          wake = @p.now
        end
        return nil if @p.now - wake >= IDLE_TIMEOUT_S

        @p.sleep_s(POLL_S)
      end
    end

    def toggle_mode
      @mode = @mode == :passit ? :solo : :passit
      sfx(@mode == :passit ? :passit : :solo)
    end

    def cycle_volume
      @vol = { 1.0 => 0.33, 0.33 => 0.66, 0.66 => 1.0 }[@vol]
      sfx({ 0.33 => :quiet, 0.66 => :loud, 1.0 => :blasting }[@vol])
    end

    def cycle_level
      @level = (@level + 1) % (@ulevel + 1)
      sfx(:"level#{@level}")
    end

    # --- hidden developer test mode -----------------------------------------

    # R opens a 5 s window to type the combo "pbttt" with the three action
    # keys. On the combo the toy announces "five" (the Beta build number),
    # then for SPAM_WINDOW_S each action key replays its success sound and
    # restarts the window. When the window finally lapses it tours every clip.
    # Returns true to continue the session, false when escape ended it.
    def reset_window
      @p.alert('reset')
      entered = []
      stop = @p.now + R_WINDOW_S
      loop do
        @p.take_pressed.each do |k|
          return false if k == :escape

          sym = { bop: :bop, twist: :twist, pull: :pull }[k]
          next unless sym

          entered << sym
          entered.shift(entered.size - COMBO.size) if entered.size > COMBO.size
          return test_mode if entered == COMBO
        end
        return true if @p.now >= stop

        @p.sleep_s(POLL_S)
      end
    end

    def test_mode
      announce_score(5)
      window = @p.now + SPAM_WINDOW_S
      loop do
        @p.take_pressed.each do |k|
          return true if k == :escape # skip the clip tour, back to start

          name = SUCCESS_SOUND[k]
          sfx(name) if name
          window = @p.now + SPAM_WINDOW_S
        end
        break if @p.now >= window

        @p.sleep_s(POLL_S)
      end
      TEST_MODE_SOUNDS.each { |name| cue(name) }
      true
    end

    # --- a round ------------------------------------------------------------

    def play_round
      @stayscore = 0 if @mode == :solo
      @topassit = rand(4) + 3
      if @mode == :solo && @scores[slot].positive?
        cue(:high)
        announce_score(@scores[slot])
      end
      beet(0, @base_speed_ms)

      i = @stayscore
      while i < TOTAL_COMMANDS
        # Pass-it: when the hand-off counter hits zero, the toy plays the
        # "pass it" countdown and the players physically pass the device.
        if @mode == :passit && @topassit <= 0
          beet(1, @speed_ms)
          @topassit = rand(4) + 3
        end
        @speed_ms = [@base_speed_ms - i, 1].max

        command = i <= 2 ? i : rand(3) # the toy always opens bop, twist, pull
        @topassit -= 1 if @mode == :passit
        sfx(command_sound(command))

        case check_key(command, @speed_ms)
        when :ok
          i += 1
        when :escape
          @go_intro = false
          return # back to the start screen; no loss recorded
        else
          finish_round(i)
          return
        end
      end
      win_round
    end

    # Ask voice variant: novice speaks the word (…0), expert uses the toy
    # sound (…1 = drum/scratch/whistle), master mixes both at random.
    def command_sound(command)
      rr = @level == 1 ? 1 : (@level == 2 ? rand(2) : 0)
      :"#{COMMAND_SOUND[command]}#{rr}"
    end

    # Waits up to the command window for the single correct key. A wrong
    # action key is an instant loss, escape aborts the round, and the
    # metronome beeps pace the command at 2x and 3x the speed.
    def check_key(command, speed_ms)
      correct = ACTIONS[command]
      step = speed_ms / 1000.0
      deadline = @p.now + step * 5
      beep2_at = @p.now + step * 2
      beep3_at = @p.now + step * 3
      beeps = 0

      loop do
        @p.take_pressed.each do |k|
          if k == :escape
            return :escape
          elsif k == :help
            @p.alert(HELP_TEXT) # mid-round help must not consume the round
          elsif k == :help_full
            @p.open_help        # neither does the full help page
          elsif k == correct
            sfx(SUCCESS_SOUND[correct])
            littlebit(speed_ms)
            return :ok
          elsif ACTIONS.include?(k)
            return :wrong
          end
        end

        now = @p.now
        if beeps.zero? && now >= beep2_at
          sfx(:beets21)
          beeps = 1
        elsif beeps == 1 && now >= beep3_at
          sfx(:beetw)
          beeps = 2
        end
        return :timeout if now >= deadline

        @p.sleep_s(POLL_S)
      end
    end

    # Keep-the-beat riff right after a correct key.
    def littlebit(speed_ms)
      s = speed_ms / 1000.0
      @p.sleep_s(s * 2)
      sfx(:beets21)
      @p.sleep_s(s)
      sfx(:beetw)
      @p.sleep_s(s)
    end

    # The intro metronome (topass=0) or the pass-it hand-off (topass=1: the
    # "pass it" voice, the 1..6 countdown, then the same metronome) played
    # between commands. Each beat is spaced by the current speed.
    def beet(topass, speed_ms)
      if topass == 1
        sfx(:passit)
        step_wait(speed_ms * 2)
        (1..6).each do |n|
          sfx(:"pass#{n}")
          step_wait(speed_ms)
        end
      end
      intro_beats.each do |name|
        sfx(name)
        step_wait(speed_ms)
      end
    end

    def intro_beats
      [:"beets1#{rand(4)}", :beetw, :"beets2#{rand(2)}", :beets10,
       :"beets1#{rand(3)}", :beetw, :beets20, :beetw]
    end

    # Silence between two beats. Escape here ends the round back at the start
    # screen (the original went straight to the Elten menu from the intro
    # beats; we made the escape behaviour consistent — see port notes).
    def step_wait(ms)
      deadline = @p.now + [ms / 1000.0, 0.0].max
      until @p.now >= deadline
        return if @p.take_pressed.include?(:escape)

        @p.sleep_s(POLL_S)
      end
    end

    def finish_round(failed_index)
      @stayscore = failed_index if @mode == :passit
      @go_intro = @mode == :passit
      score = failed_index
      if score > @scores[slot]
        @scores[slot] = score
        save_current_score
      end
      cue(:"yaw#{rand(4)}")
      cue(:"lose#{rand(5)}")
      if @mode == :solo
        announce_score(score)
      else
        cue(:yourout)
      end
    end

    def win_round
      @stayscore = 0
      cue(:win)
      cue(:wow) if @level == 2
      cue(:youbeet)
      cue(:"level#{@level}") if @level <= 1
      cue(:bopit0) if @level == 2
      @ulevel += 1 if @ulevel == @level && @ulevel < 2
      @scores[slot] = 100
      save_current_score
      @level = @ulevel
      @go_intro = true
    end

    # --- score speech -------------------------------------------------------

    # Spoken English number words, as in the original. Pure and testable:
    # returns the ordered clip names. The "troublesome teens" map to a digit
    # plus "teen" (13 -> thir+teen, 15 -> fif+teen, so 15 does NOT also play
    # the digit "5"), 20+ to a tens word or digit plus "tee", and 100 to
    # "one hundred".
    def self.score_clip_names(score)
      return [] if score.nil? || score <= 0

      clips = []
      clips << score.to_s if score <= 12
      if score == 100
        return %w[1 hundred]
      end

      clips << 'twen' if score.between?(20, 29)
      clips << 'thir' if score == 13 || score.between?(30, 39)
      clips << 'fif' if score == 15 || score.between?(50, 59)
      clips << (score - 10).to_s if score.between?(14, 19) && score != 15
      clips << 'teen' if score.between?(13, 19)
      clips << (score / 10).to_s if score.between?(40, 49) || score.between?(60, 99)
      clips << 'tee' if score.between?(20, 99)
      clips << (score % 10).to_s if score.between?(20, 99) && (score % 10).positive?
      clips
    end

    def announce_score(score)
      return if score.nil? || score <= 0

      cue(:score)
      self.class.score_clip_names(score).each { |n| cue(n) }
    end
  end
end
