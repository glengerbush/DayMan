import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

import { detectTimezone, lookupZipCode } from '../src/lib/location';

describe('location lookup', () => {
  test.each([
    [40.7128, -74.006, 'America/New_York'],
    [34.0522, -118.2437, 'America/Los_Angeles'],
    [33.4484, -112.074, 'America/Phoenix'],
    [51.5074, -0.1278, 'Europe/London']
  ])('detects the timezone at %s, %s', (latitude, longitude, expected) => {
    expect(detectTimezone(latitude as number, longitude as number)).toBe(expected);
  });

  test('ships the 2025 Census ZIP representative points', async () => {
    const raw = await readFile(
      new URL('../src/lib/data/zcta-2025.json', import.meta.url),
      'utf8'
    );
    const zctas = JSON.parse(raw) as Record<string, [number, number]>;

    expect(Object.keys(zctas).length).toBe(33_791);
    expect(zctas['10001']).toEqual([40.750649, -73.997298]);
    expect(zctas['90210']).toEqual([34.100517, -118.41463]);
  });

  test('loads an offline ZIP lookup through the application module graph', async () => {
    await expect(lookupZipCode('10001')).resolves.toMatchObject({
      postalCode: '10001',
      latitude: 40.750649,
      longitude: -73.997298,
      timezone: 'America/New_York',
      source: 'postal'
    });
  });
});
