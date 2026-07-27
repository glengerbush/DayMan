export type LocationSource = 'default' | 'gps' | 'postal' | 'map' | 'coordinates';
export type LocationMethod = 'map' | 'postal' | 'coordinates';

export interface SavedLocation {
  label: string;
  latitude: number;
  longitude: number;
  timezone: string;
  source: LocationSource;
  postalCode?: string;
}

export interface SkyInterval {
  startMinute: number;
  endMinute: number;
}

export type SkyEventKind =
  | 'astronomical-dawn'
  | 'nautical-dawn'
  | 'civil-dawn'
  | 'sunrise'
  | 'solar-noon'
  | 'sunset'
  | 'civil-dusk'
  | 'nautical-dusk'
  | 'astronomical-dusk'
  | 'moonrise'
  | 'lunar-noon'
  | 'moonset';

export interface SkyEvent {
  kind: SkyEventKind;
  label: string;
  time: Date;
  minute: number;
  body: 'sun' | 'moon' | 'twilight';
}

export interface BodyPosition {
  altitude: number;
  azimuth: number;
}

export interface NextSolarEvent {
  kind: 'sunrise' | 'sunset';
  time: Date;
}

export interface DaySky {
  dateKey: string;
  events: SkyEvent[];
  daylight: SkyInterval[];
  civilLight: SkyInterval[];
  nauticalLight: SkyInterval[];
  astronomicalLight: SkyInterval[];
  moonVisible: SkyInterval[];
  sunPosition: BodyPosition;
  moonPosition: BodyPosition;
  moonIllumination: number;
  moonPhaseAngle: number;
  moonPhaseName: string;
  nextSolarEvent: NextSolarEvent | null;
  referenceTime: Date;
  isToday: boolean;
}
