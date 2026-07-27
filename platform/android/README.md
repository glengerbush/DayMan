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
cannot guarantee. The center shows the snapshot date and fixed sunrise/sunset
times rather than a relative countdown that could become stale. Sun, twilight,
Moon, and event geometry remains fixed for the snapshot date.

Refreshes are requested:

- immediately after `saveClockSnapshot` or `refreshWidget`
- whenever the full app resumes
- every 30 minutes through unique WorkManager work
- just after midnight in the saved timezone
- after boot, date/time/timezone changes, app replacement, and widget enable

The 30-minute WorkManager interval is best-effort: Android may defer background
work for battery optimization or Doze. No runtime permission is required for
these refresh requests.

## Signing the direct-install APK

Android requires every installable APK to have a stable signature, even when
the APK never goes through an app store. DayMan uses a passwordless PKCS#8 key
and certificate bundle rather than a password-protected keystore.

Generate that bundle once, outside the repository:

```sh
platform/android/scripts/create-signing-bundle.sh
```

Back up `dayman-android-signing.tar.gz` securely. Every future update must use
the same key. Encode it to a text file, then copy the file contents only into
the GitHub Actions secret `DAYMAN_ANDROID_SIGNING_BUNDLE_BASE64`:

```sh
# Linux
base64 -w 0 dayman-android-signing.tar.gz \
  > dayman-android-signing-base64.txt

# macOS
base64 < dayman-android-signing.tar.gz |
  tr -d '\n' > dayman-android-signing-base64.txt
```

The release workflow builds `app-release-unsigned.apk`, aligns it, signs it
with Android SDK `apksigner`, verifies the signature, and publishes the
direct-install APK with a SHA-256 checksum. No Play Store account, password, or
app bundle is involved.

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
