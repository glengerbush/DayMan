<script lang="ts">
  import { untrack, type Component } from 'svelte';
  import {
    availableTimezones,
    coordinatesLabel,
    detectTimezone,
    lookupZipCode
  } from '../location';
  import { isValidTimezone } from '../time';
  import type { LocationMethod, LocationSource, SavedLocation } from '../types';

  interface Props {
    location: SavedLocation;
    initialMethod: LocationMethod;
    onclose: () => void;
    onapply: (location: SavedLocation) => void;
    onmethodchange: (method: LocationMethod) => void;
  }

  let { location, initialMethod, onclose, onapply, onmethodchange }: Props = $props();

  const initialLocation = untrack(() => location);
  const initialLocationMethod = untrack(() => initialMethod);
  let draft = $state<SavedLocation>({ ...initialLocation });
  let autoTimezone = $state<string | null>(
    timezoneForCoordinates(initialLocation.latitude, initialLocation.longitude)
  );
  let timezoneSelectionVersion = $state(0);
  let method = $state<LocationMethod>(initialLocationMethod);
  let MapPickerComponent = $state<Component<{
    latitude: number;
    longitude: number;
    onpick: (latitude: number, longitude: number) => void;
  }> | null>(null);
  let zip = $state(initialLocation.postalCode ?? '');
  let manualLatitude = $state(String(initialLocation.latitude));
  let manualLongitude = $state(String(initialLocation.longitude));
  let status = $state('');
  let isLocating = $state(false);
  let isSearching = $state(false);
  const timezones = availableTimezones();

  if (initialLocationMethod === 'map') {
    void loadMapPicker();
  }

  let coordinates = $derived(coordinatesLabel(draft.latitude, draft.longitude));
  let timezoneValid = $derived(isValidTimezone(draft.timezone));
  let timezoneOverridden = $derived(
    autoTimezone !== null && draft.timezone !== autoTimezone
  );
  let canSave = $derived(
    timezoneValid &&
      draft.label.trim().length > 0 &&
      Number.isFinite(draft.latitude) &&
      Number.isFinite(draft.longitude)
  );

  function updateCoordinates(
    latitude: number,
    longitude: number,
    source: LocationSource,
    label?: string
  ): void {
    draft.latitude = Math.max(-90, Math.min(90, latitude));
    draft.longitude = Math.max(-180, Math.min(180, longitude));
    draft.source = source;
    draft.postalCode = source === 'postal' ? draft.postalCode : undefined;
    if (label) draft.label = label;
    manualLatitude = String(Number(draft.latitude.toFixed(6)));
    manualLongitude = String(Number(draft.longitude.toFixed(6)));

    const detectedTimezone = timezoneForCoordinates(draft.latitude, draft.longitude);
    if (detectedTimezone) {
      setAutomaticTimezone(detectedTimezone);
      status = 'Coordinates and timezone updated.';
    } else {
      autoTimezone = null;
      status = 'Coordinates updated. Please choose a timezone below.';
    }
  }

  function timezoneForCoordinates(latitude: number, longitude: number): string | null {
    try {
      return detectTimezone(latitude, longitude);
    } catch {
      return null;
    }
  }

  function setAutomaticTimezone(timezone: string): void {
    autoTimezone = timezone;
    draft.timezone = timezone;
    timezoneSelectionVersion += 1;
  }

  function restoreAutomaticTimezone(): void {
    if (!autoTimezone) return;
    draft.timezone = autoTimezone;
    timezoneSelectionVersion += 1;
  }

  function useGps(): void {
    if (!navigator.geolocation) {
      status = 'Location services are not supported in this browser.';
      return;
    }

    isLocating = true;
    status = 'Finding your position…';
    navigator.geolocation.getCurrentPosition(
      (position) => {
        updateCoordinates(
          position.coords.latitude,
          position.coords.longitude,
          'gps',
          'Current location'
        );
        isLocating = false;
      },
      (error) => {
        status =
          error.code === error.PERMISSION_DENIED
            ? 'Location permission was declined. Try a ZIP code or map pin.'
            : 'Your position could not be found. Try a ZIP code or map pin.';
        isLocating = false;
      },
      { enableHighAccuracy: false, timeout: 10_000, maximumAge: 300_000 }
    );
  }

  async function searchZip(): Promise<void> {
    const postalCode = zip.trim();
    if (!/^[0-9]{5}$/.test(postalCode)) {
      status = 'Enter a five-digit US ZIP code.';
      return;
    }

    zip = postalCode;
    isSearching = true;
    status = 'Looking up ZIP code…';

    try {
      const result = await lookupZipCode(postalCode);
      if (!result) {
        status = 'That ZIP code is not represented in the 2025 Census ZCTA data.';
        return;
      }
      draft = { ...result };
      autoTimezone = result.timezone;
      timezoneSelectionVersion += 1;
      manualLatitude = String(result.latitude);
      manualLongitude = String(result.longitude);
      status = 'Using the Census representative point.';
    } catch {
      status = 'ZIP data could not be loaded. Check the connection once, or use coordinates.';
    } finally {
      isSearching = false;
    }
  }

  function handleZipSubmit(event: SubmitEvent): void {
    event.preventDefault();
    void searchZip();
  }

  function handleZipKeydown(event: KeyboardEvent): void {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    void searchZip();
  }

  function applyManualCoordinates(): void {
    const latitude = Number(manualLatitude);
    const longitude = Number(manualLongitude);
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      status = 'Enter a latitude from −90 to 90 and longitude from −180 to 180.';
      return;
    }
    updateCoordinates(latitude, longitude, 'coordinates', 'Custom location');
  }

  function handleCoordinateSubmit(event: SubmitEvent): void {
    event.preventDefault();
    applyManualCoordinates();
  }

  function handleCoordinateKeydown(event: KeyboardEvent): void {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    applyManualCoordinates();
  }

  function pickOnMap(latitude: number, longitude: number): void {
    updateCoordinates(latitude, longitude, 'map', 'Pinned location');
  }

  async function loadMapPicker(): Promise<void> {
    MapPickerComponent ??= (await import('./MapPicker.svelte')).default;
  }

  async function chooseMethod(nextMethod: LocationMethod): Promise<void> {
    method = nextMethod;
    onmethodchange(nextMethod);
    if (nextMethod === 'map') {
      await loadMapPicker();
    }
  }

  function save(): void {
    if (!canSave) return;
    onapply({ ...draft, label: draft.label.trim() });
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') onclose();
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<div
  class="backdrop"
  role="presentation"
  onclick={(event) => {
    if (event.target === event.currentTarget) onclose();
  }}
>
  <div
    class="sheet"
    role="dialog"
    aria-modal="true"
    aria-labelledby="location-title"
    data-testid="location-sheet"
  >
    <header class="sheet-header">
      <div>
        <p class="eyebrow">Observer position</p>
        <h2 id="location-title">Choose a location</h2>
      </div>
      <button class="icon-button" type="button" aria-label="Close location settings" onclick={onclose}>
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M6 6l12 12M18 6L6 18" />
        </svg>
      </button>
    </header>

    <div class="quick-actions">
      <button class="gps-button" type="button" onclick={useGps} disabled={isLocating}>
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <circle cx="12" cy="12" r="3" />
          <path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2" />
        </svg>
        {isLocating ? 'Locating…' : 'Use my location'}
      </button>
      <span>{coordinates}</span>
    </div>

    <div class="method-tabs" role="tablist" aria-label="Location method">
      <button
        type="button"
        role="tab"
        aria-selected={method === 'map'}
        class:active={method === 'map'}
        onclick={() => chooseMethod('map')}>Drop a pin</button
      >
      <button
        type="button"
        role="tab"
        aria-selected={method === 'postal'}
        class:active={method === 'postal'}
        onclick={() => chooseMethod('postal')}>ZIP code</button
      >
      <button
        type="button"
        role="tab"
        aria-selected={method === 'coordinates'}
        class:active={method === 'coordinates'}
        onclick={() => chooseMethod('coordinates')}>Coordinates</button
      >
    </div>

    <div class="method-panel">
      {#if method === 'postal'}
        <form class="zip-form" novalidate onsubmit={handleZipSubmit}>
          <label for="zip">US ZIP code</label>
          <div>
            <input
              id="zip"
              bind:value={zip}
              inputmode="numeric"
              maxlength="5"
              placeholder="e.g. 10001"
              autocomplete="postal-code"
              onkeydown={handleZipKeydown}
            />
            <button type="submit" disabled={isSearching}>
              {isSearching ? 'Finding…' : 'Find'}
            </button>
          </div>
          <p>Uses an offline 2025 US Census ZIP-area representative point.</p>
        </form>
      {:else if method === 'map'}
        {#if MapPickerComponent}
          <MapPickerComponent
            latitude={draft.latitude}
            longitude={draft.longitude}
            onpick={pickOnMap}
          />
        {:else}
          <div class="map-loading">Loading the map…</div>
        {/if}
      {:else}
        <form class="coordinate-form" novalidate onsubmit={handleCoordinateSubmit}>
          <div class="field-pair">
            <label>
              <span>Latitude</span>
              <input
                type="number"
                min="-90"
                max="90"
                step="any"
                bind:value={manualLatitude}
                onkeydown={handleCoordinateKeydown}
              />
            </label>
            <label>
              <span>Longitude</span>
              <input
                type="number"
                min="-180"
                max="180"
                step="any"
                bind:value={manualLongitude}
                onkeydown={handleCoordinateKeydown}
              />
            </label>
          </div>
          <button type="submit">Use coordinates</button>
        </form>
      {/if}
    </div>

    {#if status}
      <p class="status" aria-live="polite">{status}</p>
    {/if}

    <div class="details-grid">
      <label class="detail-field">
        <span>Location name</span>
        <input bind:value={draft.label} placeholder="Home, cabin, observatory…" />
      </label>
      <div class="detail-field">
        <label for="timezone-input">Timezone</label>
        {#key timezoneSelectionVersion}
          <div class="timezone-input-row" class:auto-selected={timezoneSelectionVersion > 0}>
            <input
              id="timezone-input"
              bind:value={draft.timezone}
              list="timezone-options"
              aria-invalid={!timezoneValid}
              autocomplete="off"
              spellcheck="false"
            />
            {#if timezoneOverridden}
              <button
                class="timezone-reset"
                type="button"
                aria-label={`Restore automatically selected timezone: ${autoTimezone}`}
                onclick={restoreAutomaticTimezone}
              >
                <svg viewBox="0 0 24 24" aria-hidden="true">
                  <path d="M20 6v5h-5M19 11a7 7 0 1 0-2 5" />
                </svg>
              </button>
            {/if}
          </div>
        {/key}
        <datalist id="timezone-options">
          {#each timezones as timezone (timezone)}
            <option value={timezone}></option>
          {/each}
        </datalist>
      </div>
    </div>

    <footer>
      <button class="secondary-button" type="button" onclick={onclose}>Cancel</button>
      <button class="primary-button" type="button" onclick={save} disabled={!canSave}>
        Apply location
      </button>
    </footer>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    z-index: 20;
    inset: 0;
    display: grid;
    place-items: center;
    padding: 1rem;
    background: rgb(3 8 17 / 0.76);
    backdrop-filter: blur(12px);
  }

  .sheet {
    width: min(100%, 42rem);
    max-height: min(92vh, 54rem);
    overflow: auto;
    padding: 1.4rem;
    border: 1px solid rgb(255 255 255 / 0.12);
    border-radius: 1.5rem;
    background: #121d30;
    box-shadow: 0 2rem 6rem rgb(0 0 0 / 0.5);
  }

  .sheet-header,
  .quick-actions,
  footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  .eyebrow {
    margin: 0 0 0.3rem;
    color: var(--accent);
    font-size: 0.68rem;
    font-weight: 700;
    letter-spacing: 0.18em;
    text-transform: uppercase;
  }

  h2 {
    margin: 0;
    font-family: var(--font-display);
    font-size: clamp(1.6rem, 5vw, 2.2rem);
    font-weight: 500;
  }

  .icon-button {
    display: grid;
    width: 2.55rem;
    height: 2.55rem;
    padding: 0;
    place-items: center;
    border: 1px solid var(--line);
    border-radius: 50%;
    color: var(--text);
    background: rgb(255 255 255 / 0.04);
  }

  .icon-button svg,
  .gps-button svg {
    width: 1.1rem;
    fill: none;
    stroke: currentColor;
    stroke-linecap: round;
    stroke-width: 1.7;
  }

  .quick-actions {
    margin: 1.35rem 0 1rem;
  }

  .quick-actions span {
    color: var(--text-muted);
    font-family: var(--font-mono);
    font-size: 0.73rem;
    text-align: right;
  }

  .gps-button {
    display: inline-flex;
    align-items: center;
    gap: 0.55rem;
    padding: 0.72rem 0.95rem;
    border: 1px solid rgb(255 190 92 / 0.3);
    border-radius: 0.8rem;
    color: #ffd592;
    background: rgb(255 181 82 / 0.08);
  }

  .method-tabs {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    padding: 0.28rem;
    border: 1px solid var(--line);
    border-radius: 0.85rem;
    background: var(--surface-deep);
  }

  .method-tabs button {
    padding: 0.65rem 0.4rem;
    border: 0;
    border-radius: 0.62rem;
    color: var(--text-muted);
    background: transparent;
    font-size: 0.78rem;
  }

  .method-tabs button.active {
    color: var(--text);
    background: #26344b;
    box-shadow: 0 2px 8px rgb(0 0 0 / 0.24);
  }

  .method-panel {
    min-height: 10rem;
    padding: 1rem 0 0;
  }

  .map-loading {
    display: grid;
    height: 16rem;
    place-items: center;
    border: 1px solid var(--line);
    border-radius: 1rem;
    color: var(--text-muted);
    background: var(--surface-deep);
    font-size: 0.8rem;
  }

  label,
  .zip-form {
    display: grid;
    gap: 0.45rem;
  }

  label span,
  .detail-field > label,
  .zip-form > label {
    color: var(--text-soft);
    font-size: 0.76rem;
    font-weight: 650;
  }

  input {
    width: 100%;
    min-width: 0;
    padding: 0.78rem 0.85rem;
    border: 1px solid var(--line-strong);
    border-radius: 0.72rem;
    outline: none;
    color: var(--text);
    background: var(--surface-deep);
  }

  input:focus {
    border-color: rgb(255 188 91 / 0.72);
    box-shadow: 0 0 0 3px rgb(255 181 82 / 0.1);
  }

  input[aria-invalid='true'] {
    border-color: #d26f6f;
  }

  .zip-form > div {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 0.6rem;
  }

  .zip-form button,
  .coordinate-form > button {
    padding: 0.75rem 1rem;
    border: 1px solid var(--line-strong);
    border-radius: 0.72rem;
    color: var(--text);
    background: #26344b;
  }

  .zip-form p {
    margin: 0;
    color: var(--text-muted);
    font-size: 0.69rem;
    line-height: 1.45;
  }

  .coordinate-form {
    display: grid;
    gap: 0.8rem;
  }

  .field-pair,
  .details-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.8rem;
  }

  .status {
    margin: 0 0 1rem;
    padding: 0.72rem 0.85rem;
    border-radius: 0.72rem;
    color: #c9d7e6;
    background: rgb(93 126 157 / 0.13);
    font-size: 0.76rem;
    line-height: 1.45;
  }

  .details-grid {
    align-items: start;
    padding-top: 1rem;
    border-top: 1px solid var(--line);
  }

  .detail-field {
    display: grid;
    min-width: 0;
    gap: 0.45rem;
  }

  .timezone-input-row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 0.45rem;
  }

  .timezone-input-row.auto-selected input {
    animation: timezone-selected 700ms ease-out;
  }

  .timezone-reset {
    display: grid;
    width: 2.85rem;
    padding: 0;
    place-items: center;
    border: 1px solid var(--line-strong);
    border-radius: 0.72rem;
    color: var(--accent);
    background: color-mix(in srgb, var(--surface-deep) 84%, var(--accent) 16%);
    cursor: pointer;
  }

  .timezone-reset:hover {
    border-color: var(--accent);
    background: color-mix(in srgb, var(--surface-deep) 74%, var(--accent) 26%);
  }

  .timezone-reset:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }

  .timezone-reset svg {
    width: 1.15rem;
    height: 1.15rem;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  @keyframes timezone-selected {
    0% {
      border-color: var(--accent);
      background: color-mix(in srgb, var(--surface-deep) 82%, var(--accent) 18%);
      box-shadow: 0 0 0 0 color-mix(in srgb, var(--accent) 35%, transparent);
    }

    45% {
      box-shadow: 0 0 0 4px color-mix(in srgb, var(--accent) 18%, transparent);
    }

    100% {
      border-color: var(--line-strong);
      background: var(--surface-deep);
      box-shadow: 0 0 0 0 transparent;
    }
  }

  footer {
    justify-content: flex-end;
    margin-top: 1.3rem;
    padding-top: 1.1rem;
    border-top: 1px solid var(--line);
  }

  footer button {
    padding: 0.78rem 1rem;
    border-radius: 0.78rem;
  }

  .secondary-button {
    border: 1px solid var(--line-strong);
    color: var(--text-soft);
    background: transparent;
  }

  .primary-button {
    border: 1px solid #ffc572;
    color: #182033;
    background: #ffc572;
    font-weight: 750;
  }

  button:disabled {
    cursor: not-allowed;
    opacity: 0.5;
  }

  @media (max-width: 620px) {
    .backdrop {
      align-items: end;
      padding: 0;
    }

    .sheet {
      max-height: 94vh;
      border-radius: 1.5rem 1.5rem 0 0;
    }

    .details-grid,
    .field-pair {
      grid-template-columns: 1fr;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .timezone-input-row.auto-selected input {
      animation: none;
    }
  }
</style>
