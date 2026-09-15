# fs-desktop-leds

Native macOS utility for controlling ELK-BLEDOM Bluetooth LED lights, with screen ambient lighting planned next.

**Status:** Project initialization. No working application or verified hardware compatibility yet.

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

The app target and build instructions will be added with the first implementation. There is no executable to build in this initial repository.

## Protocol references

- [TheSylex/ELK-BLEDOM-bluetooth-led-strip-controller](https://github.com/TheSylex/ELK-BLEDOM-bluetooth-led-strip-controller)
- [dave-code-ruiz/elkbledom](https://github.com/dave-code-ruiz/elkbledom)
- [qanshangi/duoCoStrip](https://github.com/qanshangi/duoCoStrip)

These are research references, not bundled dependencies. Review the license of any third-party code before incorporating it.

## License

[MIT](LICENSE).
