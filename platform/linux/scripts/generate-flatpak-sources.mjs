#!/usr/bin/env node

import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = resolve(fileURLToPath(new URL('.', import.meta.url)));
const linuxDirectory = resolve(scriptDirectory, '..');
const lockfile = resolve(linuxDirectory, 'src-tauri/Cargo.lock');
const output = resolve(
  linuxDirectory,
  'packaging/flatpak/cargo-sources.json'
);
const registry = 'registry+https://github.com/rust-lang/crates.io-index';

function stringField(block, key) {
  return new RegExp(`^${key} = "([^"]+)"$`, 'm').exec(block)?.[1];
}

const lock = await readFile(lockfile, 'utf8');
const packages = lock
  .split(/\n(?=\[\[package\]\]\n)/)
  .filter(block => stringField(block, 'source') === registry)
  .map(block => ({
    name: stringField(block, 'name'),
    version: stringField(block, 'version'),
    checksum: stringField(block, 'checksum')
  }));

if (packages.some(pkg => !pkg.name || !pkg.version || !pkg.checksum))
  throw new Error('Cargo.lock contains an incomplete crates.io package');

const sources = [{
  type: 'inline',
  contents: [
    '[source.crates-io]',
    'replace-with = "vendored-sources"',
    '',
    '[source.vendored-sources]',
    'directory = "vendor"',
    ''
  ].join('\n'),
  dest: 'cargo',
  'dest-filename': 'config'
}];

for (const {name, version, checksum} of packages) {
  const destination = `cargo/vendor/${name}-${version}`;
  sources.push({
    type: 'archive',
    'archive-type': 'tar-gzip',
    url: `https://static.crates.io/crates/${name}/${name}-${version}.crate`,
    sha256: checksum,
    dest: destination
  });
  sources.push({
    type: 'inline',
    contents: JSON.stringify({package: checksum, files: {}}),
    dest: destination,
    'dest-filename': '.cargo-checksum.json'
  });
}

const rendered = `${JSON.stringify(sources, null, 2)}\n`;
if (process.argv.includes('--check')) {
  const existing = await readFile(output, 'utf8').catch(() => '');
  if (existing !== rendered) {
    console.error(
      'cargo-sources.json is stale; run platform/linux/scripts/generate-flatpak-sources.sh'
    );
    process.exitCode = 1;
  }
} else {
  await writeFile(output, rendered);
  console.log(`Generated ${output} with ${packages.length} locked crates.`);
}
