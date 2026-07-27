# DayMan deployment and native widget pathway

## Implementation status

The code portions of this pathway are implemented:

- PWA manifest, offline service worker, install menu, GitHub Pages deployment,
  and generated release verification
- Versioned `ClockSnapshot` model, shared DST/polar/Moon fixtures, and native
  persistence bridge
- Rolling 32-day native snapshot queue so widgets can advance at midnight
  without a server or background WebView
- Capacitor Android host, Kotlin/Glance widget, scheduling, tests, passwordless
  release signing, and a direct-install APK build
- SwiftUI/WKWebView macOS host, WidgetKit extension, App Group storage,
  XcodeGen project, tests, ad-hoc signing, and DMG scripts
- Tauri Linux host, XDG state bridge, Plasma 6 plasmoid, GNOME Shell
  extension, Flatpak/native/AUR packaging definitions, installers, and tests
- GitHub Actions checks for the web, Android, macOS, and Linux tracks, plus
  tag-driven native package publishing to GitHub Releases

Run the complete host-available validation with `npm run check:all`. Platform
source and release instructions live under `platform/android`,
`platform/macos`, and `platform/linux`. The remaining steps are release
operations requiring external accounts, signing identities, accepted SDK
licenses, target operating systems, and a Git remote; they are not missing
application code.

## PWA release

DayMan is a static Vite application. A production build is created with
`npm ci && npm run build`, and the generated `dist/` directory can be published
to any static HTTPS host.

The current web manifest provides:

- A stable application identity with a deployment-aware scope and start URL
- Standalone display mode and matching dark launch/theme colors
- The original SVG application icon
- 192 px and 512 px PNG fallbacks
- A separate full-bleed 512 px maskable icon whose important artwork stays
  inside the manifest safe zone
- An Apple touch icon and install-title metadata

The generated service worker precaches the app shell, ZIP centroid data, Moon
texture, and application icons. Astronomical calculations and saved location
settings remain local. The pin map still needs a network connection for tiles
that the user has not viewed before.

Before a public launch:

1. Deploy `dist/` over HTTPS. The included GitHub Pages workflow supports both
   root sites and repository subpaths.
2. Verify installation and offline reload in current Chrome/Android, Safari,
   and a Chromium browser on Linux.
3. Add the public URL and a support contact to store listings and map-provider
   configuration.
4. Keep the service worker and HTML on conservative cache headers so an
   `autoUpdate` release can reach installed users.
5. The low-traffic demo can continue using direct OpenStreetMap raster tiles
   while it keeps attribution visible, fetches only the active viewport, and
   retains the current seven-day cache. Switch providers if usage grows.

## What the manifest cannot do

A web manifest can install the PWA, but it cannot register an Android home
screen widget, a macOS WidgetKit extension, or a Linux desktop widget. Those
surfaces require platform packages. The native widgets should remain display
only; one full-surface click opens DayMan.

## Shared widget contract

The calculation and dial-model code is exposed by
`src/lib/clock-snapshot.ts`. Given a time, latitude, longitude, timezone, date,
and widget size, it returns a versioned `ClockSnapshot` containing:

- Sun, twilight, and Moon arcs expressed as minute ranges
- Rise, set, noon, phase, and next-event values
- Dial labels, colors, and accessibility text
- The time at which the snapshot was calculated and when it expires

The web dial is the reference renderer. Shared JSON fixtures cover
daylight-saving transitions, polar day/night, and several Moon phases so every
native renderer can be compared with the PWA.

The full app writes the selected location, timezone, current snapshot, and a
rolling 32-day snapshot queue to the platform bridge. The widget reads only
that saved state and selects the current local date. No account or server is
required. See `docs/clock-snapshot-contract.md`.

## Platform plan

| Platform | Full app package | Widget implementation | Distribution |
| --- | --- | --- | --- |
| Android | Capacitor shell around the Vite build | Kotlin Jetpack Glance `AppWidget` showing a rendered dial image; one `PendingIntent` opens the app | Signed direct-install APK from GitHub Releases |
| macOS | Small SwiftUI app containing a bundled `WKWebView` build | WidgetKit source is implemented, but its App Group state sharing requires Apple provisioning and remains unconfigured in the ad-hoc release | Ad-hoc-signed DMG from GitHub Releases; users clear quarantine before launch |
| Linux | Tauri 2 shell around the Vite build | Plasma 6 plasmoid for KDE; separate GNOME Shell extension for a panel surface | Flatpak plus Tauri `.deb`, `.rpm`, AppImage, and an AUR package |

### Android

Use Capacitor because the app is already a static web build and the generated
Android project can contain ordinary Kotlin components. The Glance widget
should render from the saved `ClockSnapshot` and put a single launch action over
its entire surface.

Android's normal periodic `AppWidget` mechanism does not accept periods below
30 minutes, and background work is still subject to power limits. Therefore:

- Recompute immediately when the app saves a location or timezone.
- Refresh at midnight, timezone changes, device boot, and the platform's
  permitted periodic cadence.
- Treat the Sun/Moon/twilight geometry and event times as exact for the day.
- Either show the current-time hand rounded to the last refresh or omit that
  hand in the widget. Do not imply minute precision that the host cannot keep.

### macOS

Use a native SwiftUI host because WidgetKit extensions and their signing,
entitlements, shared App Group, previews, and store packaging are all managed
directly by Xcode. Bundle the Vite output in the app and expose only a narrow
JavaScript bridge for location/timezone persistence.

WidgetKit is timeline based rather than continuously running. Generate future
timeline entries for predictable dial states, reload the timeline when the app
changes location, and use `widgetURL` on the widget root so any click opens
DayMan. As on Android, the moving hand must respect the system refresh budget.

### Linux

Linux distributions do not share one desktop-widget API. Packaging the app for
Debian, Fedora, and Arch does not by itself make one widget work on GNOME, KDE,
and other desktop environments.

Ship the Tauri full app once, then support desktop environments explicitly:

- Plasma 6: a QML plasmoid can live on the desktop or panel and is the closest
  match to the requested clock widget.
- GNOME: a GJS Shell extension can provide a non-interactive panel clock that
  launches DayMan. GNOME does not provide the same general desktop-widget
  surface as Plasma.
- Cinnamon/Xfce: consider a Cinnamon desklet or Xfce panel plugin only after
  demand is known; these are additional implementations.

Both Linux widgets can read a versioned snapshot from the XDG configuration
directory and launch the installed `dayman` desktop application on click.
Unlike mobile widget hosts, Shell/Plasma widgets can update the time hand every
minute.

## Recommended release order

1. Publish and validate the PWA.
2. Extract and test `ClockSnapshot`; add the web-to-native settings bridge.
3. Release Android first, because it validates the static-image widget and
   background-update model.
4. Release macOS with WidgetKit and the same snapshot fixtures.
5. Release the Tauri Linux app through Flatpak and portable/native packages.
6. Release Plasma 6 first, then GNOME Shell; describe Linux support by desktop
   environment as well as by distribution.

This order keeps the current PWA deployable while native work is added in
separate package directories rather than coupling the web app to any one
platform.

## Primary platform references

- [Web Application Manifest](https://www.w3.org/TR/appmanifest/)
- [Android app widget updates](https://developer.android.com/develop/ui/views/appwidgets/advanced)
- [Jetpack Glance](https://developer.android.com/develop/ui/compose/glance)
- [Capacitor](https://capacitorjs.com/docs)
- [Apple WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Tauri distribution formats](https://v2.tauri.app/distribute/)
- [KDE Plasma widgets](https://develop.kde.org/docs/plasma/widget/)
- [GNOME Shell extensions](https://gjs.guide/extensions/)
- [OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/)
