#!/usr/bin/env bash
# Builds build/ZnKeyboard.app from the Swift package: compiles a release binary, lays out the
# bundle with Info.plist and the prompt files, and signs it ad hoc so it runs locally.
#
# Usage: scripts/build_app.sh            (then: open build/ZnKeyboard.app)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.2.1"
BUILD="3"
APP="build/ZnKeyboard.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/ZnKeyboardMac"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ZnKeyboardMac"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R Resources/prompts "$APP/Contents/Resources/prompts"
# Regenerate with: swift scripts/make_icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP ($VERSION)"
