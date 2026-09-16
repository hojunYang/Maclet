# Maclet

Maclet is a local-first macOS menu bar command launcher. It stores terminal commands, presents an `NSStatusItem` command center, captures output, and keeps local run history.

## Build

```sh
swift build
swift test
swift run Maclet
```

## Package the App

```sh
Scripts/package-app.sh
open dist/Maclet.app
```

The generated app bundle uses ad-hoc signing by default and sets `LSUIElement` so the app lives in the menu bar instead of the Dock.

## Build a DMG

```sh
Scripts/build-dmg.sh
```

The DMG is written to `dist/Maclet-1.0.0.dmg`. For distribution under another Apple Developer account, run the script on that account owner's Mac with their bundle ID and Developer ID certificate:

```sh
MACLET_BUNDLE_ID="com.example.maclet" \
MACLET_VERSION="1.0.0" \
MACLET_BUILD_NUMBER="1" \
MACLET_CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
MACLET_NOTARY_PROFILE="maclet-notary" \
Scripts/build-dmg.sh
```

`MACLET_NOTARY_PROFILE` is optional. When set, the script submits the DMG with `notarytool` and staples the accepted ticket. Create the profile once on the distribution Mac with `xcrun notarytool store-credentials`.

Maclet registers `fn + V` as its default global shortcut. You can change, disable, or reset it from Settings without granting Input Monitoring or Accessibility permission.

For a feature-by-feature source map, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Admin Commands

Commands marked as requiring admin rights use macOS administrator authorization before execution. Custom commands and Keep Awake share one `AdminAuthorizationCoordinator`, and passwords are passed to `sudo` through standard input without being stored.

## Data Migration

On first launch, Maclet moves existing command, settings, and run-history data from the previous application-support directory when the new Maclet directory does not yet exist.

## Private Relay

iCloud Private Relay does not expose a stable app-facing toggle API. Maclet includes a preset that opens the relevant System Settings area instead of pretending to control the setting silently.
