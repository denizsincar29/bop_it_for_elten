# encoding: utf-8
# frozen_string_literal: true

module BopItElten
  # Full in-game help, shown in a markdown-capable read-only field. Elten 3
  # renders Markdown in an EditBox with the MarkDown flag (the same widget the
  # built-in documentation uses), so the text below is written as Markdown.
  # F1 opens it on demand; the UI layer also opens it once on a fresh install
  # (no "helped" flag in the high-score store yet).
  module Help
    # Short UI strings, single-sourced here so the English msgids in the
    # locale catalogs match the code exactly (the Elten dictionary keys on
    # the literal English text). The full manual is one big msgid too, so the
    # whole help window follows Elten's UI language at once.
    TITLE = "Bop It — Help".freeze
    CLOSE = "Close".freeze
    JOIN_BETA = "Join the beta testing group".freeze

    # The trailing-newline chomp keeps the English msgid the locale generator
    # extracts byte-stable (tools/build_locales.py reproduces this dedent +
    # chomp; test/bop_it_test.rb re-verifies parity against the .mo files).
    FULL_HELP = <<~MARKDOWN.chomp
      # Bop It for Elten 3

      A fast reaction game. The toy calls out a command — **bop it**, **twist
      it** or **pull it** — and you must hit the matching key before the
      metronome runs out. A wrong key or a pause ends the round.

      ## The original

      The mechanics are copied from the **Bop It Shout** toy by Hasbro
      (2008), which made the whole room play: one person held the toy while
      everyone shouted the commands together. This port keeps the three
      classic moves and leaves out the **Shout It** command.

      ## Playing with the keys

      - **Space** — bop it.
      - **Enter** — twist it.
      - **Tab** — pull it.
      - **Escape** — turn the toy off.

      A round lasts until you miss or complete **100 correct moves**. The
      commands speed up the longer you survive.

      ## On the start screen

      While the toy says "bop it to start", the keys do extra things:

      - **Space** — start a game.
      - **Enter** — change the volume (quiet, loud, blasting), like the
        switch on the real toy.
      - **M** — the small button on the toy's body: pick the level.
      - **Tab** — switch between Solo and Pass It.
      - **H** — repeat the short key list.
      - **F1** — reopen this page.

      ## Levels

      There are three: **Novice**, **Expert** and **Master**. Novice calls
      the command by name, Expert plays the toy's sound, Master mixes both.
      Beat a level with 100 moves to unlock the next one.

      ## Pass It

      Hand the device around the room. When the toy says "pass it", give it
      to the next player. Anyone who misses is out; the last one standing
      wins.

      ## About this port

      Written by Deniz Sincar, this version recreates the toy on **Elten 3**.
      The game logic is a faithful port of his original Elten 2 edition,
      built on the Bop It Shout mechanics, and the voice and effect sounds
      were recorded from a real Bop It unit. The engine is kept free of
      Elten calls so it can be tested on its own, which keeps every release
      solid.

      Enjoy — and keep your hands on the keys.
    MARKDOWN
  end
end
