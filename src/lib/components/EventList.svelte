<script lang="ts">
  import { formatClockTime } from '../time';
  import type { SkyEvent } from '../types';
  import MoonPhase from './MoonPhase.svelte';

  interface Props {
    title: string;
    eyebrow: string;
    events: SkyEvent[];
    timezone: string;
    tone: 'sun' | 'moon';
    phaseAngle?: number;
  }

  let { title, eyebrow, events, timezone, tone, phaseAngle }: Props = $props();
</script>

<section class="event-panel {tone}">
  <header>
    <div>
      <p>{eyebrow}</p>
      <h2>{title}</h2>
    </div>
    {#if tone === 'moon' && phaseAngle !== undefined}
      <svg class="orb moon-orb" viewBox="-11 -11 22 22" aria-hidden="true">
        <MoonPhase {phaseAngle} id="event-panel-moon" />
      </svg>
    {:else}
      <span class="orb" aria-hidden="true"></span>
    {/if}
  </header>

  <div class="events">
    {#each events as event (event.kind)}
      <div class="event-row">
        <span>{event.label}</span>
        <time datetime={event.time.toISOString()}>{formatClockTime(event.time, timezone)}</time>
      </div>
    {:else}
      <p class="empty">No horizon crossing on this date.</p>
    {/each}
  </div>
</section>

<style>
  .event-panel {
    padding: 1.2rem;
    border: 1px solid var(--line);
    border-radius: 1.2rem;
    background: linear-gradient(145deg, rgb(255 255 255 / 0.045), rgb(255 255 255 / 0.018));
  }

  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-bottom: 1rem;
    border-bottom: 1px solid var(--line);
  }

  header p {
    margin: 0 0 0.22rem;
    color: var(--text-muted);
    font-size: 0.66rem;
    font-weight: 700;
    letter-spacing: 0.15em;
    text-transform: uppercase;
  }

  h2 {
    margin: 0;
    font-family: var(--font-display);
    font-size: 1.45rem;
    font-weight: 500;
  }

  .orb {
    width: 2.15rem;
    height: 2.15rem;
    border-radius: 50%;
  }

  .sun .orb {
    background: #ffc461;
    box-shadow: 0 0 1rem rgb(255 186 81 / 0.45);
  }

  .moon .moon-orb {
    overflow: visible;
    filter: drop-shadow(0 0 0.55rem rgb(221 233 239 / 0.38));
  }

  .events {
    padding-top: 0.35rem;
  }

  .event-row {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    padding: 0.72rem 0;
    color: var(--text-soft);
    font-size: 0.86rem;
  }

  .event-row + .event-row {
    border-top: 1px solid rgb(255 255 255 / 0.045);
  }

  time {
    color: var(--text);
    font-family: var(--font-mono);
    font-size: 0.82rem;
    font-weight: 600;
  }

  .empty {
    margin: 0.8rem 0 0.35rem;
    color: var(--text-muted);
    font-size: 0.82rem;
  }
</style>
