# ClockSnapshot contract

`src/lib/clock-snapshot.ts` is the platform-neutral dial model used by the PWA
and every native widget. Native renderers do not calculate astronomy. They
decode the same JSON fields and draw the minute ranges, event markers, labels,
colors, Moon phase, and accessibility description supplied by the web core.

## Versioning

Both the snapshot and its platform envelope currently use `schemaVersion: 1`.
A native decoder must reject a future major version it does not understand.
Additive fields may be ignored.

Each `ClockSnapshot` includes:

- the selected IANA timezone, local `dateKey`, location, and widget size;
- JSON-safe ISO timestamps for calculation and expiry;
- shared dial geometry, palette, hour labels, and accessibility text;
- ordered Sun, civil, nautical, astronomical, and Moon arc ranges in local
  minutes from 0 through 1440;
- JSON-safe event times, minute positions, marker types, and dial visibility;
- Moon illumination/phase and the next sunrise or sunset.

The snapshot expires at the end of its local civil day. Hosts may update the
current-time hand more often, but they must not present a snapshot after its
date has passed.

## Rolling native state

Whenever the user saves a location or timezone, the full app writes a
`PlatformStateEnvelope` through the narrow platform bridge:

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-07-27T02:00:00.000Z",
  "settings": {
    "location": {}
  },
  "snapshot": {},
  "snapshots": []
}
```

`snapshot` is the current-day compatibility fallback. `snapshots` contains 32
consecutive local dates, starting today. At every refresh or timeline entry,
the widget selects the item whose `dateKey` matches the current date in the
saved IANA timezone. This lets midnight, boot, and timezone refreshes advance
the dial without a server, account, background WebView, or duplicated native
astronomy implementation.

After 32 days without opening DayMan, a widget must show a stale/open-the-app
state rather than silently labeling an expired dial as current. Opening the app
regenerates the queue locally.

Browsing a historical or future date in the full app never changes the widget
queue. Only saved location/timezone state is bridged.

## Bridge endpoints

- Android: `window.DayManAndroid.saveState(JSON.stringify(envelope))`
- macOS: `window.webkit.messageHandlers.daymanState.postMessage(envelope)`
- Linux/Tauri: `invoke("save_dayman_state", { state: envelope })`

The PWA has no native endpoint and treats persistence as a no-op.

## Fixtures

Reference JSON lives in `fixtures/clock-snapshots/`. It covers both New York
daylight-saving transitions, multiple Moon phases, and Tromsø polar day/night.
Regenerate and verify it with:

```sh
npm run fixtures
npm test
```

Native tests should decode these files directly. Renderer-specific snapshots
may be added, but their astronomical values must continue to match the shared
fixtures.
