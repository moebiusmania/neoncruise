# Neon Cruise TUI

The [Neon Cruise](../README.md) cassette player in your terminal, built with Rust and [ratatui](https://ratatui.rs).
It plays the same seven Nightride FM stations and mirrors the web app's layout: tape shelf, animated outrun stage with the cassette, and the Signal FX panel.

## Features

- Live 320 kbps MP3 streams decoded in-process (no external player needed), with auto-reconnect
- Now-playing info, listener counts and the on-air log from the Nightride FM live feed
- Animated outrun scene drawn with half-block pixels: twinkling stars, striped sun, mountains and a scrolling grid that pulses on the beat
- Real spectrum analyser and beat detection from the decoded audio (or a simulated meter with REACTIVE off)
- Cassette with spinning reels that slides into the deck, a station name that scrambles in, and a static burst on every tape change
- CRT effects (scanlines, flicker, grain), optional tape hiss and a sleep timer that fades out
- Mouse support: click tapes, buttons, toggles and the volume bar; hover a tape to preview its colours
- Three-pane layout on wide terminals, Now / Shelf / FX screens on narrow ones
- Settings saved between runs

## Requirements

- Rust 1.88 or newer
- A terminal with truecolor support (iTerm2, Ghostty, WezTerm, kitty, Alacritty, Windows Terminal, recent GNOME Terminal…) and at least 100×28 for the full layout
- On Linux, the ALSA development package (`libasound2-dev` on Debian/Ubuntu, `alsa-lib-devel` on Fedora)

## Run

```sh
cd tui
cargo run --release
```

## Keys

| Key                 | Action                         |
| ------------------- | ------------------------------ |
| `Space` / `K`       | Play / pause                   |
| `←` `→` / `N` `P`   | Previous / next station        |
| `1`–`7`             | Jump to a station              |
| `M`                 | Mute                           |
| `+` `-` / scroll    | Volume                         |
| `S`                 | Cycle the sleep timer          |
| `R`                 | Toggle REACTIVE                |
| `H`                 | Toggle tape hiss               |
| `F`                 | Open Signal FX                 |
| `Tab`               | Switch screen (narrow layout)  |
| `↑` `↓` + `Enter`   | Pick a tape on the Shelf screen |
| `Esc`               | Back to Now Playing            |
| `Q` / `Ctrl+C`      | Quit                           |

## Layout

| File               | What it does                                                    |
| ------------------ | --------------------------------------------------------------- |
| `src/audio.rs`     | HTTP stream → symphonia MP3 decoder → rodio output, hiss, static burst, analyser tap |
| `src/meta.rs`      | Nightride FM SSE feed and Icecast status polling                |
| `src/app.rs`       | Player state and transport logic (port of `src/lib/player.ts`)  |
| `src/vis.rs`       | FFT, beat and loudness (port of `src/lib/ticker.ts`)            |
| `src/ui/`          | Horizon scene, cassette, pixel font, panels and CRT effects     |

Settings are stored in `neoncruise/settings.json` under your OS config directory.

Pushes that only change files in `tui/` don't trigger the GitHub Pages deploy.
