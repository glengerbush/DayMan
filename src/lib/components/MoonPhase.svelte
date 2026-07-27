<svelte:options namespace="svg" />

<script lang="ts">
  interface Props {
    phaseAngle: number;
    id: string;
  }

  let { phaseAngle, id }: Props = $props();

  let phaseShape = $derived(moonPhasePath(phaseAngle));
  let clipId = $derived(`${id}-lit-clip`);

  function moonPhasePath(angle: number, radius = 9): string {
    const phase = ((angle % 360) + 360) % 360;
    const terminatorRadius = Math.max(
      0.05,
      Math.abs(Math.cos((phase * Math.PI) / 180)) * radius
    );
    const waxing = phase <= 180;
    const outerSweep = waxing ? 1 : 0;
    const terminatorSweep = waxing ? (phase < 90 ? 0 : 1) : phase < 270 ? 0 : 1;

    return [
      `M 0 ${-radius}`,
      `A ${radius} ${radius} 0 0 ${outerSweep} 0 ${radius}`,
      `A ${terminatorRadius} ${radius} 0 0 ${terminatorSweep} 0 ${-radius}`,
      'Z'
    ].join(' ');
  }
</script>

<defs>
  <clipPath id={clipId} clipPathUnits="userSpaceOnUse">
    <path d={phaseShape} />
  </clipPath>
</defs>

<g class="moon-phase">
  <circle r="9" class="moon-hidden" />
  <image
    href="/moon-nearside.webp"
    x="-9"
    y="-9"
    width="18"
    height="18"
    preserveAspectRatio="xMidYMid slice"
    clip-path={`url(#${clipId})`}
    class="moon-texture"
  />
  <circle r="9" class="moon-outline" />
</g>

<style>
  .moon-hidden {
    fill: #050b14;
  }

  .moon-texture {
    filter: saturate(0) contrast(1.04) brightness(1.03);
  }

  .moon-outline {
    fill: none;
    stroke: rgb(221 231 232 / 0.56);
    stroke-width: 0.5;
  }
</style>
