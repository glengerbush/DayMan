import { readdir, readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

import {
  CLOCK_SNAPSHOT_QUEUE_DAYS,
  CLOCK_SNAPSHOT_VERSION,
  createClockSnapshot,
  createClockSnapshotQueue,
  parseClockSnapshot,
  serializeClockSnapshot,
  type ClockSnapshot
} from '../src/lib/clock-snapshot';

const fixtureDirectory = new URL(
  '../fixtures/clock-snapshots/',
  import.meta.url
);

async function loadFixtures(): Promise<
  Array<{ name: string; snapshot: ClockSnapshot }>
> {
  const names = (await readdir(fixtureDirectory))
    .filter((name) => name.endsWith('.json'))
    .sort();
  return Promise.all(
    names.map(async (name) => ({
      name,
      snapshot: parseClockSnapshot(
        await readFile(new URL(name, fixtureDirectory), 'utf8')
      )
    }))
  );
}

function daylightMinutes(snapshot: ClockSnapshot): number {
  const daylight = snapshot.arcs.find((arc) => arc.kind === 'daylight');
  return (
    daylight?.ranges.reduce(
      (total, range) => total + range.endMinute - range.startMinute,
      0
    ) ?? 0
  );
}

describe('ClockSnapshot contract', () => {
  test('round-trips a deterministic JSON-safe snapshot', () => {
    const snapshot = createClockSnapshot({
      at: new Date('2026-06-21T16:00:00.000Z'),
      latitude: 40.7128,
      longitude: -74.006,
      timezone: 'America/New_York',
      locationLabel: 'New York',
      size: { width: 420, height: 420, density: 1 }
    });

    expect(parseClockSnapshot(serializeClockSnapshot(snapshot))).toEqual(
      snapshot
    );
    expect(snapshot.schemaVersion).toBe(CLOCK_SNAPSHOT_VERSION);
    expect(snapshot.arcs.map((arc) => arc.kind)).toEqual([
      'astronomical',
      'nautical',
      'civil',
      'daylight',
      'moon'
    ]);
    expect(snapshot.events.every((event) => event.time.endsWith('Z'))).toBe(
      true
    );
  });

  test('expires at the selected timezone day boundary', () => {
    const snapshot = createClockSnapshot({
      at: new Date('2026-06-21T16:00:00.000Z'),
      latitude: 40.7128,
      longitude: -74.006,
      timezone: 'America/New_York',
      locationLabel: 'New York',
      size: { width: 420, height: 420 }
    });
    const lifetimeMinutes =
      (Date.parse(snapshot.expiresAt) - Date.parse(snapshot.calculatedAt)) /
      60_000;

    expect(snapshot.expiresAt).toBe('2026-06-22T04:00:00.000Z');
    expect(lifetimeMinutes).toBe(12 * 60);
  });

  test('builds a rolling queue across local date boundaries', () => {
    const snapshots = createClockSnapshotQueue({
      at: new Date('2026-03-08T12:00:00.000Z'),
      latitude: 40.7128,
      longitude: -74.006,
      timezone: 'America/New_York',
      locationLabel: 'New York',
      size: { width: 420, height: 420 }
    });

    expect(snapshots).toHaveLength(CLOCK_SNAPSHOT_QUEUE_DAYS);
    expect(snapshots[0].dateKey).toBe('2026-03-08');
    expect(snapshots[1].dateKey).toBe('2026-03-09');
    expect(snapshots.at(-1)?.dateKey).toBe('2026-04-08');
    expect(snapshots.every((snapshot) => snapshot.schemaVersion === 1)).toBe(
      true
    );
  });

  test('keeps generated fixtures synchronized with the web reference model', async () => {
    const fixtures = await loadFixtures();

    expect(fixtures).toHaveLength(7);
    for (const { snapshot } of fixtures) {
      expect(
        createClockSnapshot({
          at: new Date(snapshot.calculatedAt),
          dateKey: snapshot.dateKey,
          latitude: snapshot.location.latitude,
          longitude: snapshot.location.longitude,
          timezone: snapshot.timezone,
          locationLabel: snapshot.location.label,
          size: snapshot.size
        })
      ).toEqual(snapshot);
    }
  });

  test('covers polar day, polar night, DST, and several Moon phases', async () => {
    const fixtures = await loadFixtures();
    const byName = Object.fromEntries(
      fixtures.map(({ name, snapshot }) => [name, snapshot])
    );
    const moonPhases = new Set(
      fixtures
        .filter(({ name }) => name.includes('moon-phase'))
        .map(({ snapshot }) => snapshot.moon.phaseName)
    );

    expect(daylightMinutes(byName['tromso-polar-day.json'])).toBe(1440);
    expect(daylightMinutes(byName['tromso-polar-night.json'])).toBe(0);
    expect(byName['new-york-dst-spring.json'].dateKey).toBe('2026-03-08');
    expect(byName['new-york-dst-fall.json'].dateKey).toBe('2026-11-01');
    expect(moonPhases.size).toBeGreaterThanOrEqual(3);
  });

  test('rejects unsupported snapshot versions', () => {
    expect(() =>
      parseClockSnapshot(
        JSON.stringify({
          schemaVersion: 99,
          calculatedAt: '2026-01-01T00:00:00.000Z',
          expiresAt: '2026-01-01T00:30:00.000Z',
          arcs: [],
          events: []
        })
      )
    ).toThrow('Unsupported or invalid ClockSnapshot');
  });
});
