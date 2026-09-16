# Performance notes

The app uses native Swift, AppKit and SwiftUI. It has no embedded browser or
interpreter. Sparkle is linked, but its update controller starts only when you
choose Check for Updates.

## Measured footprint

Local measurements on September 16, 2026, on an Apple Silicon Mac running macOS
26.7, using the signed release build, with notification detection enabled:

| Build and state | Physical footprint |
| --- | --- |
| Beta with Sparkle and color-swatch menus, lights paused | About 32 MiB |
| Earlier build in the same session, Ambient active, before Sparkle and menu polish | 35.1–35.4 MiB |

The Ambient measurement is a development reference, not a measurement of the
final beta. Active-mode memory should be measured again on the final package.
Music and Game do not yet have published measurements.

Values come from `vmmap -summary PID` after startup, with four samples roughly
12 seconds apart. They describe one short local run, not a ceiling or a long-term
leak test. Display count, capture permissions, content and OS versions can change
memory use. Resident size from `ps` includes shared mappings and is not the same
as physical footprint. These numbers cover the app process, not shared macOS
capture services or an active Sparkle installer.

## Limits in the implementation

- Screen samples are scaled to 96 pixels on the longest dimension, at 15 fps.
- Capture queues have a depth of three; audio analysis does not enqueue an
  unbounded second copy of every sample.
- Audio delivery and lighting rendering are limited to 15 updates per second.
- Bluetooth writes are paced and coalesced; newer color commands replace stale ones.
- Solid-color animation timers stop once the transition settles.
- Capture stops when the active mode does not need it or the lights are paused.
- Notification polling runs only when enabled, with bounded traversal and
  coalesced accessibility callbacks.
- Menu color samples are tiny cached images. Schedules use a compact editor,
  rather than prebuilding every time and scene combination.

## Reproduce

Build in release mode and launch the signed app. Let it settle, then record
`vmmap -summary PID` while paused, in a solid color, and in each capture mode.
Wait at least a minute per mode and record display count, macOS, selected audio
source and whether notification detection is enabled. For a leak investigation,
repeat mode changes and sleep/wake cycles over a longer run.
