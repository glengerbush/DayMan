import { cp, mkdir, rm, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const repositoryRoot = dirname(dirname(packageRoot));
const dist = join(repositoryRoot, "dist");
const destination = join(packageRoot, "www");

try {
  const info = await stat(join(dist, "index.html"));
  if (!info.isFile()) throw new Error("dist/index.html is not a file");
} catch {
  throw new Error(
    `No native web build was found at ${dist}. Run "npm run build:native" from ${repositoryRoot} first.`,
  );
}

await rm(destination, { recursive: true, force: true });
await mkdir(destination, { recursive: true });
await cp(dist, destination, { recursive: true });
await writeFile(join(destination, ".gitkeep"), "");
console.log(`Copied ${dist} to ${destination}`);
