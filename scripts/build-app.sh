#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PWD/build/Desktop LEDs.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/DesktopLEDs" "$APP_DIR/Contents/MacOS/DesktopLEDs"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP_DIR/Contents/Resources/"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --entitlements Resources/DesktopLEDs.entitlements "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
