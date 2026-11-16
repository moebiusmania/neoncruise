# Neon Cruise for iPhone

The [Neon Cruise](../README.md) cassette player as a native iPhone app, built with SwiftUI. It plays the same seven Nightride FM stations and follows the web app's phone layout: Now Playing, Tape Shelf and Signal FX screens over the live outrun scene.

## Features

- Live 320 kbps streams decoded in-process (`AudioFileStream` + `AVAudioConverter` into an `AVAudioEngine` source node), with auto-reconnect and a stall watchdog
- Real spectrum analyser and beat detection (vDSP FFT, same tuning as the web analyser), tape hiss and the static burst on tape change
- Keeps playing in the background, with lock screen / Control Center info and controls (play, pause, next and previous station)
- Pauses on calls and other interruptions and resumes after, and pauses when headphones are unplugged
- Now-playing info, listener counts and the on-air log from the Nightride FM live feed
- Animated outrun scene, spinning cassette reels, coverflow tape shelf with swipe and haptics
- CRT effects (scanlines, flicker, grain), sleep timer that fades out, settings saved between launches
- VoiceOver labels, Reduce Motion support and Dynamic Type for the text styles

## Requirements

- Xcode 26 or newer (the project uses Swift 6 with main-actor default isolation)
- iOS 18 or newer, iPhone

## Run it

Open `NeonCruise.xcodeproj` in Xcode, pick an iPhone simulator or your device and press Run. To run on a device, choose your team under Signing & Capabilities.

From the command line:

```sh
cd ios
xcodebuild -project NeonCruise.xcodeproj -scheme NeonCruise \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

Debug builds accept two launch arguments for quick testing: `-autoplay` starts the stream on launch, and `-screen shelf` or `-screen fx` opens that screen (like the web's `?screen=` shortcuts).

## How it's built

| Folder | What's in it |
| --- | --- |
| `Audio/` | `StreamDecoder` (HTTP → MP3 packets → PCM), `AudioCore` (lock-free ring buffer, real-time render with hiss and burst), `Analyzer` (FFT and beat), `Player` (transport, retries, sleep timer, audio session, Now Playing) |
| `Model/` | Stations, settings, and the metadata feed (SSE + Icecast status) with defensive parsing |
| `Theme/` | The oklch colour maths shared with the web and TUI, plus the bundled fonts |
| `Views/` | The phone screens and the shared pieces: outrun scene, spectrum, cassette, CRT overlays, panels |

The real-time audio thread never allocates or waits on a lock: it only uses atomics and `Mutex.withLockIfAvailable`, and plays silence for one cycle in the rare case the decoder holds the buffer.

The fonts (Syncopate, VT323, Space Grotesk) are bundled under their own licences, which sit next to the font files in `NeonCruise/Resources/Fonts`.

An iPad layout (the web's three-pane desktop view) is sketched in `Views/Pad/` but not enabled yet: the app currently targets iPhone only.
