#!/usr/bin/env bash
# Builds the release DMG: the signed app, a drag-to-Applications disk image, Apple's notarization
# and the stapled ticket. Needs the Developer ID certificate and the notary profile (see
# docs/new-computer.md in zn-keyboard). Leaves build/ZnKeyboard-macOS-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-znkeyboard-notary}"
VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' scripts/build_app.sh)
DMG="build/ZnKeyboard-macOS-$VERSION.dmg"
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "No Developer ID Application certificate in the keychain." >&2; exit 1; }

scripts/build_app.sh

rm -rf build/dmg-stage "$DMG"
mkdir build/dmg-stage
cp -R build/ZnKeyboard.app build/dmg-stage/
ln -s /Applications build/dmg-stage/Applications
hdiutil create -volname ZnKeyboard -srcfolder build/dmg-stage -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee "build/notary-$VERSION.log"
grep -q 'status: Accepted' "build/notary-$VERSION.log" || { echo "Notarization failed." >&2; exit 1; }
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "Built $DMG ($VERSION)"
