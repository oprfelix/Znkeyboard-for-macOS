#!/usr/bin/env bash
# Builds build/ZnKeyboard.app from the Swift package: compiles a release binary, lays out the
# bundle with Info.plist and the prompt files, and signs it.
#
# Signing uses the "Developer ID Application" identity in the keychain when there is one, with
# the hardened runtime and a secure timestamp that notarization needs; macOS then keeps the
# Accessibility permission across updates. Without it the app is signed ad hoc, which runs
# locally but needs Accessibility granted again after every rebuild.
#
# Usage: scripts/build_app.sh            (then: open build/ZnKeyboard.app)
#        SIGN_IDENTITY=- scripts/build_app.sh   (force ad hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.4.7"
BUILD="20"
APP="build/ZnKeyboard.app"

# One app for Apple silicon and Intel Macs, so downloads and in-app updates need no choice of build.
# Each architecture has its own build folder: sharing one breaks the second build after the first.
BINS=()
for ARCH in arm64 x86_64; do
    swift build -c release --arch "$ARCH" --scratch-path ".build/$ARCH"
    BINS+=("$(swift build -c release --arch "$ARCH" --scratch-path ".build/$ARCH" --show-bin-path)/ZnKeyboardMac")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/ZnKeyboardMac"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R Resources/prompts "$APP/Contents/Resources/prompts"
# Regenerate with: swift scripts/make_icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed with $SIGN_IDENTITY"
else
    codesign --force --sign - --timestamp=none "$APP"
    echo "Signed ad hoc"
fi
echo "Built $APP ($VERSION)"
