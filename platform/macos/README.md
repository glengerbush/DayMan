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
- `Shared` contains the Codable settings/snapshot types, an atomic App Group
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
- An Apple Developer Team with an App Group for device/distribution testing

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

In Xcode, select the `DayMan` scheme and your development team. Register these
identifiers in the Apple Developer portal and use the same values locally:

```text
App:       com.glengerbush.DayMan
Extension: com.glengerbush.DayMan.Widget
App Group: group.com.glengerbush.DayMan
```

Override the defaults without editing the shared configuration by creating
`Configuration/Local.xcconfig`:

```xcconfig
DAYMAN_DEVELOPMENT_TEAM = ABCDE12345
DAYMAN_BUNDLE_ID = com.example.DayMan
DAYMAN_WIDGET_BUNDLE_ID = com.example.DayMan.Widget
DAYMAN_APP_GROUP = group.com.example.DayMan
```

The three identifiers and both entitlements must agree exactly. The widget
cannot read the app's state when the App Group is absent or mismatched.

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
full platform envelope through an injected temporary App Group directory.
They also verify local-midnight queue selection, stale-queue rejection, and
same-day-only compatibility for a pre-queue version-1 envelope.

Before release, compare the fixture dial with the web reference at the same
size and verify:

- DST spring-forward and fall-back days
- polar day and polar night
- new, quarter, and full Moon phases
- a location/timezone update while the widget gallery is open
- leaving the app closed while the widget crosses local midnight
- full-surface click-through from every supported widget family

## Direct-download release

Direct distribution still requires Developer ID signing and Apple
notarization. No App Store listing is involved.

1. Store notarization credentials in the login keychain (never in the repo):

   ```sh
   xcrun notarytool store-credentials dayman-notary \
     --apple-id you@example.com \
     --team-id ABCDE12345 \
     --password app-specific-password
   ```

2. Archive and export:

   ```sh
   DAYMAN_DEVELOPMENT_TEAM=ABCDE12345 \
     platform/macos/scripts/archive.sh
   ```

3. Create, submit, staple, and verify the DMG:

   ```sh
   DAYMAN_NOTARY_PROFILE=dayman-notary \
     platform/macos/scripts/notarize-dmg.sh
   ```

4. Test the DMG on a clean macOS account, verify the Gatekeeper assessment,
   install the widget, and publish the DMG plus a SHA-256 checksum over HTTPS.

The scripts intentionally contain no certificate names, team IDs, Apple IDs,
passwords, or keychain profiles. CI should inject those values from secrets.

## Release checklist

- Re-run bootstrap so the embedded web bundle matches the release commit.
- Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- Confirm both targets show the intended Team and App Group capability.
- Run XCTest and exercise offline app launch.
- Confirm HTTPS map tiles load when online.
- Confirm location/timezone changes reload the widget timeline.
- Inspect signatures with `codesign --verify --deep --strict --verbose=2`.
- Notarize, staple, and assess the exact DMG being published.
- Publish its checksum and keep the PWA install option available.
