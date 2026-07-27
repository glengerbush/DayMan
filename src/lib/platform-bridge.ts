import type { ClockSnapshot } from './clock-snapshot';
import type { SavedLocation } from './types';

export const PLATFORM_STATE_VERSION = 1 as const;

export interface PlatformStateEnvelope {
  schemaVersion: typeof PLATFORM_STATE_VERSION;
  updatedAt: string;
  settings: {
    location: SavedLocation;
  };
  snapshot: ClockSnapshot;
  snapshots: ClockSnapshot[];
}

type BridgeTarget = 'android' | 'apple' | 'tauri' | 'custom' | 'web';

interface AndroidBridge {
  saveState(payload: string): void;
}

interface AppleMessageHandler {
  postMessage(payload: PlatformStateEnvelope): void;
}

interface CustomBridge {
  saveState(payload: string): void | Promise<void>;
}

interface TauriInternals {
  invoke(
    command: string,
    payload: Record<string, unknown>
  ): Promise<unknown>;
}

declare global {
  interface Window {
    DayManAndroid?: AndroidBridge;
    DayManNative?: CustomBridge;
    __TAURI_INTERNALS__?: TauriInternals;
    webkit?: {
      messageHandlers?: {
        daymanState?: AppleMessageHandler;
      };
    };
  }
}

export function hasPlatformBridge(): boolean {
  return Boolean(
    window.DayManAndroid ||
      window.webkit?.messageHandlers?.daymanState ||
      window.__TAURI_INTERNALS__ ||
      window.DayManNative
  );
}

export async function persistPlatformState(
  location: SavedLocation,
  snapshot: ClockSnapshot,
  snapshots: ClockSnapshot[] = [snapshot]
): Promise<BridgeTarget> {
  const state: PlatformStateEnvelope = {
    schemaVersion: PLATFORM_STATE_VERSION,
    updatedAt: new Date().toISOString(),
    settings: {
      location: { ...location }
    },
    snapshot,
    snapshots
  };

  if (window.DayManAndroid) {
    window.DayManAndroid.saveState(JSON.stringify(state));
    return 'android';
  }

  if (window.webkit?.messageHandlers?.daymanState) {
    window.webkit.messageHandlers.daymanState.postMessage(state);
    return 'apple';
  }

  if (window.__TAURI_INTERNALS__) {
    await window.__TAURI_INTERNALS__.invoke('save_dayman_state', { state });
    return 'tauri';
  }

  if (window.DayManNative) {
    await window.DayManNative.saveState(JSON.stringify(state));
    return 'custom';
  }

  return 'web';
}
