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

# TCC (Bluetooth and Screen Recording) identifies a signed application by its
# team and bundle identifier. Ad-hoc signatures change with each build and make
# macOS ask for the same permission repeatedly, so prefer a stable identity.
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
KEYCHAIN_PATH="${CODE_SIGN_KEYCHAIN:-}"
if [[ -n "$KEYCHAIN_PATH" && -z "$SIGNING_IDENTITY" ]]; then
  # Local development and direct distribution use Developer ID. App Store
  # builds require a distinct provisioning profile and are not produced here.
  # The SHA-1 avoids ambiguity when the same certificate appears twice.
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | sed -nE '/Developer ID Application/s/^[[:space:]]*[0-9]+\) ([0-9A-F]+).*/\1/p' | head -n 1)"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  printf '%s\n' 'Warning: set CODE_SIGN_KEYCHAIN to use stable signing; ad-hoc builds may request permissions after every rebuild.' >&2
fi

SIGN_COMMAND=(codesign --force --sign "$SIGNING_IDENTITY" --entitlements Resources/DesktopLEDs.entitlements)
if [[ -n "$KEYCHAIN_PATH" ]]; then
  SIGN_COMMAND+=(--keychain "$KEYCHAIN_PATH")
fi
SIGN_COMMAND+=("$APP_DIR")
"${SIGN_COMMAND[@]}"
codesign --verify --strict "$APP_DIR"
printf 'Built: %s (signed by %s)\n' "$APP_DIR" "$SIGNING_IDENTITY"
