# encoding: utf-8
# frozen_string_literal: true

=begin Elten3AppInfo
{
  "id": "78774b7d-2d15-440e-9502-b5260dc136a6",
  "name": "BopIt",
  "version": "0.1.0",
  "build_id": 20260907001,
  "EltenAPIVersion": "3.0",
  "author": "denizsincar29",
  "main_class": "ProgramBopIt",
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

# Elten 3 entry for Bop It. The program IS the toy: there is no menu to
# choose a mode from — the engine's start screen is the toy's "on" state,
# where every key is already a command (bop = play, pull = pass-it, twist =
# volume, M = level, R = hidden test mode, escape = off). main therefore
# just wires the Elten Program into the engine and hands it the whole
# session. The engine returns only when the toy is turned off or falls
# asleep after idling; finish then drops the Program (Elten closes the
# sound pool on finalize, so the layered toy clips die with it).
#
# The boot path is the proven Mile by Mile idiom (`def main` + `ensure
# finish`) — execute_scene_main calls scene.main because Program subclasses
# here define no `program_main`; apps that define `program_main` get the
# runtime to finalize for them instead.
class ProgramBopIt < Program
  def main
    platform = BopItElten::Platform.new(self)
    store = BopItElten::Store.new(self)
    engine = BopItElten::Engine.new(platform, store)
    engine.run
  ensure
    finish
  end
end
