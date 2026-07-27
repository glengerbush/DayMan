# ClockSnapshot fixtures

These JSON files are the renderer contract shared by the PWA and native
widgets. Regenerate them after an intentional schema or astronomy change:

```bash
npm run fixtures
```

The set covers both New York daylight-saving transitions, three different
Moon phases, and Tromsø polar day and polar night. Native tests should decode
these files directly and compare their dial-model output with the values in
the fixture rather than reimplementing the astronomical calculations.

Each snapshot expires at its local civil-day boundary. Native state stores a
rolling 32-day array of these snapshots as documented in
`docs/clock-snapshot-contract.md`.
