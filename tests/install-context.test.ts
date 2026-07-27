import { afterEach, describe, expect, it, vi } from 'vitest';
import { isInstalledExperience } from '../src/lib/install-context';

interface InstalledContextOptions {
  displayMode?: boolean;
  iosStandalone?: boolean;
  nativeBridge?: boolean;
}

function installBrowserContext({
  displayMode = false,
  iosStandalone = false,
  nativeBridge = false
}: InstalledContextOptions = {}): void {
  vi.stubGlobal('navigator', { standalone: iosStandalone });
  vi.stubGlobal('window', {
    matchMedia: () => ({ matches: displayMode }),
    DayManNative: nativeBridge ? { saveState: () => undefined } : undefined
  });
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('isInstalledExperience', () => {
  it('keeps the brand link enabled on the plain website', () => {
    installBrowserContext();
    expect(isInstalledExperience()).toBe(false);
  });

  it('detects an installed PWA', () => {
    installBrowserContext({ displayMode: true });
    expect(isInstalledExperience()).toBe(true);
  });

  it('detects the iOS standalone mode', () => {
    installBrowserContext({ iosStandalone: true });
    expect(isInstalledExperience()).toBe(true);
  });

  it('detects a native host bridge', () => {
    installBrowserContext({ nativeBridge: true });
    expect(isInstalledExperience()).toBe(true);
  });
});
