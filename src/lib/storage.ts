import type { SavedLocation } from './types';

const LOCATION_KEY = 'dayman.location.v1';
const LEGACY_LOCATION_KEY = 'dayarc.location.v1';

export const DEFAULT_LOCATION: SavedLocation = {
  label: 'New York',
  latitude: 40.7128,
  longitude: -74.006,
  timezone: 'America/New_York',
  source: 'default'
};

export function loadLocation(): SavedLocation {
  try {
    const raw =
      localStorage.getItem(LOCATION_KEY) ??
      localStorage.getItem(LEGACY_LOCATION_KEY);
    return raw ? ({ ...DEFAULT_LOCATION, ...JSON.parse(raw) } as SavedLocation) : DEFAULT_LOCATION;
  } catch {
    return DEFAULT_LOCATION;
  }
}

export function saveLocation(location: SavedLocation): void {
  localStorage.setItem(LOCATION_KEY, JSON.stringify(location));
}
