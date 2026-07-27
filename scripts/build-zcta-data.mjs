import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const [, , inputPath, outputPath = 'public/data/zcta-2025.json'] = process.argv;

if (!inputPath) {
  throw new Error('Usage: node scripts/build-zcta-data.mjs <gazetteer.txt> [output.json]');
}

const source = await readFile(resolve(inputPath), 'utf8');
const rows = source.trim().split(/\r?\n/).slice(1);
const lookup = Object.fromEntries(
  rows.map((row) => {
    const [zip, , , , , , latitude, longitude] = row.split('|');
    return [zip, [Number(latitude), Number(longitude)]];
  })
);

const destination = resolve(outputPath);
await mkdir(dirname(destination), { recursive: true });
await writeFile(destination, JSON.stringify(lookup));

console.log(`Wrote ${Object.keys(lookup).length.toLocaleString()} ZCTAs to ${destination}`);
