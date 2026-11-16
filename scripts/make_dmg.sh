#!/bin/bash
# Package build/Clackey.app into build/Clackey-<version>.dmg: a disk image that opens to
# Clackey next to an Applications shortcut, so installing is one drag.
#
#   scripts/make_dmg.sh             # after scripts/build_app.sh
#
# Env: SIGN_ID (codesign identity; "-" = ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Clackey.app"
[[ -d "$APP" ]] || { echo "build $APP first (scripts/build_app.sh)" >&2; exit 1; }
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DMG="build/Clackey-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr "$APP" "$STAGE/Clackey.app"
ln -s /Applications "$STAGE/Applications"
# Disk icon in Finder and on the desktop
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# Build writable first so the volume's "custom icon" flag can be set, then compress.
RW="$STAGE.rw.dmg"
MNT="$(mktemp -d)"
trap 'hdiutil detach -quiet "$MNT" 2>/dev/null || true; rm -rf "$STAGE" "$RW" "$MNT"' EXIT
hdiutil create -quiet -volname "Clackey" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
hdiutil attach -quiet -nobrowse -mountpoint "$MNT" "$RW"
xcrun SetFile -a C "$MNT"
hdiutil detach -quiet "$MNT"

rm -f "$DMG"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
codesign --force --sign "${SIGN_ID:--}" "$DMG"
hdiutil verify -quiet "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
