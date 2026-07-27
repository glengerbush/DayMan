#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACOS_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPOSITORY_ROOT="${1:-$(cd -- "${MACOS_ROOT}/../.." && pwd)}"
SOURCE_SVG="${REPOSITORY_ROOT}/public/favicon.svg"
SOURCE_PNG="${REPOSITORY_ROOT}/public/pwa-512.png"
DESTINATION="${MACOS_ROOT}/Resources/Assets.xcassets/AppIcon.appiconset"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TEMP_DIR}"' EXIT

mkdir -p "${DESTINATION}"

render_source() {
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert --width 1024 --height 1024 "${SOURCE_SVG}" > "${TEMP_DIR}/source.png"
  elif command -v qlmanage >/dev/null 2>&1; then
    qlmanage -t -s 1024 -o "${TEMP_DIR}" "${SOURCE_SVG}" >/dev/null
    mv "${TEMP_DIR}/favicon.svg.png" "${TEMP_DIR}/source.png"
  else
    cp "${SOURCE_PNG}" "${TEMP_DIR}/source.png"
  fi
}

resize() {
  local pixels="$1"
  local output="$2"
  if command -v magick >/dev/null 2>&1; then
    magick "${TEMP_DIR}/source.png" -resize "${pixels}x${pixels}" "${DESTINATION}/${output}"
  elif command -v sips >/dev/null 2>&1; then
    sips -z "${pixels}" "${pixels}" "${TEMP_DIR}/source.png" \
      --out "${DESTINATION}/${output}" >/dev/null
  else
    echo "error: install ImageMagick or run this script on macOS with sips" >&2
    exit 1
  fi
}

render_source
resize 16 icon_16x16.png
resize 32 icon_16x16@2x.png
resize 32 icon_32x32.png
resize 64 icon_32x32@2x.png
resize 128 icon_128x128.png
resize 256 icon_128x128@2x.png
resize 256 icon_256x256.png
resize 512 icon_256x256@2x.png
resize 512 icon_512x512.png
resize 1024 icon_512x512@2x.png

echo "Generated macOS app icons in ${DESTINATION}"
