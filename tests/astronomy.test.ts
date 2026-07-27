import { describe, expect, test } from 'vitest';

import { calculateDaySky } from '../src/lib/astronomy';
import type { SavedLocation } from '../src/lib/types';

const newYork: SavedLocation = {
  label: 'New York',
  latitude: 40.7128,
  longitude: -74.006,
  timezone: 'America/New_York',
  source: 'coordinates'
};

const tromso: SavedLocation = {
  label: 'Tromsø',
  latitude: 69.6492,
  longitude: 18.9553,
  timezone: 'Europe/Oslo',
  source: 'coordinates'
};

function intervalMinutes(intervals: { startMinute: number; endMinute: number }[]): number {
  return intervals.reduce(
    (total, interval) => total + interval.endMinute - interval.startMinute,
    0
  );
}

describe('daily sky calculation', () => {
  test('builds a chronological New York summer day', () => {
    const day = calculateDaySky(
      '2026-06-21',
      newYork,
      new Date('2026-06-21T16:00:00.000Z')
    );
    const eventKinds = day.events.map((event) => event.kind);

    expect(eventKinds).toContain('sunrise');
    expect(eventKinds).toContain('solar-noon');
    expect(eventKinds).toContain('sunset');
    expect(intervalMinutes(day.daylight)).toBeGreaterThan(14 * 60);
    expect(intervalMinutes(day.daylight)).toBeLessThan(16 * 60);
    expect(day.events.map((event) => event.time.getTime())).toEqual(
      [...day.events].map((event) => event.time.getTime()).sort((a, b) => a - b)
    );
    expect(day.moonIllumination).toBeGreaterThanOrEqual(0);
    expect(day.moonIllumination).toBeLessThanOrEqual(1);
  });

  test('shows less daylight in New York winter', () => {
    const summer = calculateDaySky('2026-06-21', newYork);
    const winter = calculateDaySky('2026-12-21', newYork);

    expect(intervalMinutes(winter.daylight)).toBeLessThan(10 * 60);
    expect(intervalMinutes(winter.daylight)).toBeLessThan(
      intervalMinutes(summer.daylight)
    );
  });

  test('finds the next solar horizon crossing beyond the selected day', () => {
    const afternoon = calculateDaySky(
      '2026-06-21',
      newYork,
      new Date('2026-06-21T16:00:00.000Z')
    );
    const evening = calculateDaySky(
      '2026-06-21',
      newYork,
      new Date('2026-06-22T01:00:00.000Z')
    );

    expect(afternoon.nextSolarEvent?.kind).toBe('sunset');
    expect(evening.nextSolarEvent?.kind).toBe('sunrise');
    expect(evening.nextSolarEvent?.time.getTime()).toBeGreaterThan(
      evening.referenceTime.getTime()
    );
  });

  test('handles polar day and polar night without invented crossings', () => {
    const summer = calculateDaySky('2026-06-21', tromso);
    const winter = calculateDaySky('2026-12-21', tromso);

    expect(summer.daylight).toEqual([{ startMinute: 0, endMinute: 1440 }]);
    expect(summer.events.some((event) => event.kind === 'sunrise')).toBe(false);
    expect(winter.daylight).toEqual([]);
    expect(winter.events.some((event) => event.kind === 'sunset')).toBe(false);
  });
});
