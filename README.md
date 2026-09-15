# fs-desktop-leds

Native macOS utility for controlling ELK-BLEDOM Bluetooth LED lights, with screen ambient lighting planned next.

**Status:** macOS manual-control MVP implemented and locally buildable. Hardware response still needs validation on the target desk. Screen synchronization is not implemented yet.

## First MVP

- Discover nearby ELK-BLEDOM devices using CoreBluetooth.
- Let the user select and connect to their light controller.
- Control power, RGB color, and brightness.
- Show Bluetooth permission, connection, and error states.
- Handle disconnects without continuous scanning or busy retry loops.

Initial test hardware: an Apple Silicon M3 MacBook Pro and a standing desk whose LED controller advertises as `ELK-BLEDOM` and is currently controlled with duoCo Strip.

## Technology

- Swift and SwiftUI for the macOS application.
- CoreBluetooth for Bluetooth Low Energy communication.
- ScreenCaptureKit for the future screen synchronization feature.

Keep the Bluetooth protocol, device connection, and interface separate. Linux support is a future goal; no Rust or Qt dependency is required for the macOS MVP.

### Driver architecture

The app-level control vocabulary is deliberately small: power, RGB color, and brightness. Each controller family is represented by a `LightDriver`, which is responsible for three things: deciding whether it supports an advertised device name, declaring its BLE write characteristic, and encoding the common controls into device-specific packets.

`DriverCatalog` is the only registration point for built-in drivers. CoreBluetooth never contains vendor names, UUIDs, or packet layouts, and SwiftUI only speaks in common controls. To add a controller family, implement `LightDriver`, add it to the catalog, and write driver-level tests; the discovery, reconnection, queueing, UI, and future ambient engine remain unchanged.

## Next: screen ambient lighting

- Read monitor arrangement from macOS automatically.
- Support selecting displays or regions and handle display configuration changes.
- Analyze small frames at a bounded rate, smooth color transitions, and limit Bluetooth updates.
- Pause capture when synchronization is disabled or the lights are disconnected.
- Measure CPU, memory, and incremental energy use on real hardware before making performance claims.

Treat the desk strip as one RGB zone until hardware testing establishes otherwise. Segment control and Bluetooth update rates are not yet verified.

### Ambient mode

Ambient mode uses ScreenCaptureKit and automatically includes every active display exposed by macOS. One display produces one sample; multiple displays are captured independently and their average colors are weighted by display area. `SCDisplay.frame` and `displayID` are retained by the capture layer, so a later placement-aware feature can use the existing macOS layout without changing the Bluetooth or driver layers.

Capture is deliberately bounded: each display is scaled to 64 pixels wide, sampled at most at 5 fps, has a queue depth of 3, and never captures audio. The mixer smooths scene transitions, ignores imperceptibly small RGB differences, and outputs at most 5 Bluetooth updates per second. It stops when the toggle is disabled or the light disconnects.

The first activation requires macOS Screen Recording permission. If macOS asks, grant it to Desktop LEDs; if it was previously denied, the Ambient section provides **Abrir ajustes de Grabación de pantalla**. Enable Desktop LEDs there, then quit and reopen the app before activating Ambient again. The implementation does not record, save, upload, or transmit screen images. It reduces each frame locally to one color and discards the pixels immediately.

## Development

Requires macOS 14 or later and Xcode 15 or later (Swift 5.9+). No third-party package dependencies.

```sh
swift test
bash scripts/build-app.sh
open "build/Desktop LEDs.app"
```

The script builds an optimized release executable and packages it as a native `.app`. To preserve Bluetooth and Screen Recording permission across rebuilds, sign with a stable Developer ID identity and its exact keychain:

```sh
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db" bash scripts/build-app.sh
```

The script selects the App Store signing certificate used by FS User Stories from that keychain by fingerprint, falling back to Developer ID when needed. It falls back to ad-hoc signing when `CODE_SIGN_KEYCHAIN` is absent; use that only for disposable local builds, because macOS may request permissions after every rebuild. This is a local development build, not a notarized release or an App Store submission.

Open `Package.swift` in Xcode to edit the source. Launch the bundled app using the instructions above for Bluetooth permission testing, rather than the bare command-line executable.

### Connect and control

1. Power the desk's LED controller and close duoCo Strip on the iPhone to release its connection.
2. Open Desktop LEDs and click **Buscar luces**. Allow the macOS Bluetooth prompt. The MVP also shows nearby unsupported BLE advertisements to make controller discovery diagnosable; only supported devices can be connected.
3. Select **ELK-BLEDOM** and click **Conectar**. No prior pairing in System Settings is required for the expected controller.
4. Test **Encender**, the color presets, brightness, and **Apagar**.
5. If it connects but does not respond, expand **Compatibilidad y conexión**, select the alternate protocol, and try a color again. The selected variant applies immediately and is saved per device. This variant sends the documented ELK-BLEDOM frames beginning `7E 04 04` for power and `7E 07 05 03` for RGB.

The app remembers the selected device after service discovery succeeds and attempts reconnection on subsequent launches. An unexpected disconnect triggers up to three retries with increasing delays. Use **Desconectar** to release the lights for the phone, or **Olvidar dispositivo** to remove the saved selection.

The menu bar provides power controls and can reopen the control window. UI values are requested settings, not live readings from the strip. A Bluetooth write does not establish that the lights visibly changed.

### Resource behavior

- Discovery stops after 10 seconds, on connection, or on cancellation.
- Connection and service discovery have a 15-second timeout.
- Pending writes are coalesced by command type and paced at no more than 10 per second; the queue holds at most three commands.
- Brightness is sent after releasing the slider. Color changes are coalesced during interaction.
- No polling timer, screen capture, network access, or persistent discovery in manual-control mode.
- Ambient mode uses bounded, low-resolution ScreenCaptureKit streams only while enabled.
- Sleep cancels active work; wake can reconnect the selected device.

The CPU, memory, and energy budget has not yet been benchmarked.

### Validation

Automated tests cover reference wire packets, brightness bounds, burst coalescing, and dropping stale commands when switching off. They do not replace a hardware test.

Manual checks before a release: permission denied, Bluetooth off/on, scan cancellation and empty results, physical color/power/brightness response, reconnect after disconnect and sleep, remembering/forgetting the device, and reopening controls from the menu bar.

## Protocol references

- [TheSylex/ELK-BLEDOM-bluetooth-led-strip-controller](https://github.com/TheSylex/ELK-BLEDOM-bluetooth-led-strip-controller)
- [dave-code-ruiz/elkbledom](https://github.com/dave-code-ruiz/elkbledom)
- [qanshangi/duoCoStrip](https://github.com/qanshangi/duoCoStrip)

These are research references, not bundled runtime dependencies. The command layouts use the MIT-licensed `elkbledom` model definitions; attribution and its license are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE).
