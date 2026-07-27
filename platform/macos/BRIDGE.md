# DayMan macOS bridge contract

The macOS app exposes exactly the Apple handler used by
`src/lib/platform-bridge.ts`:

```js
window.webkit.messageHandlers.daymanState.postMessage(state);
```

The host also injects a read-only capability marker before the first app
script:

```js
window.__DAYMAN_NATIVE__
// { platform: "macOS", bridgeVersion: 1, messageHandler: "daymanState" }
```

The web app must continue to work when the marker or handler is absent. That
keeps the PWA a first-class release.

## Payload

The message body is the exact `PlatformStateEnvelope` shared by Android, Apple,
Tauri, and custom hosts:

```js
{
  schemaVersion: 1,
  updatedAt: new Date().toISOString(),
  settings: {
    location: {
      label: "New York",
      latitude: 40.7128,
      longitude: -74.006,
      timezone: "America/New_York",
      source: "map"
    }
  },
  snapshot, // current/fallback ClockSnapshot
  snapshots // today plus 31 future local-date ClockSnapshots
}
```

The host rejects unsupported schema versions, invalid coordinates, unknown
IANA timezones, inconsistent settings/snapshot locations, unordered or
duplicate snapshot dates, queues larger than 32 days, invalid dates and event
minutes, and non-main-frame callers. It does not accept paths, URLs, JavaScript
source, or native method names.

After handling a message, the host emits a diagnostic
`dayman:native-result` window event:

```js
window.addEventListener("dayman:native-result", ({ detail }) => {
  // detail is { ok: true } or { ok: false, error: "..." }
});
```

PWA persistence remains the source of truth and must not wait for this event.

## App Group state

The bridge atomically replaces `platform-state-v1.json` in the configured App
Group. It asks WidgetKit to reload immediately for a location, current date,
schema, or queue-date change and otherwise no more than once per 25 minutes.
The widget opens the same envelope read-only. Each timeline entry selects the
snapshot whose `dateKey` matches that entry in the saved location's timezone;
if a non-empty queue has no match, the widget shows its refresh state rather
than stale geometry. A legacy envelope with an absent/empty queue may use
`snapshot` only while its `dateKey` matches the current local date.

`Shared/ClockModels.swift` is the Codable counterpart to
`src/lib/clock-snapshot.ts` and `src/lib/platform-bridge.ts`. The XCTest target
decodes every JSON file directly from `fixtures/clock-snapshots`; there is no
native copy to drift. An intentional contract change requires a new schema
version and fixtures.
