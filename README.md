# BopIt for Elten

A port of the classic reaction toy to the Elten 3 API. Follow the voice
commands: **bop it**, **twist it**, **pull it** — and don't be late.
Originally written by Deniz Sincar (bomberman29) for Elten 2; this repo
re-implements the same game on Elten 3. The mechanics are copied from the
Bop It Shout (2008) toy — the game loop, the metronome pace and the spoken
commands — minus the Shout It command.

## How to play

The toy speaks a command — `bop it`, `twist it`, `pull it` (voice in
Novice, sound-coded in Expert, mixed in Master). Reply with the right key:

| Command   | Key           |
|-----------|---------------|
| bop it    | Space         |
| twist it  | Enter         |
| pull it   | Tab           |

A metronome keeps the pace. Be the first to make 100 correct moves on a
level to unlock the next one: Novice → Expert → Master. Beat all three to
win.

On the start screen (when the toy says "bop it to start"):

- **Bop it** — start a game.
- **Pull it** — toggle Solo / Pass It mode.
- **Twist it** — cycle the volume (Quiet / Loud / Blasting), like the volume
  switch on the toy.
- **M** — the small button on the toy's body: cycle the level (Novice /
  Expert / Master, only the unlocked ones).
- **H / F1** — speak this help (handy when you do not know the keys yet).

### Pass It mode

Play with any number of people. When the toy says "pass it", hand the
device to the next player. Anyone who fails a command is eliminated; the
last player standing wins.

## Controls / hidden extras

- **Escape** anywhere returns to the menu.
- Secret developer test mode exists (it cycles through every voice clip);
  it is reachable exactly as in the original — intended for the author, not
  for normal play.
- High scores are tracked per level and per mode and are saved across runs.

## Structure

```
src/
  __app.rb                    — entry point + Elten3AppInfo manifest
  lib/bop_it_elten/           — game engine + Elten UI/audio glue
  Audio/                      — flat sound assets (see naming note below)
```

The engine (`lib/bop_it_elten/engine.rb`) is free of Elten calls so it can
be unit-tested outside the runtime (`test/bop_it_test.rb`); the Program
subclass and the real-time Runner loop live in the UI layer.

## Sound assets

Elten 3 looks up sound assets by **basename only**, extension stripped
(`add_sound_asset` does `File.basename(path, ext)`), and the physical
loader scans the `Audio/` folder **without recursing into subfolders**.
So every sample shipped as a flat, unique `*.ogg` in `src/Audio/` — the
number clips that lived in `sounds/numbers/` in the Elten 2 original
(`1.ogg`…`12.ogg`, `teen.ogg`, `twen.ogg`, `thir.ogg`, `fif.ogg`,
`tee.ogg`, `hundred.ogg`) sit alongside the toy-voice clips. Source WAVs
are mono 44100 Hz, encoded as Vorbis.

## Installing into Elten (dev)

Copy `src/` into `<appdata>/elten/apps/src/BopIt` and restart Elten in
developer mode (Exit → "Reload in developer mode"), or build a signed
`.eltsetup` via the GitHub Action on a `v*` tag.

**Windows gotcha (CRLF):** Elten 3's `Elten3AppInfo` parser fails on CRLF
line endings — the closing `=end Elten3AppInfo` regex misses the trailing
`\r` and the app is flagged "incompatible". `.gitattributes` forces LF for
`.rb`/`.json`; keep it that way.

## Credits

Voice and toy sounds recorded from a real Bop It unit; game logic and
wording by Deniz Sincar. A metronome-paced reaction game by nature —
volume up, hands on the keys.
