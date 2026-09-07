# encoding: utf-8
# frozen_string_literal: true

=begin Elten3AppInfo
{
  "id": "78774b7d-2d15-440e-9502-b5260dc136a6",
  "name": "BopIt",
  "version": "0.1.3",
  "build_id": 20260907004,
  "EltenAPIVersion": "3.0",
  "author": "denizsincar29",
  "main_class": "ProgramBopIt",
  "main_language": "en",
  "supported_languages": ["en"],
  "platforms": ["all"],
  "required_assets": {
    "sounds": [
      "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12",
      "amgoinasleep", "beets10", "beets11", "beets12", "beets13",
      "beets20", "beets21", "beetw", "blasting", "bopit0", "bopit1",
      "bopit2", "bopittogo", "bopittostart", "fif", "high", "hundred",
      "level0", "level1", "level2", "lose0", "lose1", "lose2", "lose3",
      "lose4", "lose5", "loud", "pass1", "pass2", "pass3", "pass4",
      "pass5", "pass6", "passit", "poolit0", "poolit1", "poolit2",
      "quiet", "score", "solo", "tee", "teen", "thir", "twen",
      "twistit0", "twistit1", "twistit2", "win", "wow", "yaw0", "yaw1",
      "yaw2", "yaw3", "youbeet", "youcanplaybopit", "yourout"
    ]
  },
  "description": "Bop It — порт звуковой игры с Элтена 2: бей, крути, тяни."
}
=end Elten3AppInfo

require_relative "lib/bop_it_elten/engine"
require_relative "lib/bop_it_elten/store"
require_relative "lib/bop_it_elten/platform"
require_relative "lib/bop_it_elten/help"

# Elten 3 entry for Bop It. The program IS the toy: there is no menu to
# choose a mode from — the engine's start screen is the toy's "on" state,
# where every key is already a command (bop = play, pull = pass-it, twist =
# volume, M = level, R = hidden test mode, F1 = full help, escape = off).
# main therefore just wires the Elten Program into the engine and hands it
# the whole session. The engine returns only when the toy is turned off or
# falls asleep after idling; finish then drops the Program (Elten closes the
# sound pool on finalize, so the layered toy clips die with it).
#
# The boot path is the proven Mile by Mile idiom (`def main` + `ensure
# finish`) — execute_scene_main calls scene.main because Program subclasses
# here define no `program_main`; apps that define `program_main` get the
# runtime to finalize for them instead.
#
# The full written help is a Form built HERE, in the Program subclass, not in
# the plain helper classes: Elten mixes EltenAPI into Object, so the bare
# control constants (EditBox, Button, Form, EditBox::Flags::*) only resolve
# inside a Program/Scene subclass. The engine asks for it through
# Platform#open_help, which forwards to open_full_help when present.
class ProgramBopIt < Program
  def main
    platform = BopItElten::Platform.new(self)
    store = BopItElten::Store.new(self)

    # A brand-new install (no "helped" flag in the score store yet) opens the
    # full manual once, so a player who does not know the toy gets the written
    # intro instead of silence. F1 reopens it any time afterwards.
    if store.read('meta', 'helped').empty?
      open_full_help
      store.write('meta', 'helped', '1')
    end

    engine = BopItElten::Engine.new(platform, store)
    engine.run
  ensure
    finish
  end

  # The full manual in a read-only markdown field, mirroring Elten's own
  # documentation window (documentation.rb): MarkDown flag renders the text,
  # quiet read-only EditBox, Close button doubles as accept and cancel so
  # Enter / Escape both leave. Blocks until the player closes it.
  def open_full_help
    box = EditBox.new(
      "Bop It — Help",
      type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine | EditBox::Flags::MarkDown,
      text: BopItElten::Help::FULL_HELP,
      quiet: true
    )
    close = Button.new("Close")
    form = Form.new([box, close], index: 0, quiet: true)
    close.on(:press) { form.resume }
    form.accept_button = form.cancel_button = close
    form.wait
  end
end
