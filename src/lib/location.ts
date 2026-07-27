import tzLookup from 'tz-lookup';

import type { SavedLocation } from './types';

type ZctaLookup = Record<string, [number, number]>;

let zctaPromise: Promise<ZctaLookup> | undefined;

async function loadZctas(): Promise<ZctaLookup> {
  zctaPromise ??= fetch(
    `${import.meta.env.BASE_URL}data/zcta-2025.json`
  )
    .then(async (response) => {
      if (!response.ok) {
        throw new Error('ZIP code data is unavailable');
      }
      return (await response.json()) as ZctaLookup;
    })
    .catch((error: unknown) => {
      zctaPromise = undefined;
      throw error;
    });
  return zctaPromise;
}

export function detectTimezone(latitude: number, longitude: number): string {
  return tzLookup(latitude, longitude);
}

export async function lookupZipCode(zipInput: string): Promise<SavedLocation | null> {
  const postalCode = zipInput.replace(/\D/g, '').slice(0, 5);
  if (postalCode.length !== 5) return null;

  const coordinates = (await loadZctas())[postalCode];
  if (!coordinates) return null;

  const [latitude, longitude] = coordinates;
  return {
    label: `ZIP ${postalCode}`,
    latitude,
    longitude,
    timezone: detectTimezone(latitude, longitude),
    source: 'postal',
    postalCode
  };
}

export function availableTimezones(): string[] {
  if ('supportedValuesOf' in Intl) {
    return Intl.supportedValuesOf('timeZone');
  }

  return [
    'America/Anchorage',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/New_York',
    'America/Phoenix',
    'Pacific/Honolulu',
    'UTC'
  ];
}

export function coordinatesLabel(latitude: number, longitude: number): string {
  const lat = `${Math.abs(latitude).toFixed(3)}° ${latitude >= 0 ? 'N' : 'S'}`;
  const lon = `${Math.abs(longitude).toFixed(3)}° ${longitude >= 0 ? 'E' : 'W'}`;
  return `${lat}, ${lon}`;
}
