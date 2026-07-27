import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

import { expect, test } from 'vitest';

import { createClockSnapshot } from '../src/lib/clock-snapshot';

const outputDirectory = resolve(
  import.meta.dirname,
  '../fixtures/clock-snapshots'
);
const cases = [
  {
    name: 'new-york-dst-spring',
    at: '2026-03-08T12:00:00.000Z',
    latitude: 40.7128,
    longitude: -74.006,
    timezone: 'America/New_York',
    locationLabel: 'New York'
  },
  {
    name: 'new-york-dst-fall',
    at: '2026-11-01T17:00:00.000Z',
    latitude: 40.7128,
    longitude: -74.006,
    timezone: 'America/New_York',
    locationLabel: 'New York'
  },
  {
    name: 'new-york-moon-phase-a',
    at: '2026-08-12T16:00:00.000Z',
    latitude: 40.7128,
    longitude: -74.006,
    timezone: 'America/New_York',
    locationLabel: 'New York'
  },
  {
    name: 'new-york-moon-phase-b',
    at: '2026-08-20T16:00:00.000Z',
    latitude: 40.7128,
    longitude: -74.006,
    timezone: 'America/New_York',
    locationLabel: 'New York'
  },
  {
    name: 'new-york-moon-phase-c',
    at: '2026-08-28T16:00:00.000Z',
    latitude: 40.7128,
    longitude: -74.006,
    timezone: 'America/New_York',
    locationLabel: 'New York'
  },
  {
    name: 'tromso-polar-day',
    at: '2026-06-21T12:00:00.000Z',
    latitude: 69.6492,
    longitude: 18.9553,
    timezone: 'Europe/Oslo',
    locationLabel: 'Tromsø'
  },
  {
    name: 'tromso-polar-night',
    at: '2026-12-21T12:00:00.000Z',
    latitude: 69.6492,
    longitude: 18.9553,
    timezone: 'Europe/Oslo',
    locationLabel: 'Tromsø'
  }
];

test('generate ClockSnapshot fixtures', async () => {
  await mkdir(outputDirectory, { recursive: true });

  for (const fixture of cases) {
    const snapshot = createClockSnapshot({
      ...fixture,
      at: new Date(fixture.at),
      size: {
        width: 420,
        height: 420,
        density: 1
      }
    });
    await writeFile(
      resolve(outputDirectory, `${fixture.name}.json`),
      `${JSON.stringify(snapshot, null, 2)}\n`,
      'utf8'
    );
  }

  expect(cases).toHaveLength(7);
});
