<script lang="ts">
  import { onMount } from 'svelte';
  import { on } from 'svelte/events';

  interface BeforeInstallPromptEvent extends Event {
    prompt(): Promise<void>;
    userChoice: Promise<{
      outcome: 'accepted' | 'dismissed';
      platform: string;
    }>;
  }

  interface DownloadOption {
    id: ReleaseAssetKind;
    label: string;
    detail: string;
    href: string;
    resolveFromRelease: boolean;
  }

  interface GitHubReleaseAsset {
    name: string;
    browser_download_url: string;
  }

  interface GitHubRelease {
    assets: GitHubReleaseAsset[];
  }

  type Platform = 'android' | 'macos' | 'linux' | 'other';
  type ReleaseAssetKind = 'android' | 'macos' | 'appimage' | 'deb' | 'rpm' | 'arch';
  const latestReleaseUrl = 'https://github.com/glengerbush/DayMan/releases/latest';
  const latestReleaseApiUrl =
    'https://api.github.com/repos/glengerbush/DayMan/releases/latest';

  const platform = detectPlatform();
  const platformName =
    platform === 'android'
      ? 'Android'
      : platform === 'macos'
        ? 'macOS'
        : platform === 'linux'
          ? 'Linux'
          : null;
  let installed = $state(isInstalled());
  let open = $state(false);
  let showPwaHelp = $state(false);
  let installPrompt = $state<BeforeInstallPromptEvent | null>(null);
  let downloads = $state.raw(downloadOptions(platform));
  let releaseLookupStarted = false;

  onMount(() => {
    const displayMode = window.matchMedia('(display-mode: standalone)');

    function updateInstalled(): void {
      installed = isInstalled();
      if (installed) open = false;
    }

    function captureInstallPrompt(event: Event): void {
      event.preventDefault();
      installPrompt = event as BeforeInstallPromptEvent;
    }

    function handleInstalled(): void {
      installed = true;
      installPrompt = null;
      open = false;
    }

    updateInstalled();

    const cleanups = [
      on(displayMode, 'change', updateInstalled),
      on(window, 'beforeinstallprompt', captureInstallPrompt),
      on(window, 'appinstalled', handleInstalled)
    ];

    return () => cleanups.forEach((cleanup) => cleanup());
  });

  function detectPlatform(): Platform {
    if (typeof navigator === 'undefined') return 'other';

    const identity = `${navigator.userAgent} ${navigator.platform}`;
    if (/android/i.test(identity)) return 'android';
    if (/macintosh|macintel|macppc|mac68k/i.test(identity)) return 'macos';
    if (/linux/i.test(identity)) return 'linux';
    return 'other';
  }

  function isInstalled(): boolean {
    if (typeof window === 'undefined' || typeof navigator === 'undefined') return false;

    const iosStandalone = (navigator as Navigator & { standalone?: boolean }).standalone === true;
    const nativeHost =
      window.DayManAndroid !== undefined ||
      window.DayManNative !== undefined ||
      window.__TAURI_INTERNALS__ !== undefined ||
      window.webkit?.messageHandlers?.daymanState !== undefined;
    return (
      window.matchMedia('(display-mode: standalone)').matches ||
      iosStandalone ||
      nativeHost
    );
  }

  function configuredUrl(value: string | undefined): string | null {
    const url = value?.trim();
    return url || null;
  }

  function downloadOptions(visitorPlatform: Platform): DownloadOption[] {
    const option = (
      id: ReleaseAssetKind,
      label: string,
      detail: string,
      value: string | undefined
    ): DownloadOption => {
      const configured = configuredUrl(value);
      return {
        id,
        label,
        detail,
        href: configured ?? latestReleaseUrl,
        resolveFromRelease: configured === null
      };
    };

    const options =
      visitorPlatform === 'android'
        ? [
            option(
              'android',
              'Download Android app',
              'APK in the latest GitHub release',
              import.meta.env.VITE_ANDROID_APK_URL
            )
          ]
        : visitorPlatform === 'macos'
          ? [
              option(
                'macos',
                'Download macOS app',
                'DMG in the latest GitHub release',
                import.meta.env.VITE_MACOS_DOWNLOAD_URL
              )
            ]
          : visitorPlatform === 'linux'
            ? [
                option(
                  'appimage',
                  'Download AppImage',
                  'Portable app in the latest release',
                  import.meta.env.VITE_LINUX_APPIMAGE_URL
                ),
                option(
                  'deb',
                  'Download for Debian',
                  'DEB in the latest GitHub release',
                  import.meta.env.VITE_LINUX_DEB_URL
                ),
                option(
                  'rpm',
                  'Download for Fedora',
                  'RPM in the latest GitHub release',
                  import.meta.env.VITE_LINUX_RPM_URL
                ),
                option(
                  'arch',
                  'Download for Arch',
                  'Arch package in the latest release',
                  import.meta.env.VITE_LINUX_ARCH_URL
                )
              ]
            : [];

    return options;
  }

  function matchesAsset(kind: ReleaseAssetKind, name: string): boolean {
    switch (kind) {
      case 'android':
        return /\.apk$/i.test(name);
      case 'macos':
        return /\.dmg$/i.test(name);
      case 'appimage':
        return /\.AppImage$/i.test(name);
      case 'deb':
        return /\.deb$/i.test(name);
      case 'rpm':
        return /\.rpm$/i.test(name);
      case 'arch':
        return /\.pkg\.tar\.zst$/i.test(name) && !/-debug-/i.test(name);
    }
  }

  async function resolveLatestReleaseDownloads(): Promise<void> {
    if (releaseLookupStarted || !downloads.some((download) => download.resolveFromRelease)) {
      return;
    }
    releaseLookupStarted = true;

    try {
      const response = await fetch(latestReleaseApiUrl, {
        headers: { Accept: 'application/vnd.github+json' }
      });
      if (!response.ok) throw new Error(`GitHub release lookup returned ${response.status}`);

      const release = (await response.json()) as GitHubRelease;
      if (!Array.isArray(release.assets)) throw new Error('GitHub release assets are missing');

      downloads = downloads.map((download) => {
        if (!download.resolveFromRelease) return download;
        const asset = release.assets.find((candidate) =>
          matchesAsset(download.id, candidate.name)
        );
        return asset
          ? {
              ...download,
              detail: asset.name,
              href: asset.browser_download_url,
              resolveFromRelease: false
            }
          : download;
      });
    } catch (error) {
      console.warn('Unable to resolve the latest DayMan release downloads.', error);
    }
  }

  function toggleMenu(event: MouseEvent): void {
    event.stopPropagation();
    open = !open;
    if (open) void resolveLatestReleaseDownloads();
    if (!open) showPwaHelp = false;
  }

  function closeMenu(): void {
    open = false;
    showPwaHelp = false;
  }

  function handleWindowClick(event: MouseEvent): void {
    const target = event.target;
    if (open && (!(target instanceof Element) || !target.closest('[data-install-menu]'))) {
      closeMenu();
    }
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape' && open) closeMenu();
  }

  async function installPwa(event: MouseEvent): Promise<void> {
    event.stopPropagation();

    if (!installPrompt) {
      showPwaHelp = true;
      return;
    }

    await installPrompt.prompt();
    const choice = await installPrompt.userChoice;
    installPrompt = null;

    if (choice.outcome === 'accepted') {
      installed = true;
      open = false;
    }
  }
</script>

<svelte:window onclick={handleWindowClick} onkeydown={handleKeydown} />

{#if !installed}
  <div class="install-menu" data-install-menu>
    <button
      class="install-trigger"
      type="button"
      aria-label="Install DayMan"
      aria-haspopup="menu"
      aria-expanded={open}
      aria-controls="install-options"
      onclick={toggleMenu}
    >
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M12 3v11m0 0 4-4m-4 4-4-4M5 16v4h14v-4" />
      </svg>
      <span>Install</span>
      <svg class="install-chevron" viewBox="0 0 24 24" aria-hidden="true">
        <path d="m8 10 4 4 4-4" />
      </svg>
    </button>

    {#if open}
      <div class="install-popover" id="install-options" role="menu">
        <div class="install-heading">
          <strong>Install DayMan</strong>
          <small>Choose the version for this device.</small>
        </div>

        <button class="install-option" type="button" role="menuitem" onclick={installPwa}>
          <span class="option-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24">
              <rect x="4" y="4" width="16" height="16" rx="3" />
              <path d="M12 7v7m0 0 3-3m-3 3-3-3M8 17h8" />
            </svg>
          </span>
          <span>
            <strong>Install the PWA</strong>
            <small>{installPrompt ? 'Open the browser install prompt' : 'Add it from your browser'}</small>
          </span>
        </button>

        {#if showPwaHelp}
          <p class="install-help">
            Use your browser menu and choose <strong>Install app</strong> or
            <strong>Add to Home Screen</strong>.
          </p>
        {/if}

        {#if downloads.length > 0}
          <div class="option-separator"><span>or</span></div>
          {#each downloads as download (download.id)}
            <a
              class="install-option"
              role="menuitem"
              href={download.href}
              target="_blank"
              rel="noreferrer"
            >
              <span class="option-icon native" aria-hidden="true">
                <svg viewBox="0 0 24 24">
                  <path d="M12 3v11m0 0 4-4m-4 4-4-4M5 16v4h14v-4" />
                </svg>
              </span>
              <span>
                <strong>{download.label}</strong>
                <small>{download.detail}</small>
              </span>
            </a>
          {/each}
        {:else if platformName}
          <p class="native-pending">
            The direct {platformName} download will appear here when the first build is released.
          </p>
        {/if}
      </div>
    {/if}
  </div>
{/if}

<style>
  .install-menu {
    position: relative;
  }

  .install-trigger {
    display: flex;
    align-items: center;
    gap: 0.38rem;
    min-height: 2.2rem;
    padding: 0.42rem 0.55rem;
    border: 1px solid rgb(255 255 255 / 0.1);
    border-radius: 0.72rem;
    color: var(--text-soft);
    background: rgb(255 255 255 / 0.035);
    font-size: 0.7rem;
    font-weight: 700;
    transition:
      border-color 160ms ease,
      color 160ms ease,
      background 160ms ease;
  }

  .install-trigger:hover,
  .install-trigger[aria-expanded='true'] {
    border-color: rgb(255 189 99 / 0.35);
    color: var(--accent);
    background: rgb(255 189 99 / 0.07);
  }

  .install-trigger svg {
    width: 0.95rem;
    fill: none;
    stroke: currentColor;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-width: 1.7;
  }

  .install-trigger .install-chevron {
    width: 0.72rem;
    color: var(--text-muted);
  }

  .install-popover {
    position: absolute;
    z-index: 20;
    top: calc(100% + 0.55rem);
    left: 0;
    width: min(20rem, calc(100vw - 1rem));
    overflow: hidden;
    border: 1px solid var(--line-strong);
    border-radius: 1rem;
    background: #111c2e;
    box-shadow: 0 1.25rem 4rem rgb(0 0 0 / 0.42);
  }

  .install-heading {
    display: grid;
    gap: 0.16rem;
    padding: 0.9rem 1rem 0.72rem;
    border-bottom: 1px solid var(--line);
  }

  .install-heading strong {
    font-family: var(--font-display);
    font-size: 1rem;
    font-weight: 600;
  }

  .install-heading small,
  .install-option small {
    color: var(--text-muted);
    font-size: 0.64rem;
  }

  .install-option {
    display: grid;
    width: 100%;
    grid-template-columns: 2rem 1fr;
    align-items: center;
    gap: 0.65rem;
    padding: 0.72rem 1rem;
    border: 0;
    color: var(--text);
    background: transparent;
    text-align: left;
  }

  .install-option:hover,
  .install-option:focus-visible {
    background: rgb(255 255 255 / 0.045);
  }

  .install-option > span:last-child {
    display: grid;
    gap: 0.12rem;
  }

  .install-option strong {
    font-size: 0.73rem;
  }

  .option-icon {
    display: grid;
    width: 2rem;
    height: 2rem;
    place-items: center;
    border-radius: 0.65rem;
    color: var(--accent);
    background: rgb(255 189 99 / 0.09);
  }

  .option-icon.native {
    color: #b8cbde;
    background: rgb(89 122 157 / 0.15);
  }

  .option-icon svg {
    width: 1.1rem;
    fill: none;
    stroke: currentColor;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-width: 1.55;
  }

  .install-help,
  .native-pending {
    margin: 0;
    padding: 0.68rem 1rem 0.8rem 3.65rem;
    color: var(--text-muted);
    background: rgb(255 255 255 / 0.018);
    font-size: 0.64rem;
    line-height: 1.45;
  }

  .install-help strong {
    color: var(--text-soft);
  }

  .native-pending {
    padding: 0.78rem 1rem;
    border-top: 1px solid var(--line);
  }

  .option-separator {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    padding: 0 1rem;
    color: var(--text-muted);
    font-size: 0.57rem;
    text-transform: uppercase;
  }

  .option-separator::before,
  .option-separator::after {
    height: 1px;
    flex: 1;
    background: var(--line);
    content: '';
  }

  @media (max-width: 620px) {
    .install-trigger {
      width: 2.2rem;
      justify-content: center;
      padding-inline: 0;
    }

    .install-trigger span,
    .install-trigger .install-chevron {
      display: none;
    }
  }
</style>
