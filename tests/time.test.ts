import { describe, expect, test } from 'vitest';

import {
  civilDayRange,
  dateKeyInZone,
  localMinute,
  zonedDateTimeToUtc
} from '../src/lib/time';

describe('timezone conversion', () => {
  test('uses winter and summer New York offsets', () => {
    expect(
      zonedDateTimeToUtc('2026-01-15', 'America/New_York').toISOString()
    ).toBe('2026-01-15T05:00:00.000Z');
    expect(
      zonedDateTimeToUtc('2026-07-15', 'America/New_York').toISOString()
    ).toBe('2026-07-15T04:00:00.000Z');
  });

  test('represents a spring DST day as 23 real hours', () => {
    const { start, end } = civilDayRange('2026-03-08', 'America/New_York');
    expect((end.getTime() - start.getTime()) / 3_600_000).toBe(23);
  });

  test('projects instants into the selected timezone', () => {
    const instant = new Date('2026-07-26T04:30:00.000Z');
    expect(dateKeyInZone(instant, 'America/New_York')).toBe('2026-07-26');
    expect(dateKeyInZone(instant, 'America/Los_Angeles')).toBe('2026-07-25');
    expect(localMinute(instant, 'America/New_York')).toBe(30);
  });
});
