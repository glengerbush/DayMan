<script lang="ts">
  import type { ClockSnapshot } from '../clock-snapshot';
  import type { SkyInterval } from '../types';
  import MoonPhase from './MoonPhase.svelte';

  interface Props {
    snapshot: ClockSnapshot;
  }

  interface ClockPopover {
    title: string;
    detail: string;
    left: number;
    top: number;
  }

  let { snapshot }: Props = $props();

  const hours = Array.from({ length: 24 }, (_, hour) => hour);

  let handEnd = $derived(
    point(snapshot.referenceMinute, snapshot.geometry.handEndRadius)
  );
  let handStart = $derived(
    point(snapshot.referenceMinute, snapshot.geometry.handStartRadius)
  );
  let moonPoint = $derived(
    point(snapshot.moon.markerMinute, snapshot.geometry.moonRadius)
  );
  let sunArcs = $derived(
    snapshot.arcs.filter((arc) => arc.kind !== 'moon')
  );
  let moonArc = $derived(
    snapshot.arcs.find((arc) => arc.kind === 'moon')
  );
  let hoverMinute = $state<number | null>(null);
  let clockPopover = $state<ClockPopover | null>(null);
  let hoverHand = $derived.by(() => {
    if (hoverMinute === null) return null;
    return {
      start: point(hoverMinute, 64),
      end: point(hoverMinute, 160),
      label: point(hoverMinute, 170),
      time: formatDialMinute(hoverMinute)
    };
  });

  function point(minute: number, radius: number): { x: number; y: number } {
    const angle = (minute / 1440) * Math.PI * 2 - Math.PI / 2;
    return {
      x: snapshot.geometry.center + Math.cos(angle) * radius,
      y: snapshot.geometry.center + Math.sin(angle) * radius
    };
  }

  function intervalDash(interval: SkyInterval): string {
    const length = Math.max(0, interval.endMinute - interval.startMinute);
    return `${length} ${1440 - length}`;
  }

  function formatDialMinute(minute: number): string {
    const normalized = ((Math.round(minute) % 1440) + 1440) % 1440;
    const hour = Math.floor(normalized / 60);
    const minutePart = normalized % 60;
    return `${String(hour).padStart(2, '0')}:${String(minutePart).padStart(2, '0')}`;
  }

  function pointerPosition(event: PointerEvent): {
    x: number;
    y: number;
    distance: number;
    left: number;
    top: number;
  } | null {
    const target = event.currentTarget as SVGElement;
    const dial = target instanceof SVGSVGElement ? target : target.ownerSVGElement;
    if (!dial) return null;

    const bounds = dial.getBoundingClientRect();
    const x = ((event.clientX - bounds.left) / bounds.width) * 420;
    const y = ((event.clientY - bounds.top) / bounds.height) * 420;
    const deltaX = x - snapshot.geometry.center;
    const deltaY = y - snapshot.geometry.center;
    return {
      x,
      y,
      distance: Math.hypot(deltaX, deltaY),
      left: Math.max(18, Math.min(82, (x / 420) * 100)),
      top: Math.max(12, Math.min(92, (y / 420) * 100))
    };
  }

  function showClockPopover(event: PointerEvent, title: string, detail: string): void {
    const position = pointerPosition(event);
    if (!position) return;
    clockPopover = {
      title,
      detail,
      left: position.left,
      top: position.top
    };
  }

  function handlePointerMove(event: PointerEvent): void {
    const position = pointerPosition(event);
    if (!position) return;

    if (clockPopover) {
      clockPopover = {
        ...clockPopover,
        left: position.left,
        top: position.top
      };
    }

    if (position.distance < 76 || position.distance > 202) {
      hoverMinute = null;
      return;
    }

    const angle =
      Math.atan2(
        position.y - snapshot.geometry.center,
        position.x - snapshot.geometry.center
      ) + Math.PI / 2;
    const normalizedAngle = (angle + Math.PI * 2) % (Math.PI * 2);
    hoverMinute = Math.round((normalizedAngle / (Math.PI * 2)) * 1440) % 1440;
  }

  function clearClockHover(): void {
    hoverMinute = null;
    clockPopover = null;
  }
</script>

<div class="dial-wrap">
  <svg
    class="dial"
    viewBox={`0 0 ${snapshot.geometry.viewBox} ${snapshot.geometry.viewBox}`}
    role="img"
    aria-label={snapshot.accessibilityText}
    aria-describedby="dial-description"
    onpointermove={handlePointerMove}
    onpointerleave={clearClockHover}
  >
    <desc id="dial-description">
      {snapshot.accessibilityText}
    </desc>

    <defs>
      <filter id="soft-glow" x="-100%" y="-100%" width="300%" height="300%">
        <feGaussianBlur stdDeviation="3" result="blur" />
        <feMerge>
          <feMergeNode in="blur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
      <radialGradient id="dial-face" cx="48%" cy="40%">
        <stop offset="0%" stop-color="#1c2a43" />
        <stop offset="70%" stop-color="#111b2e" />
        <stop offset="100%" stop-color="#0c1424" />
      </radialGradient>
    </defs>

    <circle
      cx={snapshot.geometry.center}
      cy={snapshot.geometry.center}
      r={snapshot.geometry.outerRadius + 11}
      class="outer-shadow"
    />
    <circle
      cx={snapshot.geometry.center}
      cy={snapshot.geometry.center}
      r={snapshot.geometry.outerRadius}
      fill="url(#dial-face)"
      class="face"
    />

    {#each hours as hour (hour)}
      {@const outer = point(hour * 60, snapshot.geometry.outerRadius - 2)}
      {@const inner = point(hour * 60, hour % 3 === 0 ? 179 : 183)}
      <line
        x1={inner.x}
        y1={inner.y}
        x2={outer.x}
        y2={outer.y}
        class:major={hour % 3 === 0}
        class="hour-tick"
      />
    {/each}

    {#each snapshot.hourLabels as hour (hour.hour)}
      {@const labelPoint = point(hour.minute, snapshot.geometry.hourLabelRadius)}
      <text x={labelPoint.x} y={labelPoint.y} class="hour-label">{hour.label}</text>
    {/each}

    <circle
      cx={snapshot.geometry.center}
      cy={snapshot.geometry.center}
      r={snapshot.geometry.sunRadius}
      class="track day-track"
      pathLength="1440"
    />

    {#each sunArcs as arc (arc.kind)}
      {#each arc.ranges as interval (`${arc.kind}-${interval.startMinute}`)}
        <circle
          cx={snapshot.geometry.center}
          cy={snapshot.geometry.center}
          r={arc.radius}
          class="arc {arc.kind}-arc"
          role={arc.kind === 'daylight' ? undefined : 'img'}
          aria-label={arc.kind === 'daylight'
            ? undefined
            : `${arc.label}: ${arc.detail}`}
          pathLength="1440"
          stroke-dasharray={intervalDash(interval)}
          stroke-dashoffset={-interval.startMinute}
          onpointerenter={(event) => {
            if (arc.kind !== 'daylight') {
              showClockPopover(event, arc.label, arc.detail);
            }
          }}
          onpointerleave={() => (clockPopover = null)}
        />
      {/each}
    {/each}

    <circle
      cx={snapshot.geometry.center}
      cy={snapshot.geometry.center}
      r={snapshot.geometry.moonRadius}
      class="track moon-track"
      pathLength="1440"
    />
    {#each moonArc?.ranges ?? [] as interval (`moon-${interval.startMinute}`)}
      <circle
        cx={snapshot.geometry.center}
        cy={snapshot.geometry.center}
        r={moonArc?.radius ?? snapshot.geometry.moonRadius}
        class="arc moon-arc"
        pathLength="1440"
        stroke-dasharray={intervalDash(interval)}
        stroke-dashoffset={-interval.startMinute}
      />
    {/each}

    {#each snapshot.events.filter((event) => event.visibleOnDial) as event (event.kind)}
      {@const eventPoint = point(event.minute, event.radius)}
      <circle
        cx={eventPoint.x}
        cy={eventPoint.y}
        r="3.5"
        class="event-dot {event.body} {event.marker}"
        role="img"
        aria-label={`${event.label}: ${event.timeLabel}`}
        onpointerenter={(pointerEvent) =>
          showClockPopover(
            pointerEvent,
            event.label,
            event.timeLabel
          )}
        onpointerleave={() => (clockPopover = null)}
      />
    {/each}

    {#if hoverHand}
      <line
        x1={hoverHand.start.x}
        y1={hoverHand.start.y}
        x2={hoverHand.end.x}
        y2={hoverHand.end.y}
        class="hover-hand"
      />
      <text x={hoverHand.label.x} y={hoverHand.label.y} class="hover-time">
        {hoverHand.time}
      </text>
    {/if}

    <line
      x1={handStart.x}
      y1={handStart.y}
      x2={handEnd.x}
      y2={handEnd.y}
      class="time-hand"
    />

    <g
      transform={`translate(${moonPoint.x} ${moonPoint.y})`}
      filter="url(#soft-glow)"
      class="moon-marker"
    >
      <MoonPhase phaseAngle={snapshot.moon.phaseAngle} id="dial-moon" />
    </g>

    <circle
      cx={snapshot.geometry.center}
      cy={snapshot.geometry.center}
      r="76"
      class="center-disc"
    />
    <text x={snapshot.geometry.center} y="188" class="center-kicker">CURRENT TIME</text>
    <text x={snapshot.geometry.center} y="216" class="center-value">
      {snapshot.currentTimeLabel}
    </text>
    <text x={snapshot.geometry.center} y="238" class="center-sub">
      {snapshot.nextSolarEvent?.relativeLabel ?? 'No sunrise or sunset found'}
    </text>
  </svg>

  {#if clockPopover}
    <div
      class="clock-popover"
      role="tooltip"
      style:left={`${clockPopover.left}%`}
      style:top={`${clockPopover.top}%`}
    >
      <strong>{clockPopover.title}</strong>
      <span>{clockPopover.detail}</span>
    </div>
  {/if}
</div>

<style>
  .dial-wrap {
    position: relative;
    width: min(100%, 38rem);
    margin: 0 auto;
  }

  .dial {
    display: block;
    width: 100%;
    height: auto;
    overflow: visible;
  }

  .outer-shadow {
    fill: #0a111f;
    stroke: rgb(255 255 255 / 0.08);
    stroke-width: 1;
    filter: drop-shadow(0 22px 35px rgb(3 8 18 / 0.45));
  }

  .face {
    stroke: rgb(255 255 255 / 0.06);
    stroke-width: 1;
  }

  .hour-tick {
    stroke: rgb(226 235 248 / 0.3);
    stroke-width: 0.8;
  }

  .hour-tick.major {
    stroke: rgb(240 245 252 / 0.68);
    stroke-width: 1.4;
  }

  .hour-label {
    fill: rgb(230 238 250 / 0.64);
    font-family: var(--font-mono);
    font-size: 8px;
    font-weight: 600;
    text-anchor: middle;
    dominant-baseline: central;
    letter-spacing: 0.08em;
  }

  .track,
  .arc {
    fill: none;
    transform: rotate(-90deg);
    transform-origin: 210px 210px;
  }

  .track {
    stroke-linecap: round;
  }

  .day-track {
    stroke: #222a39;
    stroke-width: 15;
  }

  .moon-track {
    stroke: rgb(203 220 234 / 0.1);
    stroke-width: 10;
  }

  .arc {
    stroke-linecap: butt;
  }

  .astronomical-arc {
    stroke: #2d405d;
    stroke-width: 15;
  }

  .nautical-arc {
    stroke: #435e7a;
    stroke-width: 15;
  }

  .civil-arc {
    stroke: #718ba3;
    stroke-width: 15;
  }

  .daylight-arc {
    stroke: #ffb552;
    stroke-width: 15;
    filter: drop-shadow(0 0 5px rgb(255 174 72 / 0.3));
  }

  .moon-arc {
    stroke: #d9e5ea;
    stroke-width: 10;
    filter: drop-shadow(0 0 5px rgb(217 229 234 / 0.2));
  }

  .event-dot {
    stroke: #10192a;
    stroke-width: 2;
    cursor: help;
    transition:
      r 100ms ease,
      filter 100ms ease;
  }

  .event-dot:hover {
    r: 4.5px;
    filter: brightness(1.25);
  }

  .event-dot.sun {
    fill: #ffe3aa;
  }

  .event-dot.moon {
    fill: #f4f8f7;
  }

  .time-hand {
    stroke: rgb(242 247 252 / 0.72);
    stroke-width: 1.5;
    stroke-dasharray: 3 3;
    pointer-events: none;
  }

  .hover-hand {
    stroke: rgb(204 219 233 / 0.34);
    stroke-width: 0.75;
    stroke-dasharray: 1.5 3.5;
    pointer-events: none;
  }

  .hover-time {
    fill: #dce6ef;
    stroke: #101a2d;
    stroke-width: 3px;
    paint-order: stroke fill;
    font-family: var(--font-mono);
    font-size: 8px;
    font-weight: 700;
    text-anchor: middle;
    dominant-baseline: central;
    letter-spacing: 0.03em;
    pointer-events: none;
  }

  .astronomical-arc,
  .nautical-arc,
  .civil-arc {
    cursor: help;
    pointer-events: stroke;
    transition: filter 120ms ease;
  }

  .astronomical-arc:hover,
  .nautical-arc:hover,
  .civil-arc:hover {
    filter: brightness(1.3);
  }

  .clock-popover {
    position: absolute;
    z-index: 3;
    display: grid;
    gap: 0.18rem;
    width: max-content;
    max-width: 12rem;
    padding: 0.55rem 0.7rem;
    border: 1px solid rgb(198 216 232 / 0.18);
    border-radius: 0.65rem;
    background: rgb(9 17 30 / 0.94);
    box-shadow:
      0 10px 28px rgb(2 7 15 / 0.45),
      inset 0 1px rgb(255 255 255 / 0.04);
    color: #edf3f7;
    pointer-events: none;
    transform: translate(-50%, calc(-100% - 0.75rem));
    backdrop-filter: blur(10px);
  }

  .clock-popover::after {
    position: absolute;
    top: 100%;
    left: 50%;
    width: 0;
    height: 0;
    border: 0.32rem solid transparent;
    border-top-color: rgb(9 17 30 / 0.94);
    content: '';
    transform: translateX(-50%);
  }

  .clock-popover strong {
    font-family: var(--font-sans);
    font-size: 0.7rem;
    font-weight: 700;
    letter-spacing: 0.025em;
  }

  .clock-popover span {
    color: #94a9bc;
    font-family: var(--font-mono);
    font-size: 0.6rem;
    line-height: 1.35;
  }

  .center-disc {
    fill: rgb(11 19 33 / 0.68);
    stroke: rgb(255 255 255 / 0.08);
    stroke-width: 1;
  }

  .center-kicker,
  .center-value,
  .center-sub {
    fill: #edf2f7;
    text-anchor: middle;
  }

  .center-kicker {
    font-family: var(--font-sans);
    font-size: 7px;
    font-weight: 700;
    letter-spacing: 0.19em;
    fill: #91a4bc;
  }

  .center-value {
    font-family: var(--font-display);
    font-size: 22px;
    font-weight: 500;
  }

  .center-sub {
    font-family: var(--font-sans);
    font-size: 8px;
    font-weight: 600;
    fill: #8ca1b7;
  }

</style>
