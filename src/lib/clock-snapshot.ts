import { calculateDaySky } from './astronomy';
import {
  civilDayRange,
  dateKeyInZone,
  localMinute,
  shiftDateKey
} from './time';
import type {
  DaySky,
  SavedLocation,
  SkyEvent,
  SkyEventKind,
  SkyInterval
} from './types';

export const CLOCK_SNAPSHOT_VERSION = 1 as const;
export const CLOCK_SNAPSHOT_QUEUE_DAYS = 32;

export type ClockArcKind =
  | 'astronomical'
  | 'nautical'
  | 'civil'
  | 'daylight'
  | 'moon';

export type ClockMarkerKind = 'rising' | 'setting' | 'peak';

export interface ClockSnapshotSize {
  width: number;
  height: number;
  density?: number;
}

export interface ClockSnapshotInput {
  at: Date;
  dateKey?: string;
  latitude: number;
  longitude: number;
  timezone: string;
  locationLabel: string;
  size: ClockSnapshotSize;
}

export interface ClockArcSnapshot {
  kind: ClockArcKind;
  label: string;
  detail: string;
  color: string;
  radius: number;
  strokeWidth: number;
  ranges: SkyInterval[];
}

export interface ClockEventSnapshot {
  kind: SkyEventKind;
  body: SkyEvent['body'];
  marker: ClockMarkerKind;
  label: string;
  time: string;
  timeLabel: string;
  minute: number;
  radius: number;
  visibleOnDial: boolean;
}

export interface ClockSnapshot {
  schemaVersion: typeof CLOCK_SNAPSHOT_VERSION;
  calculatedAt: string;
  expiresAt: string;
  dateKey: string;
  timezone: string;
  location: {
    label: string;
    latitude: number;
    longitude: number;
  };
  size: ClockSnapshotSize;
  geometry: {
    viewBox: number;
    center: number;
    outerRadius: number;
    sunRadius: number;
    moonRadius: number;
    hourLabelRadius: number;
    handStartRadius: number;
    handEndRadius: number;
  };
  palette: {
    background: string;
    face: string;
    track: string;
    text: string;
    mutedText: string;
    currentHand: string;
  };
  hourLabels: Array<{
    hour: number;
    label: string;
    minute: number;
  }>;
  arcs: ClockArcSnapshot[];
  events: ClockEventSnapshot[];
  referenceMinute: number;
  currentTimeLabel: string;
  nextSolarEvent: {
    kind: 'sunrise' | 'sunset';
    time: string;
    timeLabel: string;
    relativeLabel: string;
  } | null;
  moon: {
    illumination: number;
    phaseAngle: number;
    phaseName: string;
    markerMinute: number;
  };
  accessibilityText: string;
}

const DIAL_GEOMETRY: ClockSnapshot['geometry'] = {
  viewBox: 420,
  center: 210,
  outerRadius: 190,
  sunRadius: 138,
  moonRadius: 112,
  hourLabelRadius: 170,
  handStartRadius: 64,
  handEndRadius: 181
};

const DIAL_PALETTE: ClockSnapshot['palette'] = {
  background: '#0c1424',
  face: '#111b2e',
  track: '#222a39',
  text: '#f2f7fc',
  mutedText: '#b8cbe0',
  currentHand: '#f2f7fc'
};

const ARC_DEFINITIONS: Array<
  Omit<ClockArcSnapshot, 'ranges'> & {
    ranges: (day: DaySky) => SkyInterval[];
  }
> = [
  {
    kind: 'astronomical',
    label: 'Astronomical twilight',
    detail: 'Sun 12–18° below the horizon',
    color: '#2d405d',
    radius: DIAL_GEOMETRY.sunRadius,
    strokeWidth: 15,
    ranges: (day) => day.astronomicalLight
  },
  {
    kind: 'nautical',
    label: 'Nautical twilight',
    detail: 'Sun 6–12° below the horizon',
    color: '#435e7a',
    radius: DIAL_GEOMETRY.sunRadius,
    strokeWidth: 15,
    ranges: (day) => day.nauticalLight
  },
  {
    kind: 'civil',
    label: 'Civil twilight',
    detail: 'Sun 0–6° below the horizon',
    color: '#718ba3',
    radius: DIAL_GEOMETRY.sunRadius,
    strokeWidth: 15,
    ranges: (day) => day.civilLight
  },
  {
    kind: 'daylight',
    label: 'Daylight',
    detail: 'Sun above the horizon',
    color: '#ffb552',
    radius: DIAL_GEOMETRY.sunRadius,
    strokeWidth: 15,
    ranges: (day) => day.daylight
  },
  {
    kind: 'moon',
    label: 'Moon above horizon',
    detail: 'Moon above the geometric horizon',
    color: '#d9e5ea',
    radius: DIAL_GEOMETRY.moonRadius,
    strokeWidth: 10,
    ranges: (day) => day.moonVisible
  }
];

function formatMinute(minute: number): string {
  const normalized = ((Math.round(minute) % 1440) + 1440) % 1440;
  const hour = Math.floor(normalized / 60);
  const minutePart = normalized % 60;
  return `${String(hour).padStart(2, '0')}:${String(minutePart).padStart(2, '0')}`;
}

function markerKind(event: SkyEvent): ClockMarkerKind {
  if (event.kind.includes('rise') || event.kind.includes('dawn')) return 'rising';
  if (event.kind.includes('set') || event.kind.includes('dusk')) return 'setting';
  return 'peak';
}

function isVisibleEventMarker(event: SkyEvent): boolean {
  return (
    event.body !== 'twilight' &&
    event.kind !== 'sunrise' &&
    event.kind !== 'sunset'
  );
}

function eventRadius(event: SkyEvent): number {
  return event.body === 'moon'
    ? DIAL_GEOMETRY.moonRadius
    : DIAL_GEOMETRY.sunRadius;
}

function relativeEventLabel(day: DaySky): string | null {
  if (!day.nextSolarEvent) return null;

  const totalMinutes = Math.max(
    1,
    Math.ceil(
      (day.nextSolarEvent.time.getTime() - day.referenceTime.getTime()) / 60_000
    )
  );
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  const duration =
    days > 0
      ? `${days}d ${hours}h`
      : hours > 0
        ? `${hours}h ${minutes}m`
        : `${minutes}m`;
  const label =
    day.nextSolarEvent.kind === 'sunrise' ? 'Sunrise' : 'Sunset';
  return `${label} in ${duration}`;
}

function snapshotExpiration(
  dateKey: string,
  timezone: string
): Date {
  const { end } = civilDayRange(dateKey, timezone);
  return end;
}

function intervalDuration(intervals: SkyInterval[]): number {
  return intervals.reduce(
    (total, interval) => total + interval.endMinute - interval.startMinute,
    0
  );
}

function accessibilityText(
  day: DaySky,
  locationLabel: string,
  timezone: string
): string {
  const daylightHours = intervalDuration(day.daylight) / 60;
  const next = relativeEventLabel(day);
  return [
    `DayMan clock for ${locationLabel} on ${day.dateKey} in ${timezone}.`,
    `${daylightHours.toFixed(1)} hours of daylight.`,
    `${day.moonPhaseName}, ${Math.round(day.moonIllumination * 100)} percent illuminated.`,
    next ? `${next}.` : 'No upcoming sunrise or sunset was found.'
  ].join(' ');
}

export function buildClockSnapshot(
  day: DaySky,
  location: Pick<
    SavedLocation,
    'label' | 'latitude' | 'longitude' | 'timezone'
  >,
  size: ClockSnapshotSize,
  calculatedAt = day.referenceTime
): ClockSnapshot {
  const referenceMinute = localMinute(day.referenceTime, location.timezone);
  const nextRelativeLabel = relativeEventLabel(day);

  return {
    schemaVersion: CLOCK_SNAPSHOT_VERSION,
    calculatedAt: calculatedAt.toISOString(),
    expiresAt: snapshotExpiration(
      day.dateKey,
      location.timezone
    ).toISOString(),
    dateKey: day.dateKey,
    timezone: location.timezone,
    location: {
      label: location.label,
      latitude: location.latitude,
      longitude: location.longitude
    },
    size: {
      width: size.width,
      height: size.height,
      ...(size.density === undefined ? {} : { density: size.density })
    },
    geometry: { ...DIAL_GEOMETRY },
    palette: { ...DIAL_PALETTE },
    hourLabels: Array.from({ length: 8 }, (_, index) => {
      const hour = index * 3;
      return {
        hour,
        label: String(hour).padStart(2, '0'),
        minute: hour * 60
      };
    }),
    arcs: ARC_DEFINITIONS.map(({ ranges, ...definition }) => ({
      ...definition,
      ranges: ranges(day).map((range) => ({ ...range }))
    })),
    events: day.events.map((event) => ({
      kind: event.kind,
      body: event.body,
      marker: markerKind(event),
      label: event.label,
      time: event.time.toISOString(),
      timeLabel: formatMinute(event.minute),
      minute: event.minute,
      radius: eventRadius(event),
      visibleOnDial: isVisibleEventMarker(event)
    })),
    referenceMinute,
    currentTimeLabel: formatMinute(referenceMinute),
    nextSolarEvent:
      day.nextSolarEvent && nextRelativeLabel
        ? {
            kind: day.nextSolarEvent.kind,
            time: day.nextSolarEvent.time.toISOString(),
            timeLabel: formatMinute(
              localMinute(day.nextSolarEvent.time, location.timezone)
            ),
            relativeLabel: nextRelativeLabel
          }
        : null,
    moon: {
      illumination: day.moonIllumination,
      phaseAngle: day.moonPhaseAngle,
      phaseName: day.moonPhaseName,
      markerMinute: referenceMinute
    },
    accessibilityText: accessibilityText(
      day,
      location.label,
      location.timezone
    )
  };
}

export function createClockSnapshot(input: ClockSnapshotInput): ClockSnapshot {
  const location: SavedLocation = {
    label: input.locationLabel,
    latitude: input.latitude,
    longitude: input.longitude,
    timezone: input.timezone,
    source: 'coordinates'
  };
  const dateKey = input.dateKey ?? dateKeyInZone(input.at, input.timezone);
  const day = calculateDaySky(dateKey, location, input.at);
  return buildClockSnapshot(day, location, input.size, input.at);
}

export function createClockSnapshotQueue(
  input: Omit<ClockSnapshotInput, 'dateKey'>,
  days = CLOCK_SNAPSHOT_QUEUE_DAYS
): ClockSnapshot[] {
  if (!Number.isInteger(days) || days < 1) {
    throw new Error('ClockSnapshot queue length must be a positive integer');
  }

  const firstDateKey = dateKeyInZone(input.at, input.timezone);
  return Array.from({ length: days }, (_, dayOffset) =>
    createClockSnapshot({
      ...input,
      dateKey: shiftDateKey(firstDateKey, dayOffset)
    })
  );
}

export function serializeClockSnapshot(snapshot: ClockSnapshot): string {
  return JSON.stringify(snapshot);
}

export function parseClockSnapshot(value: string): ClockSnapshot {
  const parsed: unknown = JSON.parse(value);
  if (
    typeof parsed !== 'object' ||
    parsed === null ||
    !('schemaVersion' in parsed) ||
    parsed.schemaVersion !== CLOCK_SNAPSHOT_VERSION ||
    !('calculatedAt' in parsed) ||
    typeof parsed.calculatedAt !== 'string' ||
    !('expiresAt' in parsed) ||
    typeof parsed.expiresAt !== 'string' ||
    !('arcs' in parsed) ||
    !Array.isArray(parsed.arcs) ||
    !('events' in parsed) ||
    !Array.isArray(parsed.events)
  ) {
    throw new Error('Unsupported or invalid ClockSnapshot');
  }
  return parsed as ClockSnapshot;
}
