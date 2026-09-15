#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PWD/build/Desktop LEDs.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/DesktopLEDs" "$APP_DIR/Contents/MacOS/DesktopLEDs"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
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

# This is a direct-distribution build. App Sandbox requires an App Store
# provisioning profile, so its entitlements belong only in the separate
# App Store packaging flow.
SIGN_COMMAND=(codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY")
if [[ -n "$KEYCHAIN_PATH" ]]; then
  SIGN_COMMAND+=(--keychain "$KEYCHAIN_PATH")
fi
SIGN_COMMAND+=("$APP_DIR")
"${SIGN_COMMAND[@]}"
codesign --verify --strict "$APP_DIR"
printf 'Built: %s (signed by %s)\n' "$APP_DIR" "$SIGNING_IDENTITY"
