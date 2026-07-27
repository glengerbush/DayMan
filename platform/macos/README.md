# DayMan for macOS

This directory contains the native macOS host and its display-only WidgetKit
extension. The host bundles the static Vite build in `WKWebView`; it does not
replace or fork the PWA. Clicking anywhere on the widget opens DayMan through
the `dayman://open` URL.

## Architecture

- `DayManApp` is a sandboxed SwiftUI application containing a local-file
  `WKWebView`. Normal links open in the default browser. The map can still load
  HTTPS tiles through the app's outbound-network entitlement.
- `DayManApp/NativeBridge.swift` validates the shared state envelope. See
  [BRIDGE.md](BRIDGE.md) for the versioned wire contract.
- `Shared` contains the Codable settings/snapshot types, an atomic shared-file
  store, and the SwiftUI clock renderer compiled into both targets.
- `DayManWidget` creates a rolling day of half-hour timeline entries. Each
  entry selects its local date from the 32-day snapshot queue, so crossing
  midnight changes geometry without launching the app. WidgetKit may coalesce
  those entries.
- `project.yml` is the checked-in XcodeGen project specification. Generated
  `.xcodeproj`, archives, exports, and signing credentials should remain local.

The widget does no networking and no astronomical calculation. The full app
writes today's reference-renderer snapshot plus 31 future local dates for the
saved location and timezone after a settings change or scheduled refresh.
Browsing another date affects only the full web dial. If no saved state exists,
the widget asks the user to open DayMan.

## Requirements

- macOS 14 or newer
- Current Xcode command-line tools
- Node.js matching the root `package.json`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Xcode and WidgetKit are Apple-only, so the Swift targets cannot be compiled on
Linux. The asset generation, web build, JSON validation, plist validation, and
shell validation are cross-platform.

On Linux, run all available macOS static checks with:

```sh
platform/macos/scripts/validate-linux.sh
```

## First build

From the repository root:

```sh
platform/macos/scripts/bootstrap-xcode.sh
open platform/macos/DayMan.xcodeproj
```

The bootstrap script:

1. installs the locked web dependencies with `npm ci`;
2. type-checks the web application;
3. runs the shared `npm run build:native` target and syncs its relative-base
   Vite output into `Resources/Web`;
4. derives the complete macOS icon set from the existing SVG;
5. generates the Xcode project.

The source uses these stable identifiers:

```text
App:       com.glengerbush.DayMan
Extension: com.glengerbush.DayMan.Widget
State:     ~/Library/Application Support/DayMan/platform-state-v1.json
```

The app and widget remain sandboxed. Their entitlements grant access only to
the DayMan Application Support directory: read/write for the app and read-only
for the widget. No App Group, Apple development team, or provisioning profile
is required by the direct-download build.

## Tests

After bootstrap, run the `DayMan` scheme tests in Xcode or:

```sh
xcodebuild test \
  -project platform/macos/DayMan.xcodeproj \
  -scheme DayMan \
  -destination 'platform=macOS'
```

The tests decode all version-1 fixtures directly from the repository's shared
`fixtures/clock-snapshots` directory, exercise validation, and round-trip a
full platform envelope through an injected temporary shared-state directory.
They also verify local-midnight queue selection, stale-queue rejection, and
same-day-only compatibility for a pre-queue version-1 envelope.

Before release, compare the fixture dial with the web reference at the same
size and verify:

- DST spring-forward and fall-back days
- polar day and polar night
- crescent, quarter, gibbous, and full Moon phases at varied illumination
- a location/timezone update while the widget gallery is open
- leaving the app closed while the widget crosses local midnight
- full-surface click-through from every supported widget family

## Direct-download release

DayMan is distributed as an ad-hoc-signed, unnotarized DMG. It does not require
an Apple Developer account or signing certificate.

1. Build and ad-hoc sign the app:

   ```sh
   platform/macos/scripts/archive.sh
   ```

2. Package the DMG and checksum:

   ```sh
   platform/macos/scripts/package-dmg.sh
   ```

3. After dragging DayMan into Applications, clear its quarantine attributes
   before opening it:

   ```sh
   xattr -cr /Applications/DayMan.app
   ```

The GitHub release workflow performs the first two steps automatically. Test
the DMG on a clean macOS account before publishing it. The archive step signs
the widget executable and extension from the inside out, then asks PlugInKit to
index the result; packaging fails if macOS does not recognize the widget.

The full app and widget use the same narrowly scoped shared file in this
configuration. Open the app and choose a location before adding the widget so
the initial snapshot queue exists.

## Release checklist

- Re-run bootstrap so the embedded web bundle matches the release commit.
- Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- Confirm the app and widget are both ad-hoc signed.
- Run XCTest and exercise offline app launch.
- Confirm HTTPS map tiles load when online.
- Confirm the widget appears in the gallery after the app's first launch.
- Confirm `pluginkit -m -A -D -i com.glengerbush.DayMan.Widget` lists the
  installed extension.
- Confirm the widget reads the app's selected location and changes after a new
  location is saved.
- Inspect signatures with `codesign --verify --deep --strict --verbose=2`.
- Install the DMG and verify the documented `xattr -cr` step.
- Publish its checksum and keep the PWA install option available.
