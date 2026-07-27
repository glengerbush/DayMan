# DayMan for Android

This directory is a self-contained Capacitor 8 package. Its native project is
under `android/`, which keeps Android tooling and dependencies out of the PWA.
The bundled web application remains the full DayMan UI; the Glance home-screen
widget is a display-only rendered dial, and tapping anywhere on it opens the
full app.

## Prerequisites

- Node.js supported by the root DayMan project
- JDK 21 (the version required by the Capacitor 8 Android template)
- Android SDK Platform 36 and Build Tools 36
- `ANDROID_HOME` or an `android/local.properties` file containing `sdk.dir=...`

Install the isolated Capacitor dependencies once:

```sh
cd platform/android
npm ci
```

Syncing builds the root app with relative asset paths for an embedded WebView,
copies that native build, and runs Capacitor:

```sh
npm run sync
```

`npm run android:debug` creates a debug APK. `npm run android:open` opens the
synced native project in Android Studio.

## Widget bridge contract

The Android shell exposes the exact bridge consumed by
`src/lib/platform-bridge.ts`: `window.DayManAndroid.saveState(payload)`. The
shared PWA persists its state immediately after a location, timezone, or
today-snapshot refresh. Browsing a historical date changes only the interactive
web dial and does not replace the widget snapshot:

```ts
window.DayManAndroid?.saveState(JSON.stringify(platformStateEnvelope));
```

The outer `PlatformStateEnvelope` has `schemaVersion`, `updatedAt`,
`settings.location`, `snapshot`, and `snapshots`. The `snapshots` rolling queue
contains today plus 31 future local dates. On every render and midnight refresh,
Android derives today in `settings.location.timezone`, selects the queue entry
with that `dateKey`, and shows its “Open DayMan” state if a non-empty queue no
longer contains today. It never presents an older queued day as current. For a
legacy envelope with no queue, Android uses `snapshot` only when that snapshot
is dated today; otherwise it also shows “Open DayMan.” This keeps the widget’s
geometry fresh across midnight for up to 32 local dates without launching the
PWA or accessing a network, while failing visibly and safely after the queue
expires.

Its `ClockSnapshot` version 1 matches the shared fixtures under
`fixtures/clock-snapshots/`:

- `schemaVersion`, `calculatedAt`, `expiresAt`, `dateKey`, and IANA `timezone`
- `location` containing `label`, `latitude`, and `longitude`
- `arcs`, an array of named arc objects with `kind`, `color`, and
  `{ startMinute, endMinute }` ranges
- `events`, an array containing event `kind`, `minute`, `timeLabel`, and
  `visibleOnDial`
- `moon.illumination` in the range 0–1 and `moon.phaseName`
- `nextSolarEvent` and `accessibilityText`

The bridge validates both schema versions and every queued snapshot, writes the
raw envelope to app-private `SharedPreferences`, queues an immediate widget
update, and schedules the next saved-timezone midnight refresh. No account,
server, or network connection is used by the widget.

The renderer intentionally omits a live current-time hand. Android widget
updates are opportunistic, so a minute hand would imply precision the host
cannot guarantee. Sun, twilight, Moon, and event geometry remains fixed for the
snapshot date.

Refreshes are requested:

- immediately after `saveClockSnapshot` or `refreshWidget`
- every 30 minutes through unique WorkManager work
- just after midnight in the saved timezone
- after boot, date/time/timezone changes, app replacement, and widget enable

## Signing direct APKs and app bundles

Create a private release key outside this repository:

```sh
keytool -genkeypair -v -keystore dayman-release.jks \
  -alias dayman -keyalg RSA -keysize 4096 -validity 10000
```

Export the four signing values only in the release environment:

```sh
export DAYMAN_ANDROID_KEYSTORE=/absolute/private/path/dayman-release.jks
export DAYMAN_ANDROID_STORE_PASSWORD='...'
export DAYMAN_ANDROID_KEY_ALIAS=dayman
export DAYMAN_ANDROID_KEY_PASSWORD='...'
export DAYMAN_ANDROID_VERSION_CODE=1
export DAYMAN_ANDROID_VERSION_NAME=0.1.0
```

Then run:

```sh
npm run release:apk
npm run release:aab
```

Signed outputs (when all signing variables are set) are:

- `android/app/build/outputs/apk/release/app-release.apk`
- `android/app/build/outputs/bundle/release/app-release.aab`

If all four signing variables are absent, Gradle can still create an unsigned
release artifact such as `app-release-unsigned.apk` for CI validation. A
partial signing configuration fails early. Never commit a keystore or passwords.
Direct downloads should publish the signed APK alongside a SHA-256 checksum;
the AAB is retained for a possible future Play release.

## Validation

`npm run validate` performs host-only structural checks. With the Android SDK
installed, `npm test` also syncs the current PWA and runs the Kotlin unit tests.
For a device/emulator smoke test:

1. Install the debug APK and open DayMan.
2. Save a location/timezone through the bridge.
3. Add “DayMan dial” from the Android widget picker.
4. Confirm the arcs and labels match the PWA fixture.
5. Tap the widget and confirm the existing DayMan task opens.
6. Change timezone and run
   `adb shell am broadcast -a android.intent.action.TIMEZONE_CHANGED`.
7. Confirm the widget refreshes without network access.
