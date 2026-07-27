#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACOS_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPOSITORY_ROOT="${1:-$(cd -- "${MACOS_ROOT}/../.." && pwd)}"
WEB_DESTINATION="${MACOS_ROOT}/Resources/Web"

if [[ ! -f "${REPOSITORY_ROOT}/package.json" ]]; then
  echo "error: expected DayMan package.json at ${REPOSITORY_ROOT}" >&2
  exit 1
fi

mkdir -p "${WEB_DESTINATION}"

(
  cd "${REPOSITORY_ROOT}"
  npm run build:native
)

rsync -a --delete --exclude '.gitkeep' \
  "${REPOSITORY_ROOT}/dist/" \
  "${WEB_DESTINATION}/"

# Vite rewrites imported assets for the relative base. The moon texture is the
# sole public-resource reference that remains intentionally root-relative, so
# make that known reference bundle-relative for the native host.
find "${WEB_DESTINATION}/assets" -type f -name '*.js' -exec \
  perl -pi -e \
    's{\Q/moon-nearside.webp\E}{./moon-nearside.webp}g' \
    {} +

# A file-URL WKWebView cannot register a service worker. The native bundle is
# already offline by construction; omit the registration tag and manifest link
# instead of producing a harmless but noisy security error on every launch.
perl -pi -e \
  's{<link rel="manifest"[^>]*><script id="vite-plugin-pwa:register-sw"[^>]*></script>}{}g' \
  "${WEB_DESTINATION}/index.html"

if [[ ! -f "${WEB_DESTINATION}/index.html" ]]; then
  echo "error: Vite did not create ${WEB_DESTINATION}/index.html" >&2
  exit 1
fi

echo "Bundled web assets are ready at ${WEB_DESTINATION}"
