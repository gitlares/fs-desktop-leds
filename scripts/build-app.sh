#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
"${SWIFT_EXECUTABLE:-swift}" build -c release
BIN_DIR="$("${SWIFT_EXECUTABLE:-swift}" build -c release --show-bin-path)"
APP_DIR="$PWD/build/Desktop LEDs.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/DesktopLEDs" "$APP_DIR/Contents/MacOS/DesktopLEDs"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp -R Resources/en.lproj Resources/es.lproj "$APP_DIR/Contents/Resources/"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP_DIR/Contents/Resources/"

# TCC (Bluetooth and Screen Recording) identifies an application by its team
# and bundle identifier. An ad-hoc signature changes with each build, making
# macOS ask for the same permission again. Direct builds therefore require a
# stable Developer ID identity.
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
KEYCHAIN_PATH="${CODE_SIGN_KEYCHAIN:-}"
if [[ -n "$KEYCHAIN_PATH" && -z "$SIGNING_IDENTITY" ]]; then
  # Local development and direct distribution use Developer ID. App Store
  # builds require a distinct provisioning profile and are not produced here.
  # The SHA-1 avoids ambiguity when the same certificate appears twice.
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | sed -nE '/Developer ID Application/s/^[[:space:]]*[0-9]+\) ([0-9A-F]+).*/\1/p' | head -n 1)"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  printf '%s\n' 'Set CODE_SIGN_IDENTITY and CODE_SIGN_KEYCHAIN to a stable Developer ID identity.' >&2
  exit 1
fi

# Direct distribution uses hardened runtime and Developer ID signing.
SIGN_COMMAND=(codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY")
if [[ -n "$KEYCHAIN_PATH" ]]; then
  SIGN_COMMAND+=(--keychain "$KEYCHAIN_PATH")
fi
FRAMEWORK_SOURCE="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP_DIR/Contents/Frameworks"
ditto "$FRAMEWORK_SOURCE" "$FRAMEWORK"
for component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  "${SIGN_COMMAND[@]}" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/$component"
done
"${SIGN_COMMAND[@]}" "$FRAMEWORK"
"${SIGN_COMMAND[@]}" "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf 'Built: %s (signed by %s)\n' "$APP_DIR" "$SIGNING_IDENTITY"
