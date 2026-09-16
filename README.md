# FS Desktop LEDs

**A little light for your workspace.**

Control ELK-BLEDOM desk lights from the macOS menu bar. Pick a color or scene,
follow your screen, or turn music into light.

[Download the beta](https://github.com/gitlares/fs-desktop-leds/releases/tag/v0.1.0-beta.1)
· [Website](https://gitlares.github.io/fs-desktop-leds/)
· [Report a test](https://github.com/gitlares/fs-desktop-leds/issues/new/choose)
· [♥ Support the project](https://www.paypal.com/donate/?hosted_button_id=7RDCBR3QXXEMJ)

## Why I built it

I bought a desk a year ago, and its LED lights could only be controlled from my
phone. I'm not a gamer. I just wanted to add a nice touch to the place where I
work, without reaching for another device every time.

FS Desktop LEDs puts those controls in the Mac's menu bar. FS stands for
**Fast and Simple**. That's the idea I want to keep.

— Daniel Lares

## Install

The first beta is for **Apple Silicon Macs running macOS 14 or later**.

1. Download the DMG from [GitHub Releases](https://github.com/gitlares/fs-desktop-leds/releases/tag/v0.1.0-beta.1).
2. Open it and drag **Desktop LEDs** into **Applications**.
3. Open the app and click the lightbulb in the menu bar.
4. Choose **Settings → Lights → Search for lights**, then select your strip.
5. Pick a color. If it does not respond, try **Settings → Lights → Protocol → Alternate** with the active mode off.

Close the phone's lighting app if it is holding the Bluetooth connection.
The app has no main window or Dock icon. Menus open sideways when you hover over
a mode; its settings appear below its choices.

## Modes

| Mode | What it does |
| --- | --- |
| Color | Named colors, brightness and smooth transitions. |
| Scenes | 14 presets for work, evenings, movies and more. |
| Animation | Rainbow, breathing, fade, alternating colors, blink and strobe. |
| Ambient | Dominant screen color, average color or screen edges; choose a display. |
| Music | Frequency colors, changing colors on detected beats, or a single-color volume pulse. |
| Game | Screen color with audio accents and optional palettes. No game telemetry. |
| Notifications | Experimental RGB flashes for visible macOS notification banners. |

Daily schedules, a sleep timer, a night brightness limit and launch at login are
available from the menu. English and Spanish follow the macOS app-language
preference; other languages fall back to English.

## Compatibility and beta limitations

- **Tested hardware:** ELK-BLEDOM, alternate protocol. Whole-strip colors,
  brightness and software alternation were confirmed on the development desk.
- **Other hardware:** unverified. A matching Bluetooth name does not prove compatibility.
- **LED addressing:** effects change the whole strip together. Individual pixels
  and independent segments are not supported by this release.
- **Firmware effects:** internal fade packets did not animate the test strip;
  normal animations generate RGB commands from the Mac instead.
- **Music:** uses Mac audio or the selected microphone. More tracks and output
  devices need testing. Protected content may restrict capture.
- **Notifications:** Accessibility detects visible banners. Focus-hidden notices,
  short-lived banners and unfamiliar macOS layouts may be missed. Message contents
  are not read. Use **Notifications → Test RGB flash** to preview the effect.
- **Schedules:** need the app running and the Mac awake. Scene schedules also need
  connected lights. Missed schedules are not replayed after sleep.
- **Quitting:** normal app termination requests power-off. Force quit, a crash or
  a lost connection cannot guarantee that request arrives.
- **State:** the controller does not report its physical power/color state.
  Changes made with another controller cannot be read back.

See the [beta notes](docs/releases/0.1.0-beta.1.md) and
[performance measurements](docs/PERFORMANCE.md) for validation details.

## Permissions and privacy

Bluetooth controls lights. Ambient and Mac audio use screen and system-audio
capture permission. Microphone access is requested only for that source.
Notifications ask for Accessibility only when enabled.

Samples are processed locally and discarded. There is no account, analytics,
advertising or media upload. Read the [privacy notes](PRIVACY.md).

## Updates

Choose **Check for Updates…** in the menu. Sparkle verifies signed update archives
before installation. It starts only when requested; automatic checks, downloads and
system-profile reporting are disabled. The updater contacts GitHub for the feed
and download. There is no telemetry. See [PRIVACY.md](PRIVACY.md).

## Testers welcome

Working setups are as useful as bug reports. Please include your Mac model,
macOS version, advertised device name, selected protocol and mode. For music,
include the audio source/output; for reconnection issues, include sleep/wake steps.

[Open a test report](https://github.com/gitlares/fs-desktop-leds/issues/new/choose).
Please omit private notifications, screenshots and unredacted device identifiers.

## Build from source

Install Xcode with a macOS 14+ SDK, then run `swift test` and `swift build -c release`.
To create a signed app, set `CODE_SIGN_IDENTITY` to your Developer ID identity and
`CODE_SIGN_KEYCHAIN` to your signing Keychain path, then run `bash scripts/build-app.sh`.
The output is `build/Desktop LEDs.app`. See [RELEASING.md](docs/RELEASING.md).

`LEDProtocol` contains packets and rendering/audio analysis. `LightingController`
coordinates modes; `MediaCaptureController` owns capture; `BluetoothController`
owns discovery and paced writes. New drivers belong in `LightDriver` and
`DriverCatalog` and require hardware validation.

## Contributing and license

[Contributions](CONTRIBUTING.md) are welcome. Keep the menu simple and avoid new
runtime dependencies. MIT licensed; see [LICENSE](LICENSE).

[Glow](https://github.com/kshivam654/glow) informed the feature inventory. This is
an independent Swift implementation. Packet references and attribution are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
