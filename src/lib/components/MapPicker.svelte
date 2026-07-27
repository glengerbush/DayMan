<script lang="ts">
  import * as maplibregl from 'maplibre-gl';
  import type { MapMouseEvent } from 'maplibre-gl';
  import type { Attachment } from 'svelte/attachments';
  import 'maplibre-gl/dist/maplibre-gl.css';

  interface Props {
    latitude: number;
    longitude: number;
    onpick: (latitude: number, longitude: number) => void;
  }

  let { latitude, longitude, onpick }: Props = $props();

  const mapAttachment: Attachment<HTMLDivElement> = (element) => {
    const markerElement = document.createElement('div');
    markerElement.className = 'dayman-map-marker';
    markerElement.setAttribute('aria-label', 'Selected location');
    const markerPin = document.createElement('div');
    markerPin.className = 'dayman-map-marker-pin';
    markerElement.append(markerPin);

    const map = new maplibregl.Map({
      container: element,
      center: [longitude, latitude],
      zoom: 7,
      attributionControl: false,
      style: {
        version: 8,
        sources: {
          osm: {
            type: 'raster',
            tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
            tileSize: 256,
            attribution: '© OpenStreetMap contributors'
          }
        },
        layers: [{ id: 'osm', type: 'raster', source: 'osm' }]
      }
    });

    const marker = new maplibregl.Marker({
      element: markerElement,
      anchor: 'bottom',
      draggable: true
    })
      .setLngLat([longitude, latitude])
      .addTo(map);

    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
    map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-right');

    map.on('click', (event: MapMouseEvent) => {
      onpick(event.lngLat.lat, event.lngLat.lng);
    });

    marker.on('dragend', () => {
      const point = marker.getLngLat();
      onpick(point.lat, point.lng);
    });

    $effect(() => {
      marker.setLngLat([longitude, latitude]);
    });

    return () => {
      marker.remove();
      map.remove();
    };
  };
</script>

<div class="map-shell">
  <div class="map" {@attach mapAttachment}></div>
  <p>Click or tap where the crosshair points, or drag the pin. Map tiles require a connection.</p>
</div>

<style>
  .map-shell {
    overflow: hidden;
    border: 1px solid var(--line);
    border-radius: 1rem;
    background: var(--surface-deep);
  }

  .map {
    height: 16rem;
  }

  :global(.maplibregl-canvas-container.maplibregl-interactive) {
    cursor: crosshair;
  }

  :global(.maplibregl-canvas-container.maplibregl-interactive:active) {
    cursor: move;
  }

  .map-shell p {
    margin: 0;
    padding: 0.7rem 0.9rem;
    color: var(--text-muted);
    font-size: 0.73rem;
  }

  :global(.dayman-map-marker) {
    display: grid;
    width: 2.25rem;
    height: 2.25rem;
    place-items: center;
    cursor: grab;
  }

  :global(.dayman-map-marker-pin) {
    box-sizing: border-box;
    width: 1.6rem;
    height: 1.6rem;
    border: 0.3rem solid #fff6df;
    border-radius: 50% 50% 50% 0;
    background: #e9814f;
    box-shadow: 0 4px 12px rgb(23 30 43 / 0.4);
    transform: rotate(-45deg);
  }

  :global(.dayman-map-marker:active) {
    cursor: grabbing;
  }

  :global(.maplibregl-ctrl-attrib) {
    font-size: 10px;
  }
</style>
