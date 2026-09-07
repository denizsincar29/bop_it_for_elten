# encoding: utf-8
# frozen_string_literal: true

# Engine tests for Bop It — mirror of the scratch scenario harness
# (scratch/bopit/scenarios.rb) that runs on plain Ruby in CI. The engine is
# pure logic with an injected platform/store double, so no Elten runtime is
# needed.
#
# Run: ruby -Itest test/bop_it_test.rb

require "minitest/autorun"
require_relative "../src/lib/bop_it_elten/engine"
require_relative "../src/lib/bop_it_elten/help"

# Persistence double: section/key -> string, like the read/write json store
# the UI layer will provide.
class FakeStore
  def initialize
    @h = {}
  end

  def read(section, key)
    (@h[[section, key]] || "").to_s
  end

  def write(section, key, val)
    @h[[section, key]] = val.to_s
  end
end

# Autoplay: when play() is fed a command ask (bopit0/1, twistit0/1, poolit0/1)
# the correct action is delivered on the next take_pressed, exactly like a
# player hitting the right key the instant the command plays.
ACTIONS_BY = { "bopit" => :bop, "twistit" => :twist, "poolit" => :pull }.freeze
WRONG = { bop: :pull, twist: :bop, pull: :twist }.freeze

class FakePlatform
  attr_reader :played, :alerts, :help_opens
  attr_accessor :now, :autopress, :fail_at

  def initialize
    @now = 0.0
    @pressed = []
    @played = []
    @alerts = []
    @help_opens = 0 # how many times open_help (full page) was requested
    @autopress = false
    @pending = nil
    @cmds = 0       # how many commands have been answered correctly
    @fail_at = nil  # answer the @fail_at-th (1-based) command wrongly
    @dur = Hash.new(0.2)
  end

  def play(name, volume: nil)
    name = name.to_s
    @played << name
    return unless @autopress
    m = /\A(bopit|twistit|poolit)[01]\z/.match(name)
    @pending = ACTIONS_BY[m[1]] if m
  end

  def play_wait(name, volume: nil, extra: 0.0)
    name = name.to_s
    @played << name
    @now += @dur[name] + extra
  end

  def alert(text)
    @alerts << text.to_s
  end

  # The real Platform forwards to ProgramBopIt#open_full_help (a modal Form);
  # the fake just records the request and returns, like the page closing.
  def open_help
    @help_opens += 1
  end

  def take_pressed
    out = @pressed.dup
    @pressed.clear
    if @autopress && @pending
      if @fail_at && @cmds == @fail_at
        out << WRONG[@pending]
        @fail_at = nil
      else
        out << @pending
        @cmds += 1
      end
      @pending = nil
    end
    out
  end

  def sleep_s(sec)
    @now += sec
  end

  def press(*keys)
    @pressed.concat(keys)
  end
end

class BopItEngineTest < Minitest::Test
  def fresh(base = 250)
    fp = FakePlatform.new
    fs = FakeStore.new
    e = BopItElten::Engine.new(fp, fs, base_speed_ms: base)
    [fp, fs, e]
  end

  # --- score speech (original sayscore clip order) ---

  def test_score_clip_names
    map = {
      1 => %w[1], 5 => %w[5], 12 => %w[12],
      13 => %w[thir teen], 14 => %w[4 teen], 15 => %w[fif teen],
      17 => %w[7 teen], 19 => %w[9 teen],
      20 => %w[twen tee], 21 => %w[twen tee 1],
      30 => %w[thir tee], 33 => %w[thir tee 3],
      40 => %w[4 tee], 42 => %w[4 tee 2],
      50 => %w[fif tee], 55 => %w[fif tee 5],
      60 => %w[6 tee], 99 => %w[9 tee 9],
      100 => %w[1 hundred]
    }
    map.each do |n, want|
      assert_equal want, BopItElten::Engine.score_clip_names(n), "score #{n}"
    end
    assert_empty BopItElten::Engine.score_clip_names(0)
    assert_empty BopItElten::Engine.score_clip_names(nil)
  end

  # --- volume toggle regression (original bug: elsif @@vol=66 assignment) ---

  def test_volume_cycle
    _, _, e = fresh
    e.instance_variable_set(:@vol, 1.0)
    e.cycle_volume
    assert_in_delta 0.33, e.instance_variable_get(:@vol), 0.001
    e.cycle_volume
    assert_in_delta 0.66, e.instance_variable_get(:@vol), 0.001
    e.cycle_volume
    assert_in_delta 1.0, e.instance_variable_get(:@vol), 0.001
    e.cycle_volume
    assert_in_delta 0.33, e.instance_variable_get(:@vol), 0.001
  end

  # --- level gating on start screen ---

  def test_level_cycle_respects_unlock
    fp, fs, e = fresh
    e.refresh_scores
    e.cycle_level
    assert_equal 0, e.instance_variable_get(:@level), "no unlock: stays novice"
    assert_equal "level0", fp.played.last
    fs.write("bopit", "hs0", "100")
    e.refresh_scores
    assert_equal 1, e.instance_variable_get(:@ulevel)
    e.cycle_level
    assert_equal 1, e.instance_variable_get(:@level)
    e.cycle_level
    assert_equal 0, e.instance_variable_get(:@level)
  end

  # --- check_key: correct / wrong / timeout / escape ---

  def test_check_key_outcomes
    fp, _, e = fresh
    fp.press(:bop)
    assert_equal :ok, e.send(:check_key, 0, 250)
    fp.press(:pull)
    assert_equal :wrong, e.send(:check_key, 0, 250)
    assert_equal :timeout, e.send(:check_key, 1, 250)
    fp.press(:escape)
    assert_equal :escape, e.send(:check_key, 2, 250)
  end

  # --- hidden developer test mode (R, combo pbttt) ---

  def test_reset_window_and_test_mode
    fp, _, e = fresh
    fp.press(:pull, :bop, :twist, :twist, :twist)
    assert_equal true, e.send(:reset_window)
    assert_includes fp.alerts, "reset"
    assert_includes fp.played, "5", "announced the Beta build number"
    assert_includes fp.played, "beets21"
    assert_includes fp.played, "lose0"
  end

  # --- solo round: full 100-command win on autoplay ---

  def test_solo_full_win
    fp, fs, e = fresh
    fp.autopress = true
    e.play_round
    assert_equal "100", fs.read("bopit", "hs0")
    assert_equal 100, e.instance_variable_get(:@scores)[0]
    assert_equal 1, e.instance_variable_get(:@ulevel)
    assert_equal 1, e.instance_variable_get(:@level)
    assert_includes fp.played, "win"
  end

  # --- solo round loses at a chosen command; saves high score, speaks it ---

  def test_solo_loss_records_score
    fp, fs, e = fresh
    fp.autopress = true
    fp.fail_at = 3   # 3 correct, then wrong on the 4th command (index 3)
    e.play_round
    assert_equal "3", fs.read("bopit", "hs0")
    refute_includes fp.played, "yourout"
    assert_equal 1, fp.played.count { |s| s.start_with?("yaw") }
    assert_equal 1, fp.played.count { |s| s.start_with?("lose") }
    assert_equal %w[score 3], fp.played.last(2)
  end

  # --- pass-it elimination then survivors resume the SAME sequence ---

  def test_passit_elimination_and_stayscore_resume
    fp, fs, e = fresh
    e.toggle_mode
    assert_equal :passit, e.instance_variable_get(:@mode)
    fp.autopress = true
    fp.fail_at = 4   # 4 correct, then a miss on the 5th command (index 4)
    e.play_round
    assert fp.played.any? { |s| s =~ /\A(bopit|twistit|poolit)\d\z/ }
    assert_equal "4", fs.read("passit", "hs0")
    assert_includes fp.played, "yourout"
    fp.autopress = true
    e.play_round
    assert_equal "100", fs.read("passit", "hs0")
    assert_equal "", fs.read("bopit", "hs0"), "solo untouched"
  end

  # --- high-score announcement opens a solo round when a score exists ---

  def test_solo_round_announces_existing_high_first
    fp, fs, e = fresh
    fs.write("bopit", "hs0", "30")
    e.refresh_scores
    fp.autopress = true
    e.play_round
    assert_equal %w[high score thir tee], fp.played.first(4)
  end

  # --- start screen: bop starts, pull toggles mode, idle sleeps ---

  def test_start_screen_bop_starts_round
    fp, _, e = fresh
    fp.press(:bop)
    assert_equal :play, e.send(:start_screen)
  end

  def test_start_screen_pull_toggles_mode
    fp, _, e = fresh
    fp.press(:pull)
    e.send(:start_screen)
    assert_equal :passit, e.instance_variable_get(:@mode)
  end

  def test_start_screen_idle_sleeps
    fp, _, e = fresh
    t0 = fp.now
    assert_nil e.send(:start_screen)
    assert_in_delta 20.0, fp.now - t0, 1.0
  end

  # --- H / F1 key help ---

  def test_start_screen_help_speaks_hotkeys
    fp, _, e = fresh
    fp.press(:help, :bop) # help first, then bop starts the round
    assert_equal :play, e.send(:start_screen)
    assert_includes fp.alerts, BopItElten::Engine::HELP_TEXT
    assert_equal 0, fp.help_opens, "H speaks, it does not open the page"
  end

  def test_check_key_help_does_not_consume_the_round
    fp, _, e = fresh
    fp.press(:help, :bop) # help then the correct key in the same poll
    assert_equal :ok, e.send(:check_key, 0, 250)
    assert_includes fp.alerts, BopItElten::Engine::HELP_TEXT
  end

  def test_start_screen_f1_opens_full_help
    fp, _, e = fresh
    fp.press(:help_full, :bop) # F1 opens the page, then bop starts the round
    assert_equal :play, e.send(:start_screen)
    assert_equal 1, fp.help_opens
    assert_empty fp.alerts, "F1 opens the page, it does not speak"
  end

  def test_check_key_f1_does_not_consume_the_round
    fp, _, e = fresh
    fp.press(:help_full, :bop) # F1 then the correct key in the same poll
    assert_equal :ok, e.send(:check_key, 0, 250)
    assert_equal 1, fp.help_opens
  end

  # --- run: full session auto-finishes on the very first bop ---

  def test_top_level_run_returns_cleanly
    fp, fs, e = fresh
    fp.autopress = true
    fp.press(:bop)
    e.run
    assert_equal 100, e.instance_variable_get(:@scores)[0]
  end
end

# --- locale catalogs: every .mo msgid must byte-match a Ruby constant -------
#
# Elten's dictionary keys on the literal English string the code passes to _()
# (the whole manual is one key). If tools/build_locales.py ever extracts a
# msgid that differs from what Ruby actually holds in HELP_TEXT / FULL_HELP /
# TITLE / CLOSE / JOIN_BETA — a heredoc edge, a stray space, a trailing
# newline — that language silently falls back to English at runtime. So CI
# decodes each shipped .mo and asserts key-for-key parity with the constants,
# plus a non-empty, actually-translated value.

class LocaleCatalogTest < Minitest::Test
  LOCALES = %w[de es fr it pl pt ru tr uk].freeze
  LOCALE_DIR = File.expand_path("../src/locale", __dir__)

  def decode_mo(path)
    data = File.binread(path)
    _magic, _rev, n, o_off, t_off, _hsz, _hoff = data.unpack("V7")
    read_table = lambda do |table_off|
      n.times.map do |i|
        len, at = data.byteslice(table_off + i * 8, 8).unpack("V2")
        data.byteslice(at, len).dup.force_encoding(Encoding::UTF_8)
      end
    end
    read_table.call(o_off).zip(read_table.call(t_off)).to_h
  end

  def test_catalog_msgids_match_constants_and_are_translated
    expected = {
      BopItElten::Help::TITLE => :title,
      BopItElten::Help::CLOSE => :close,
      BopItElten::Help::JOIN_BETA => :join_button,
      BopItElten::Help::FULL_HELP => :manual,
      BopItElten::Engine::HELP_TEXT => :help_speech,
      "reset" => :reset
    }
    LOCALES.each do |code|
      cat = decode_mo(File.join(LOCALE_DIR, "#{code}.mo"))
      assert_equal expected.size, cat.size, "#{code}: unexpected msgid count"
      expected.each do |msgid, kind|
        assert cat.key?(msgid),
               "#{code}: catalog lacks the #{kind} msgid (#{msgid[0, 40].inspect}...)"
        refute_empty cat[msgid], "#{code}: empty translation for #{kind}"
        refute_equal msgid, cat[msgid], "#{code}: #{kind} not translated" unless kind == :reset
      end
    end
  end

  def test_manual_translations_keep_markdown_structure
    LOCALES.each do |code|
      cat = decode_mo(File.join(LOCALE_DIR, "#{code}.mo"))
      manual = cat[BopItElten::Help::FULL_HELP]
      assert manual.include?("## "), "#{code}: manual lost its markdown headings"
      assert manual.include?("- **"), "#{code}: manual lost its key bullets"
      assert manual.start_with?("# "), "#{code}: manual lost its title heading"
    end
  end
end
