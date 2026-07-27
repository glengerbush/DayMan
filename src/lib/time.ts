interface ZonedParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

const partFormatterCache = new Map<string, Intl.DateTimeFormat>();

function partFormatter(timezone: string): Intl.DateTimeFormat {
  let formatter = partFormatterCache.get(timezone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23'
    });
    partFormatterCache.set(timezone, formatter);
  }
  return formatter;
}

export function zonedParts(date: Date, timezone: string): ZonedParts {
  const values = Object.fromEntries(
    partFormatter(timezone)
      .formatToParts(date)
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, Number(part.value)])
  );

  return values as unknown as ZonedParts;
}

function timeZoneOffsetMs(date: Date, timezone: string): number {
  const parts = zonedParts(date, timezone);
  const representedAsUtc = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second
  );
  return representedAsUtc - Math.floor(date.getTime() / 1000) * 1000;
}

export function zonedDateTimeToUtc(
  dateKey: string,
  timezone: string,
  hour = 0,
  minute = 0
): Date {
  const [year, month, day] = dateKey.split('-').map(Number);
  const utcGuess = Date.UTC(year, month - 1, day, hour, minute);
  const firstOffset = timeZoneOffsetMs(new Date(utcGuess), timezone);
  let candidate = utcGuess - firstOffset;
  const secondOffset = timeZoneOffsetMs(new Date(candidate), timezone);

  if (secondOffset !== firstOffset) {
    candidate = utcGuess - secondOffset;
  }

  return new Date(candidate);
}

export function civilDayRange(dateKey: string, timezone: string): {
  start: Date;
  end: Date;
} {
  return {
    start: zonedDateTimeToUtc(dateKey, timezone),
    end: zonedDateTimeToUtc(shiftDateKey(dateKey, 1), timezone)
  };
}

export function dateKeyInZone(date: Date, timezone: string): string {
  const parts = zonedParts(date, timezone);
  return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`;
}

export function localMinute(date: Date, timezone: string): number {
  const parts = zonedParts(date, timezone);
  return parts.hour * 60 + parts.minute + parts.second / 60;
}

export function shiftDateKey(dateKey: string, days: number): string {
  const [year, month, day] = dateKey.split('-').map(Number);
  const shifted = new Date(Date.UTC(year, month - 1, day + days, 12));
  return shifted.toISOString().slice(0, 10);
}

export function formatClockTime(date: Date, timezone: string): string {
  return new Intl.DateTimeFormat(undefined, {
    timeZone: timezone,
    hour: 'numeric',
    minute: '2-digit'
  }).format(date);
}

export function formatLongDate(dateKey: string, timezone: string): string {
  const date = zonedDateTimeToUtc(dateKey, timezone, 12);
  return new Intl.DateTimeFormat(undefined, {
    timeZone: timezone,
    weekday: 'long',
    month: 'long',
    day: 'numeric'
  }).format(date);
}

export function isValidTimezone(timezone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: timezone }).format();
    return true;
  } catch {
    return false;
  }
}
