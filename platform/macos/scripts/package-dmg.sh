#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACOS_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
APP_PATH="${1:-${MACOS_ROOT}/build/export/DayMan.app}"
DMG_PATH="${2:-${MACOS_ROOT}/build/DayMan.dmg}"
DMG_ROOT="${MACOS_ROOT}/build/dmg-root"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: macOS is required to package a DMG" >&2
  exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app not found at ${APP_PATH}; run scripts/archive.sh first" >&2
  exit 1
fi

if [[ -e "${DMG_ROOT}" ]]; then
  rm -rf -- "${DMG_ROOT}"
fi
mkdir -p "${DMG_ROOT}" "$(dirname -- "${DMG_PATH}")"
ditto "${APP_PATH}" "${DMG_ROOT}/DayMan.app"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
  -volname DayMan \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"
echo "DMG and checksum are ready at ${DMG_PATH}"
