import { afterEach, describe, expect, test, vi } from 'vitest';

import { createClockSnapshot } from '../src/lib/clock-snapshot';
import {
  hasPlatformBridge,
  persistPlatformState,
  PLATFORM_STATE_VERSION
} from '../src/lib/platform-bridge';
import type { SavedLocation } from '../src/lib/types';

const location: SavedLocation = {
  label: 'New York',
  latitude: 40.7128,
  longitude: -74.006,
  timezone: 'America/New_York',
  source: 'coordinates'
};
const snapshot = createClockSnapshot({
  at: new Date('2026-06-21T16:00:00.000Z'),
  latitude: location.latitude,
  longitude: location.longitude,
  timezone: location.timezone,
  locationLabel: location.label,
  size: { width: 420, height: 420, density: 1 }
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('native platform bridge', () => {
  test('is a no-op in the web PWA', async () => {
    vi.stubGlobal('window', {});

    expect(hasPlatformBridge()).toBe(false);
    await expect(persistPlatformState(location, snapshot)).resolves.toBe('web');
  });

  test('sends a versioned JSON envelope to Android', async () => {
    const saveState = vi.fn();
    vi.stubGlobal('window', { DayManAndroid: { saveState } });

    expect(hasPlatformBridge()).toBe(true);
    await expect(persistPlatformState(location, snapshot)).resolves.toBe(
      'android'
    );
    expect(saveState).toHaveBeenCalledOnce();
    const envelope = JSON.parse(saveState.mock.calls[0][0] as string);
    expect(envelope.schemaVersion).toBe(PLATFORM_STATE_VERSION);
    expect(envelope.settings.location).toEqual(location);
    expect(envelope.snapshot).toEqual(snapshot);
    expect(envelope.snapshots).toEqual([snapshot]);
  });

  test('posts the envelope to the Apple message handler', async () => {
    const postMessage = vi.fn();
    vi.stubGlobal('window', {
      webkit: { messageHandlers: { daymanState: { postMessage } } }
    });

    await expect(persistPlatformState(location, snapshot)).resolves.toBe(
      'apple'
    );
    expect(postMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        schemaVersion: PLATFORM_STATE_VERSION,
        snapshot,
        snapshots: [snapshot]
      })
    );
  });

  test('invokes the Tauri state command', async () => {
    const invoke = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal('window', { __TAURI_INTERNALS__: { invoke } });

    await expect(persistPlatformState(location, snapshot)).resolves.toBe(
      'tauri'
    );
    expect(invoke).toHaveBeenCalledWith(
      'save_dayman_state',
      expect.objectContaining({
        state: expect.objectContaining({ snapshot })
      })
    );
  });
});
