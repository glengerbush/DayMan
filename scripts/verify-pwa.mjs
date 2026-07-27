import { access, readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const dist = resolve(root, 'dist');

function normalizeBasePath(value) {
  const path = value?.trim();
  if (!path || path === '/') return '/';
  return `/${path.replace(/^\/+|\/+$/g, '')}/`;
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function pngSize(path) {
  const bytes = await readFile(path);
  assert(
    bytes.subarray(1, 4).toString('ascii') === 'PNG',
    `${path} is not a PNG`
  );
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20)
  };
}

const expectedBase = normalizeBasePath(process.env.VITE_BASE_PATH);
const manifest = JSON.parse(
  await readFile(resolve(dist, 'manifest.webmanifest'), 'utf8')
);
const serviceWorker = await readFile(resolve(dist, 'sw.js'), 'utf8');
const index = await readFile(resolve(dist, 'index.html'), 'utf8');
const generatedJavaScript = (
  await Promise.all(
    (await readdir(resolve(dist, 'assets')))
      .filter((name) => name.endsWith('.js'))
      .map((name) => readFile(resolve(dist, 'assets', name), 'utf8'))
  )
).join('\n');

assert(manifest.name === 'DayMan — Sun & Moon', 'Unexpected manifest name');
assert(manifest.short_name === 'DayMan', 'Unexpected manifest short name');
assert(manifest.id === expectedBase, 'Manifest id does not match Vite base');
assert(
  manifest.start_url === expectedBase,
  'Manifest start_url does not match Vite base'
);
assert(
  manifest.scope === expectedBase,
  'Manifest scope does not match Vite base'
);
assert(manifest.display === 'standalone', 'PWA must use standalone display');
assert(
  manifest.theme_color === '#101a2d' &&
    manifest.background_color === '#0c1424',
  'Manifest launch colors changed unexpectedly'
);

const expectedIcons = [
  ['favicon.svg', 'any', 'any'],
  ['pwa-192.png', '192x192', 'any'],
  ['pwa-512.png', '512x512', 'any'],
  ['pwa-maskable-512.png', '512x512', 'maskable']
];
for (const [src, sizes, purpose] of expectedIcons) {
  const icon = manifest.icons.find((candidate) => candidate.src === src);
  assert(icon, `Manifest icon is missing: ${src}`);
  assert(icon.sizes === sizes, `Unexpected sizes for ${src}`);
  assert(icon.purpose === purpose, `Unexpected purpose for ${src}`);
  await access(resolve(dist, src));
}

assert(
  JSON.stringify(await pngSize(resolve(dist, 'pwa-192.png'))) ===
    JSON.stringify({ width: 192, height: 192 }),
  '192 px icon dimensions are invalid'
);
assert(
  JSON.stringify(await pngSize(resolve(dist, 'pwa-512.png'))) ===
    JSON.stringify({ width: 512, height: 512 }),
  '512 px icon dimensions are invalid'
);
assert(
  JSON.stringify(await pngSize(resolve(dist, 'pwa-maskable-512.png'))) ===
    JSON.stringify({ width: 512, height: 512 }),
  'Maskable icon dimensions are invalid'
);

for (const asset of [
  'favicon.svg',
  'pwa-192.png',
  'pwa-512.png',
  'pwa-maskable-512.png',
  'moon-nearside.webp',
  'zcta-2025.json'
]) {
  assert(serviceWorker.includes(asset), `Service worker does not precache ${asset}`);
}

assert(
  index.includes(`${expectedBase}manifest.webmanifest`),
  'HTML manifest link does not use the deployment base'
);
assert(
  index.includes(`${expectedBase}registerSW.js`),
  'HTML service-worker registration does not use the deployment base'
);
assert(
  generatedJavaScript.includes(`${expectedBase}moon-nearside.webp`),
  'Moon texture URL does not use the deployment base'
);
await access(resolve(dist, '.nojekyll'));

console.log(`PWA release verified for base ${expectedBase}`);
