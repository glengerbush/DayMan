import { svelte } from '@sveltejs/vite-plugin-svelte';
import { loadEnv } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';
import { configDefaults, defineConfig } from 'vitest/config';

function normalizeBasePath(value: string | undefined): string {
  const path = value?.trim();
  if (!path || path === '/') return '/';
  if (path === '.' || path === './') return './';
  return `/${path.replace(/^\/+|\/+$/g, '')}/`;
}

export default defineConfig(({ mode }) => {
  const base = normalizeBasePath(loadEnv(mode, '.', '').VITE_BASE_PATH);

  return {
    base,
    optimizeDeps: {
      exclude: ['maplibre-gl']
    },
    plugins: [
      svelte(),
      VitePWA({
        registerType: 'autoUpdate',
        manifest: {
          name: 'DayMan — Sun & Moon',
          short_name: 'DayMan',
          description: 'A private, location-aware 24-hour view of the sun and moon.',
          id: base,
          lang: 'en-US',
          dir: 'ltr',
          theme_color: '#101a2d',
          background_color: '#0c1424',
          display: 'standalone',
          orientation: 'any',
          start_url: base,
          scope: base,
          categories: ['utilities', 'weather'],
          prefer_related_applications: false,
          icons: [
            {
              src: 'favicon.svg',
              sizes: 'any',
              type: 'image/svg+xml',
              purpose: 'any'
            },
            {
              src: 'pwa-192.png',
              sizes: '192x192',
              type: 'image/png',
              purpose: 'any'
            },
            {
              src: 'pwa-512.png',
              sizes: '512x512',
              type: 'image/png',
              purpose: 'any'
            },
            {
              src: 'pwa-maskable-512.png',
              sizes: '512x512',
              type: 'image/png',
              purpose: 'maskable'
            }
          ]
        },
        workbox: {
          globPatterns: ['**/*.{js,css,html,svg,png,webp,json}'],
          globIgnores: ['favicon.svg', 'pwa-192.png', 'pwa-512.png', 'pwa-maskable-512.png'],
          maximumFileSizeToCacheInBytes: 4 * 1024 * 1024,
          cleanupOutdatedCaches: true,
          runtimeCaching: [
            {
              urlPattern: /^https:\/\/tile\.openstreetmap\.org\/.*/i,
              handler: 'CacheFirst',
              options: {
                cacheName: 'dayman-map-tiles',
                expiration: {
                  maxEntries: 250,
                  maxAgeSeconds: 7 * 24 * 60 * 60
                },
                cacheableResponse: {
                  statuses: [0, 200]
                }
              }
            }
          ]
        }
      })
    ],
    test: {
      environment: 'node',
      restoreMocks: true,
      clearMocks: true,
      exclude: [...configDefaults.exclude, 'platform/**']
    }
  };
});
