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
The downloadable app and DMG are Developer ID signed and Apple notarized.
You do not need Xcode, Python or a developer account to use the download.

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

## Using the app

Click the lightbulb in the menu bar, then hover over a mode to open its submenu.
Click a choice to apply it. Open the menu again to adjust its settings; brightness,
speed and other controls are grouped below the choices. A checkmark identifies
the selected option, and color samples help distinguish colors and scenes.

- **A fixed color:** open **Color**, choose a color, then use **Brightness** or
  **Smoothing** at the bottom of the submenu. **Scenes** applies a preset color
  and brightness together.
- **An animation:** open **Animation** and choose an effect. Use **Palette**,
  **Animation color**, **Speed** and **Brightness** to customize it. Effects
  animate the whole strip.
- **Screen sync:** open **Ambient**, choose how to sample the screen, and grant
  capture permission when macOS asks. Use **Display** to select your screen;
  adjust color intensity, smoothing and brightness in the same submenu.
- **Music:** play audio on your Mac, open **Music**, and select a response style.
  Under **Source**, choose Mac audio or the microphone. Grant the requested
  permission and adjust **Sensitivity** and **Brightness**. The pulse color
  setting is for the single-color pulse style.
- **Notification flashes:** open **Notifications** and enable **Light up for
  notifications**. Allow Accessibility access when prompted, then try **Test RGB
  flash**. The flash restores the preceding lighting state afterward. Automatic
  detection is experimental and only detects visible notification banners.
- **Timers and schedules:** use **Turn off after…** for a sleep timer, or
  **Settings → Schedules → Add daily schedule** to choose an hour, minute and
  scene or power-off action. Click **Add** to save the schedule. The app must be
  running and the Mac awake for schedules to run.
- **Stop or quit:** **Turn lights off** pauses lighting and capture while keeping
  the app available. **Quit Desktop LEDs** requests lights off and disconnects.

### If something does not work

- **No lights found:** check Bluetooth permission in System Settings, bring the
  strip closer, and close any phone app connected to it. Search again from
  **Settings → Lights**. Other controller models may not be compatible.
- **Connected but no color change:** turn the active mode off, switch the
  protocol under **Settings → Lights → Protocol**, then choose a fixed color.
  The tested ELK-BLEDOM controller uses **Alternate**.
- **Ambient or Music does not react:** check the selected display or audio source
  and the capture permissions in System Settings → Privacy & Security. If macOS
  asks you to quit and reopen the app after granting permission, do so. Protected
  media may prevent capture.
- **No notification flash:** try the manual RGB test first. For automatic alerts,
  check Accessibility permission and whether Focus is hiding notification banners.

Menu labels follow the macOS app language. The paths above use English labels.

## Compatibility and beta limitations

- **Tested hardware:** ELK-BLEDOM, alternate protocol. Whole-strip colors,
  brightness and software alternation were confirmed on the development desk.
- **Other hardware:** unverified. A matching Bluetooth name does not prove compatibility.
- **LED addressing:** effects change the whole strip together. Individual pixels
  and independent segments are not supported by this release.
- **Firmware effects:** the fade commands we tested did not animate the test
  strip. This does not establish that its firmware lacks effects: Glow uses a
  different packet layout that has not been validated on this controller.
  The beta's animations generate RGB commands from the Mac instead.
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

### Prerequisites

- macOS 14 or later and Git.
- Xcode with Swift 5.9 or later and a macOS 14+ SDK. Open Xcode once to complete
  its installation, and select its command-line tools in Xcode settings.
- Internet access for Swift Package Manager to fetch Sparkle, the update framework.

### Clone, test and compile

```sh
git clone https://github.com/gitlares/fs-desktop-leds.git
cd fs-desktop-leds
swift package resolve
swift test
swift build -c release
swift build -c release --show-bin-path
```

The last command prints the directory containing the `DesktopLEDs` executable.
Swift Package Manager fetches dependencies automatically; there is no separate
Python or Node.js installation step. Compiling and running the tests does not
require a paid Apple Developer account. A source build targets the current Mac's
architecture; the published beta has only been packaged for Apple Silicon.

### Create a signed application bundle

Use the bundled app for normal operation so macOS can associate Bluetooth,
capture permissions and Sparkle with a stable app identity. The packaging script
requires your own **Developer ID Application** certificate and its private key
in Keychain. Obtaining that certificate requires Apple Developer Program membership.

```sh
export CODE_SIGN_IDENTITY="YOUR_DEVELOPER_ID_CERTIFICATE_SHA1"
export CODE_SIGN_KEYCHAIN="/absolute/path/to/your-signing.keychain-db"
bash scripts/build-app.sh
open "build/Desktop LEDs.app"
```

Replace the placeholders with your own signing details. The script embeds Sparkle,
resources and localizations, then signs the nested components and app. It does not
notarize the app. Do not commit certificates, private keys or credentials.

For notarization, DMG packaging and publishing signed updates, see
[RELEASING.md](docs/RELEASING.md). If you distribute a fork, use your own bundle
identifier, update feed and Sparkle signing key instead of this project's feed.

`LEDProtocol` contains packets and rendering/audio analysis. `LightingController`
coordinates modes; `MediaCaptureController` owns capture; `BluetoothController`
owns discovery and paced writes. New drivers belong in `LightDriver` and
`DriverCatalog` and require hardware validation.

## Contributing and license

[Contributions](CONTRIBUTING.md) are welcome. Keep the menu simple and avoid new
runtime dependencies. MIT licensed; see [LICENSE](LICENSE).

## Acknowledgements

[Glow](https://github.com/kshivam654/glow), by Shivam, inspired the feature set,
scene names and the idea of combining screen and sound with desk lighting.
Thank you for sharing that work. FS Desktop LEDs is an independent native Swift
implementation; it does not bundle or execute Glow's Python code. Scene colors,
brightness values and the lighting implementation are maintained here.

The ELK-BLEDOM packet layouts were adapted from
[dave-code-ruiz/elkbledom](https://github.com/dave-code-ruiz/elkbledom), and
[Sparkle](https://sparkle-project.org/) provides signed updates. Attribution and
license notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

### Hardware effects versus software animations

Glow exposes commands that ask the strip's firmware to run an effect. Our public
beta runs its animations on the Mac and sends changing RGB colors to the strip.
Both approaches can animate the whole strip; neither proves individual LED
addressing is available.

Our diagnostic fade tests on one ELK-BLEDOM controller had no visible response.
Glow's effect command uses a 10-byte frame with speed included; our diagnostic
variant uses a 9-byte frame and a separate speed command. Compatibility with
Glow's variant remains untested. A Bluetooth device name alone cannot establish
which packet format or built-in effects its firmware supports.

## More apps by Daniel Lares

- **[FS PDF Compressor](https://gitlares.github.io/fs-pdf-compressor/)** — Compress PDFs locally on macOS, Windows and Linux. [Source code](https://github.com/gitlares/fs-pdf-compressor).
- **[FS User Stories](https://gitlares.github.io/fs-user-stories/)** — Organize user stories with local data and optional Git sharing. [Source code](https://github.com/gitlares/fs-user-stories).
