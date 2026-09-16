#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Maclet"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="$ROOT_DIR/Resources/Maclet.icns"
MACLET_BUNDLE_ID="${MACLET_BUNDLE_ID:-com.local.maclet}"
MACLET_VERSION="${MACLET_VERSION:-1.0.0}"
MACLET_BUILD_NUMBER="${MACLET_BUILD_NUMBER:-1}"
MACLET_CODESIGN_IDENTITY="${MACLET_CODESIGN_IDENTITY:--}"
MACLET_RELAUNCH="${MACLET_RELAUNCH:-0}"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/swiftpm-home" "$ROOT_DIR/.build/module-cache"
export SWIFTPM_HOME="$ROOT_DIR/.build/swiftpm-home"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

swift build --disable-sandbox -c "$BUILD_CONFIG" --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/$BUILD_CONFIG/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ICON_FILE" "$RESOURCES_DIR/Maclet.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Maclet</string>
    <key>CFBundleIconFile</key>
    <string>Maclet.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.maclet</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Maclet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026</string>
</dict>
</plist>
PLIST

plutil -replace CFBundleIdentifier -string "$MACLET_BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$MACLET_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$MACLET_BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

if [[ "$MACLET_CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP_DIR"
else
    codesign --force --options runtime --timestamp --sign "$MACLET_CODESIGN_IDENTITY" "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "Created $APP_DIR"

if [[ "$MACLET_RELAUNCH" == "1" ]]; then
    EXECUTABLE_PATH="$MACOS_DIR/$APP_NAME"
    RUNNING_PIDS="$(pgrep -fx "$EXECUTABLE_PATH" || true)"

    if [[ -n "$RUNNING_PIDS" ]]; then
        for PID in $RUNNING_PIDS; do
            CHILD_PIDS="$(pgrep -P "$PID" || true)"
            if [[ -n "$CHILD_PIDS" ]]; then
                echo "Cannot relaunch Maclet while it has a running child process (PID $CHILD_PIDS)." >&2
                echo "Stop the running command, or package without relaunching via MACLET_RELAUNCH=0." >&2
                exit 1
            fi
        done

        kill -TERM $RUNNING_PIDS

        for _ in {1..30}; do
            STILL_RUNNING="$(pgrep -fx "$EXECUTABLE_PATH" || true)"
            if [[ -z "$STILL_RUNNING" ]]; then
                break
            fi
            sleep 0.1
        done

        STILL_RUNNING="$(pgrep -fx "$EXECUTABLE_PATH" || true)"
        if [[ -n "$STILL_RUNNING" ]]; then
            echo "Maclet did not stop after 3 seconds; forcing it to close." >&2
            kill -KILL $STILL_RUNNING
        fi
    fi

    open "$APP_DIR"

    for _ in {1..30}; do
        NEW_PID="$(pgrep -fx "$EXECUTABLE_PATH" || true)"
        if [[ -n "$NEW_PID" ]]; then
            echo "Relaunched $APP_DIR (PID $NEW_PID)"
            exit 0
        fi
        sleep 0.1
    done

    echo "Created the app, but it did not relaunch within 3 seconds." >&2
    exit 1
fi
