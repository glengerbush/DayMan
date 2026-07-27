<script lang="ts">
  import { onMount, type Component } from 'svelte';
  import { on } from 'svelte/events';
  import EventList from './lib/components/EventList.svelte';
  import InstallMenu from './lib/components/InstallMenu.svelte';
  import SkyDial from './lib/components/SkyDial.svelte';
  import { calculateDaySky } from './lib/astronomy';
  import {
    buildClockSnapshot,
    createClockSnapshotQueue
  } from './lib/clock-snapshot';
  import { coordinatesLabel } from './lib/location';
  import { isInstalledExperience } from './lib/install-context';
  import {
    hasPlatformBridge,
    persistPlatformState
  } from './lib/platform-bridge';
  import { loadLocation, saveLocation } from './lib/storage';
  import {
    dateKeyInZone,
    formatClockTime,
    formatLongDate,
    shiftDateKey
  } from './lib/time';
  import type { LocationMethod, SavedLocation, SkyEventKind } from './lib/types';

  const initialLocation = loadLocation();
  const initialNow = new Date();
  let location = $state<SavedLocation>(initialLocation);
  let now = $state(initialNow);
  let dateKey = $state(dateKeyInZone(initialNow, initialLocation.timezone));
  let locationOpen = $state(false);
  let locationMethod = $state<LocationMethod>('map');
  let LocationSheetComponent = $state<Component<{
    location: SavedLocation;
    initialMethod: LocationMethod;
    onclose: () => void;
    onapply: (location: SavedLocation) => void;
    onmethodchange: (method: LocationMethod) => void;
  }> | null>(null);
  let online = $state(navigator.onLine);
  let installedExperience = $state(isInstalledExperience());

  let sky = $derived(calculateDaySky(dateKey, location, now));
  let nativeDateKey = $derived(dateKeyInZone(now, location.timezone));
  let clockSnapshot = $derived(
    buildClockSnapshot(sky, location, { width: 420, height: 420, density: 1 })
  );
  let longDate = $derived(formatLongDate(dateKey, location.timezone));
  let coordinateText = $derived(coordinatesLabel(location.latitude, location.longitude));
  let solarEvents = $derived(
    pickEvents(['sunrise', 'solar-noon', 'sunset'])
  );
  let lunarEvents = $derived(
    pickEvents(['moonrise', 'lunar-noon', 'moonset'])
  );
  let twilightBands = $derived([
    {
      label: 'Civil',
      tone: 'civil',
      dawn: sky.events.find((event) => event.kind === 'civil-dawn'),
      dusk: sky.events.find((event) => event.kind === 'civil-dusk')
    },
    {
      label: 'Nautical',
      tone: 'nautical',
      dawn: sky.events.find((event) => event.kind === 'nautical-dawn'),
      dusk: sky.events.find((event) => event.kind === 'nautical-dusk')
    },
    {
      label: 'Astronomical',
      tone: 'astronomical',
      dawn: sky.events.find((event) => event.kind === 'astronomical-dawn'),
      dusk: sky.events.find((event) => event.kind === 'astronomical-dusk')
    }
  ]);

  $effect(() => {
    const interval = window.setInterval(() => {
      now = new Date();
    }, 30_000);
    return () => window.clearInterval(interval);
  });

  onMount(() => {
    const displayMode = window.matchMedia('(display-mode: standalone)');
    const updateInstalledExperience = (): void => {
      installedExperience = isInstalledExperience();
    };
    updateInstalledExperience();

    const cleanups = [
      on(displayMode, 'change', updateInstalledExperience),
      on(window, 'appinstalled', updateInstalledExperience)
    ];
    return () => cleanups.forEach((cleanup) => cleanup());
  });

  $effect(() => {
    saveLocation(location);
  });

  $effect(() => {
    if (!hasPlatformBridge()) return;

    // Re-run at the saved timezone's next midnight, but not on every
    // 30-second clock tick.
    const queueStartDate = nativeDateKey;
    const bridgeLocation = { ...location };
    const bridgeSnapshots = createClockSnapshotQueue({
      at: new Date(),
      latitude: bridgeLocation.latitude,
      longitude: bridgeLocation.longitude,
      timezone: bridgeLocation.timezone,
      locationLabel: bridgeLocation.label,
      size: { width: 420, height: 420, density: 1 }
    });
    if (bridgeSnapshots[0]?.dateKey !== queueStartDate) return;
    void persistPlatformState(
      bridgeLocation,
      bridgeSnapshots[0],
      bridgeSnapshots
    ).catch((error: unknown) => {
      console.warn('Unable to save DayMan state to the native host.', error);
    });
  });

  function pickEvents(kinds: SkyEventKind[]) {
    return kinds
      .map((kind) => sky.events.find((event) => event.kind === kind))
      .filter((event) => event !== undefined);
  }

  function previousDay(): void {
    dateKey = shiftDateKey(dateKey, -1);
  }

  function nextDay(): void {
    dateKey = shiftDateKey(dateKey, 1);
  }

  function goToday(): void {
    now = new Date();
    dateKey = dateKeyInZone(now, location.timezone);
  }

  function applyLocation(nextLocation: SavedLocation): void {
    location = nextLocation;
    dateKey = dateKeyInZone(new Date(), nextLocation.timezone);
    locationOpen = false;
  }

  async function openLocation(): Promise<void> {
    LocationSheetComponent ??= (await import('./lib/components/LocationSheet.svelte')).default;
    locationOpen = true;
  }
</script>

<svelte:window
  ononline={() => (online = true)}
  onoffline={() => (online = false)}
/>

<svelte:head>
  <title>{location.label} · {longDate} · DayMan</title>
</svelte:head>

{#snippet brandContent()}
  <svg viewBox="0 0 44 44" aria-hidden="true">
    <circle cx="22" cy="22" r="18" />
    <path d="M8 27c5-12 23-12 28 0" />
    <circle cx="22" cy="14" r="3.5" />
  </svg>
  <span>DayMan</span>
{/snippet}

<main>
  <header class="app-header">
    <div class="header-leading">
      {#if installedExperience}
        <span class="brand" aria-label="DayMan">
          {@render brandContent()}
        </span>
      {:else}
        <a class="brand" href={import.meta.env.BASE_URL} aria-label="DayMan home">
          {@render brandContent()}
        </a>
      {/if}
      <InstallMenu />
    </div>

    <div class="header-actions">
      <span class="connection" class:offline={!online}>
        <i></i>{online ? 'Ready offline' : 'Offline'}
      </span>
      <button class="location-button" type="button" onclick={openLocation}>
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M12 21s7-6.1 7-12a7 7 0 10-14 0c0 5.9 7 12 7 12z" />
          <circle cx="12" cy="9" r="2.2" />
        </svg>
        <span>
          <small>Observing from</small>
          <strong>{location.label}</strong>
        </span>
        <svg class="chevron" viewBox="0 0 24 24" aria-hidden="true">
          <path d="m9 7 5 5-5 5" />
        </svg>
      </button>
    </div>
  </header>

  <section class="sky-layout">
    <div class="dial-panel">
      <SkyDial snapshot={clockSnapshot} />
      <nav class="dial-date-control" aria-label="Date navigation">
        <div class="dial-date-row">
          <button class="dial-date-arrow" type="button" aria-label="Previous day" onclick={previousDay}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 5-7 7 7 7" /></svg>
          </button>
          <button
            class="dial-date-label"
            type="button"
            aria-label={sky.isToday
              ? `Today: ${longDate}`
              : `Return to today. Selected date: ${longDate}`}
            onclick={goToday}
          >
            <small>{sky.isToday ? 'Today' : 'Return to today'}</small>
            <strong>{longDate}</strong>
          </button>
          <button class="dial-date-arrow" type="button" aria-label="Next day" onclick={nextDay}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 5 7 7-7 7" /></svg>
          </button>
        </div>
      </nav>
    </div>

    <aside class="details-panel">
      <EventList
        title="Sun cycle"
        eyebrow="Warm light"
        events={solarEvents}
        timezone={location.timezone}
        tone="sun"
      />
      <EventList
        title={sky.moonPhaseName}
        eyebrow={`${Math.round(sky.moonIllumination * 100)}% illuminated`}
        events={lunarEvents}
        timezone={location.timezone}
        tone="moon"
        phaseAngle={sky.moonPhaseAngle}
      />

      <section class="position-card">
        <header>
          <p>At {sky.isToday ? 'this moment' : 'the selected time'}</p>
          <span>{coordinateText}</span>
        </header>
        <div class="position-grid">
          <div>
            <span>Sun altitude</span>
            <strong>{sky.sunPosition.altitude.toFixed(1)}°</strong>
            <small>Az {sky.sunPosition.azimuth.toFixed(0)}°</small>
          </div>
          <div>
            <span>Moon altitude</span>
            <strong>{sky.moonPosition.altitude.toFixed(1)}°</strong>
            <small>Az {sky.moonPosition.azimuth.toFixed(0)}°</small>
          </div>
        </div>
      </section>
    </aside>
  </section>

  <section class="twilight-strip" aria-label="Twilight times">
    <dl class="twilight-table">
      {#each twilightBands as band (band.tone)}
        <div class="twilight-row {band.tone}">
          <dt>
            <i aria-hidden="true"></i>
            <span>{band.label}</span>
          </dt>
          <dd>
            <span class="twilight-moment">
              <small>Dawn</small>
              <strong>
                {band.dawn
                  ? formatClockTime(band.dawn.time, location.timezone)
                  : '—'}
              </strong>
            </span>
            <i class="twilight-separator" aria-hidden="true"></i>
            <span class="twilight-moment">
              <small>Dusk</small>
              <strong>
                {band.dusk
                  ? formatClockTime(band.dusk.time, location.timezone)
                  : '—'}
              </strong>
            </span>
          </dd>
        </div>
      {/each}
    </dl>
  </section>

</main>

{#if locationOpen && LocationSheetComponent}
  <LocationSheetComponent
    {location}
    initialMethod={locationMethod}
    onclose={() => (locationOpen = false)}
    onapply={applyLocation}
    onmethodchange={(method) => (locationMethod = method)}
  />
{/if}
