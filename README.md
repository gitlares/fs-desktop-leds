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

## Next: screen ambient lighting

- Read monitor arrangement from macOS automatically.
- Support selecting displays or regions and handle display configuration changes.
- Analyze small frames at a bounded rate, smooth color transitions, and limit Bluetooth updates.
- Pause capture when synchronization is disabled or the lights are disconnected.
- Measure CPU, memory, and incremental energy use on real hardware before making performance claims.

Treat the desk strip as one RGB zone until hardware testing establishes otherwise. Segment control and Bluetooth update rates are not yet verified.

## Development

Requires macOS 14 or later and Xcode 15 or later (Swift 5.9+). No third-party package dependencies.

```sh
swift test
bash scripts/build-app.sh
open "build/Desktop LEDs.app"
```

The script builds an optimized release executable, packages it as a native `.app`, and applies an ad-hoc signature with App Sandbox and the Bluetooth entitlement. This is a local development build, not a notarized release or an App Store submission. For stable development signing, set `CODE_SIGN_IDENTITY` to an available signing identity when running the script. macOS may request Bluetooth permission again after rebuilding an ad-hoc-signed app.

Open `Package.swift` in Xcode to edit the source. Launch the bundled app using the instructions above for Bluetooth permission testing, rather than the bare command-line executable.

### Connect and control

1. Power the desk's LED controller and close duoCo Strip on the iPhone to release its connection.
2. Open Desktop LEDs and click **Buscar luces**. Allow the macOS Bluetooth prompt.
3. Select **ELK-BLEDOM** and click **Conectar**. No prior pairing in System Settings is required for the expected controller.
4. Test **Encender**, the color presets, brightness, and **Apagar**.
5. If it connects but does not respond, expand **Compatibilidad y conexión**, select the alternate protocol, and try again. The variant is saved per device.

The app remembers the selected device after service discovery succeeds and attempts reconnection on subsequent launches. An unexpected disconnect triggers up to three retries with increasing delays. Use **Desconectar** to release the lights for the phone, or **Olvidar dispositivo** to remove the saved selection.

The menu bar provides power controls and can reopen the control window. UI values are requested settings, not live readings from the strip. A Bluetooth write does not establish that the lights visibly changed.

### Resource behavior

- Discovery stops after 10 seconds, on connection, or on cancellation.
- Connection and service discovery have a 15-second timeout.
- Pending writes are coalesced by command type and paced at no more than 10 per second; the queue holds at most three commands.
- Brightness is sent after releasing the slider. Color changes are coalesced during interaction.
- No polling timer, screen capture, network access, or persistent discovery in manual-control mode.
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
