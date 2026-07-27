import {
  Body,
  Equator,
  Horizon,
  Illumination,
  MoonPhase,
  Observer,
  SearchAltitude,
  SearchHourAngle,
  SearchRiseSet
} from 'astronomy-engine';

import {
  civilDayRange,
  dateKeyInZone,
  localMinute,
  zonedDateTimeToUtc,
  zonedParts
} from './time';
import type {
  BodyPosition,
  DaySky,
  NextSolarEvent,
  SavedLocation,
  SkyEvent,
  SkyEventKind,
  SkyInterval
} from './types';

interface Crossing {
  time: Date;
  direction: 1 | -1;
}

interface EventDefinition {
  kind: SkyEventKind;
  label: string;
  body: SkyEvent['body'];
  time: Date | null;
}

const DAY_MS = 86_400_000;

function bodyPosition(body: Body, date: Date, observer: Observer): BodyPosition {
  const equatorial = Equator(body, date, observer, true, true);
  const horizontal = Horizon(
    date,
    observer,
    equatorial.ra,
    equatorial.dec,
    'normal'
  );
  return {
    altitude: horizontal.altitude,
    azimuth: horizontal.azimuth
  };
}

function eventInRange(
  search: () => { date: Date } | { time: { date: Date } } | null,
  start: Date,
  end: Date
): Date | null {
  const result = search();
  if (!result) return null;
  const date = 'date' in result ? result.date : result.time.date;
  return date >= start && date < end ? date : null;
}

function riseSet(
  body: Body,
  observer: Observer,
  direction: 1 | -1,
  start: Date,
  end: Date
): Date | null {
  const limitDays = (end.getTime() - start.getTime()) / DAY_MS + 0.02;
  return eventInRange(
    () => SearchRiseSet(body, observer, direction, start, limitDays),
    start,
    end
  );
}

function altitudeCrossing(
  observer: Observer,
  direction: 1 | -1,
  altitude: number,
  start: Date,
  end: Date
): Date | null {
  const limitDays = (end.getTime() - start.getTime()) / DAY_MS + 0.02;
  return eventInRange(
    () => SearchAltitude(Body.Sun, observer, direction, start, limitDays, altitude),
    start,
    end
  );
}

function culmination(body: Body, observer: Observer, start: Date, end: Date): Date | null {
  return eventInRange(() => SearchHourAngle(body, observer, 0, start, 1), start, end);
}

function nextSolarEvent(observer: Observer, referenceTime: Date): NextSolarEvent | null {
  const searchStart = new Date(referenceTime.getTime() + 1000);
  const sunrise = SearchRiseSet(Body.Sun, observer, 1, searchStart, 370);
  const sunset = SearchRiseSet(Body.Sun, observer, -1, searchStart, 370);

  if (!sunrise && !sunset) return null;
  if (!sunset || (sunrise && sunrise.date <= sunset.date)) {
    return sunrise ? { kind: 'sunrise', time: sunrise.date } : null;
  }
  return { kind: 'sunset', time: sunset.date };
}

function intervalsFromCrossings(
  crossings: Crossing[],
  timezone: string,
  fallbackAbove: boolean
): SkyInterval[] {
  const ordered = crossings.sort((a, b) => a.time.getTime() - b.time.getTime());
  if (ordered.length === 0) {
    return fallbackAbove ? [{ startMinute: 0, endMinute: 1440 }] : [];
  }

  let above = ordered[0].direction === -1;
  let cursor = 0;
  const intervals: SkyInterval[] = [];

  for (const crossing of ordered) {
    const minute = Math.max(0, Math.min(1440, localMinute(crossing.time, timezone)));
    if (above && minute > cursor) {
      intervals.push({ startMinute: cursor, endMinute: minute });
    }
    above = crossing.direction === 1;
    cursor = minute;
  }

  if (above && cursor < 1440) {
    intervals.push({ startMinute: cursor, endMinute: 1440 });
  }

  return intervals;
}

function phaseName(phaseDegrees: number): string {
  const names = [
    'New moon',
    'Waxing crescent',
    'First quarter',
    'Waxing gibbous',
    'Full moon',
    'Waning gibbous',
    'Last quarter',
    'Waning crescent'
  ];
  return names[Math.round(phaseDegrees / 45) % 8];
}

function makeEvent(
  definition: EventDefinition,
  timezone: string
): SkyEvent | null {
  if (!definition.time) return null;
  return {
    kind: definition.kind,
    label: definition.label,
    time: definition.time,
    minute: localMinute(definition.time, timezone),
    body: definition.body
  };
}

export function calculateDaySky(
  dateKey: string,
  location: SavedLocation,
  now = new Date()
): DaySky {
  const observer = new Observer(location.latitude, location.longitude, 0);
  const { start, end } = civilDayRange(dateKey, location.timezone);
  const midpoint = new Date((start.getTime() + end.getTime()) / 2);
  const isToday = dateKey === dateKeyInZone(now, location.timezone);
  const currentLocalTime = zonedParts(now, location.timezone);
  const referenceTime = isToday
    ? now
    : zonedDateTimeToUtc(
        dateKey,
        location.timezone,
        currentLocalTime.hour,
        currentLocalTime.minute
      );

  const sunrise = riseSet(Body.Sun, observer, 1, start, end);
  const sunset = riseSet(Body.Sun, observer, -1, start, end);
  const moonrise = riseSet(Body.Moon, observer, 1, start, end);
  const moonset = riseSet(Body.Moon, observer, -1, start, end);

  const civilDawn = altitudeCrossing(observer, 1, -6, start, end);
  const civilDusk = altitudeCrossing(observer, -1, -6, start, end);
  const nauticalDawn = altitudeCrossing(observer, 1, -12, start, end);
  const nauticalDusk = altitudeCrossing(observer, -1, -12, start, end);
  const astronomicalDawn = altitudeCrossing(observer, 1, -18, start, end);
  const astronomicalDusk = altitudeCrossing(observer, -1, -18, start, end);

  const sunAtMidpoint = bodyPosition(Body.Sun, midpoint, observer);
  const moonAtMidpoint = bodyPosition(Body.Moon, midpoint, observer);

  const events = [
    makeEvent(
      { kind: 'astronomical-dawn', label: 'Astronomical dawn', body: 'twilight', time: astronomicalDawn },
      location.timezone
    ),
    makeEvent(
      { kind: 'nautical-dawn', label: 'Nautical dawn', body: 'twilight', time: nauticalDawn },
      location.timezone
    ),
    makeEvent(
      { kind: 'civil-dawn', label: 'Civil dawn', body: 'twilight', time: civilDawn },
      location.timezone
    ),
    makeEvent({ kind: 'sunrise', label: 'Sunrise', body: 'sun', time: sunrise }, location.timezone),
    makeEvent(
      { kind: 'solar-noon', label: 'Solar noon', body: 'sun', time: culmination(Body.Sun, observer, start, end) },
      location.timezone
    ),
    makeEvent({ kind: 'sunset', label: 'Sunset', body: 'sun', time: sunset }, location.timezone),
    makeEvent(
      { kind: 'civil-dusk', label: 'Civil dusk', body: 'twilight', time: civilDusk },
      location.timezone
    ),
    makeEvent(
      { kind: 'nautical-dusk', label: 'Nautical dusk', body: 'twilight', time: nauticalDusk },
      location.timezone
    ),
    makeEvent(
      { kind: 'astronomical-dusk', label: 'Astronomical dusk', body: 'twilight', time: astronomicalDusk },
      location.timezone
    ),
    makeEvent({ kind: 'moonrise', label: 'Moonrise', body: 'moon', time: moonrise }, location.timezone),
    makeEvent(
      { kind: 'lunar-noon', label: 'Lunar noon', body: 'moon', time: culmination(Body.Moon, observer, start, end) },
      location.timezone
    ),
    makeEvent({ kind: 'moonset', label: 'Moonset', body: 'moon', time: moonset }, location.timezone)
  ].filter((event): event is SkyEvent => event !== null);

  const illumination = Illumination(Body.Moon, referenceTime);
  const phase = MoonPhase(referenceTime);

  return {
    dateKey,
    events: events.sort((a, b) => a.time.getTime() - b.time.getTime()),
    daylight: intervalsFromCrossings(
      [
        ...(sunrise ? [{ time: sunrise, direction: 1 as const }] : []),
        ...(sunset ? [{ time: sunset, direction: -1 as const }] : [])
      ],
      location.timezone,
      sunAtMidpoint.altitude > 0
    ),
    civilLight: intervalsFromCrossings(
      [
        ...(civilDawn ? [{ time: civilDawn, direction: 1 as const }] : []),
        ...(civilDusk ? [{ time: civilDusk, direction: -1 as const }] : [])
      ],
      location.timezone,
      sunAtMidpoint.altitude > -6
    ),
    nauticalLight: intervalsFromCrossings(
      [
        ...(nauticalDawn ? [{ time: nauticalDawn, direction: 1 as const }] : []),
        ...(nauticalDusk ? [{ time: nauticalDusk, direction: -1 as const }] : [])
      ],
      location.timezone,
      sunAtMidpoint.altitude > -12
    ),
    astronomicalLight: intervalsFromCrossings(
      [
        ...(astronomicalDawn ? [{ time: astronomicalDawn, direction: 1 as const }] : []),
        ...(astronomicalDusk ? [{ time: astronomicalDusk, direction: -1 as const }] : [])
      ],
      location.timezone,
      sunAtMidpoint.altitude > -18
    ),
    moonVisible: intervalsFromCrossings(
      [
        ...(moonrise ? [{ time: moonrise, direction: 1 as const }] : []),
        ...(moonset ? [{ time: moonset, direction: -1 as const }] : [])
      ],
      location.timezone,
      moonAtMidpoint.altitude > 0
    ),
    sunPosition: bodyPosition(Body.Sun, referenceTime, observer),
    moonPosition: bodyPosition(Body.Moon, referenceTime, observer),
    moonIllumination: illumination.phase_fraction,
    moonPhaseAngle: phase,
    moonPhaseName: phaseName(phase),
    nextSolarEvent: nextSolarEvent(observer, referenceTime),
    referenceTime,
    isToday
  };
}
