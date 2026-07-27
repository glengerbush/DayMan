import { hasPlatformBridge } from './platform-bridge';

export function isInstalledExperience(): boolean {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') return false;

  const iosStandalone = (navigator as Navigator & { standalone?: boolean }).standalone === true;
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    iosStandalone ||
    hasPlatformBridge()
  );
}
