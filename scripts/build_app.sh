#!/bin/bash
# Build Clackey.app (and optionally a release zip).
#
#   scripts/build_app.sh            # native arch, ad-hoc signed -> build/Clackey.app
#   UNIVERSAL=1 scripts/build_app.sh zip   # arm64 + x86_64, plus build/Clackey-<version>.zip
#
# Env: BUNDLE_ID, VERSION, SIGN_ID (codesign identity; "-" = ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Clackey"
BUNDLE_ID="${BUNDLE_ID:-io.github.aakocval.Clackey}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
SIGN_ID="${SIGN_ID:--}"

# Refuse values that could break out of the sed substitution / plist below.
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "invalid BUNDLE_ID" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "invalid VERSION" >&2; exit 1; }
[[ "$BUILD" =~ ^[0-9.]+$ ]] || { echo "invalid BUILD" >&2; exit 1; }

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp -R Resources/Packs "$APP/Contents/Resources/Packs"
[[ -d Resources/Mouse ]] && cp -R Resources/Mouse "$APP/Contents/Resources/Mouse"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

strip -x "$APP/Contents/MacOS/$APP_NAME"
xattr -cr "$APP"   # no extended attributes, so zips carry no ._ AppleDouble files
# Hardened runtime + App Sandbox (see Resources/Clackey.entitlements).
codesign --force --options runtime --timestamp=none \
    --entitlements Resources/Clackey.entitlements --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"

if [[ "${1:-}" == "zip" ]]; then
    ZIP="build/$APP_NAME-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
    echo "Zipped $ZIP"
fi
