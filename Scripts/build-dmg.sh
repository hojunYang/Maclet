#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Maclet"
VERSION="${MACLET_VERSION:-1.0.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

if [[ -n "${MACLET_NOTARY_PROFILE:-}" && "${MACLET_CODESIGN_IDENTITY:--}" == "-" ]]; then
    echo "MACLET_CODESIGN_IDENTITY is required when MACLET_NOTARY_PROFILE is set." >&2
    exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/maclet-dmg.XXXXXX")"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

MACLET_RELAUNCH=0 "$ROOT_DIR/Scripts/package-app.sh"

ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ "${MACLET_CODESIGN_IDENTITY:--}" != "-" ]]; then
    codesign --force --timestamp --sign "$MACLET_CODESIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "${MACLET_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$MACLET_NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH"
echo "Created $DMG_PATH"
