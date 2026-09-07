# encoding: utf-8
# frozen_string_literal: true

module BopItElten
  # The Elten 3 face of the engine. Every call the engine needs from the
  # outside flows through this one class — nothing else in the game touches
  # Elten. That keeps engine.rb pure Ruby and fully unit-testable (see
  # test/bop_it_test.rb), while this file owns the Elten-specific wiring.
  #
  # Elten 3 mixes EltenAPI into Object (main.rb: `class Object; include
  # EltenAPI`), so the helpers used bare below — key_first_pressed?,
  # loop_update, speak — are private methods available on any object in an
  # app runtime, exactly like they are for the Reference UI in Mile by Mile.
  #
  # Keyboard map (mirrors the original toy on a PC keyboard, and the Elten 2
  # source: pull was `$key[0x9]` tab, reset was `$key[82]` R):
  #   bop     Space  0x20   ("bop it!")
  #   twist   Enter  0x0D   ("twist it!")
  #   pull    Tab    0x09   ("pull it!")
  #   level   M      0x4D   (cycle difficulty; original used getkeychar == "m")
  #   reset   R      0x52   (hidden developer reset / test mode)
  #   escape  Esc    0x1B   (leave the toy)
  #
  # Elten resolves these as raw virtual-key codes — letters are the ASCII
  # code of the uppercase letter, independent of Caps/Shift/layout.
  class Platform
    POLL_S = 0.004 # event-loop pump step while the game waits

    KEY = {
      bop: 0x20,     # Space
      twist: 0x0D,   # Enter
      pull: 0x09,    # Tab
      level: 0x4D,   # M
      reset: 0x52,   # R
      escape: 0x1B   # Escape
    }.freeze

    # The engine wants key *edges*: a held key yields exactly one action and
    # the toy must be re-pressed for the next one. Elten's key_first_pressed?
    # stays true while the key is down across frames, so we latch every token
    # ourselves: an edge is queued only on the false->true transition.
    attr_reader :program

    def initialize(program)
      @program = program
      @down = {}
      @queue = []
    end

    # Monotonic seconds — the engine never reads the wall clock.
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Block for +sec+ while keeping Elten's event loop alive (loop_update).
    # Any key edge seen during the wait is queued and served by the next
    # take_pressed, so a press in the middle of a long wait is not lost.
    def sleep_s(sec)
      deadline = now + [sec.to_f, 0.0].max
      while now < deadline
        loop_update
        sample_keys
        sleep([deadline - now, POLL_S].min) if now < deadline
      end
    end

    # Key edges since the last call, engine-token order (:bop :twist :pull
    # :level :reset :escape — the FIFO order they were pressed).
    def take_pressed
      sample_keys
      out = @queue
      @queue = []
      out
    end

    # Start a layered effect sound and return immediately. Non-blocking: the
    # toy's ask, its metronome beeps and success riffs may ring over each
    # other exactly as the original's overlapping Bass voices did. play is
    # fire-and-forget through the program's sound pool.
    def play(name, volume: nil)
      return if name.nil?

      @program.play_sound_from_asset(name.to_s, volume: (volume || 1.0).to_f)
    rescue Exception => e
      warn_sound(name, e)
    end

    # Play +name+ to completion, then rest +extra+ seconds. Only used for
    # spoken announcements, which must finish before the next one starts
    # (score digits, the win fanfare, the clip tour). The loop pumps events
    # the whole time so Elten stays alive and key edges keep queuing.
    def play_wait(name, volume: nil, extra: 0.0)
      sound = @program.create_sound_from_asset(name.to_s)
      if sound != nil
        begin
          sound.volume = (volume || 1.0).to_f
          sound.play
          dur = sound.respond_to?(:length) ? sound.length.to_f : 0.0
          cap = now + (dur.positive? ? dur + 2.0 : 30.0)
          while now < cap
            break if sound_finished?(sound)

            loop_update
            sample_keys
            sleep(POLL_S)
          end
        ensure
          sound.close if sound.respond_to?(:close)
        end
      end
      sleep_s(extra.to_f) if extra.to_f.positive?
    end

    # Momentary spoken cue (the "reset" alert). speak is async so the engine
    # keeps running and the player can act while it is still talking.
    def alert(text)
      speak(text.to_s)
    end

    private

    def sample_keys
      KEY.each do |token, code|
        pressed = key_first_pressed?(code)
        @queue << token if pressed && !@down[token]
        @down[token] = pressed
      end
    end

    def sound_finished?(sound)
      sound.finished?
    rescue Exception
      true # a broken/closed sound must not hang the announcement
    end

    def warn_sound(name, error)
      Log.warning("BopIt sound #{name} failed: #{error.class}: #{error.message}") if defined?(Log)
    end
  end
end
