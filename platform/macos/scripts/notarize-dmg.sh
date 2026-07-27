#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACOS_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
APP_PATH="${1:-${MACOS_ROOT}/build/export/DayMan.app}"
DMG_PATH="${2:-${MACOS_ROOT}/build/DayMan.dmg}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: macOS is required for hdiutil, notarytool, and stapler" >&2
  exit 1
fi

if [[ -z "${DAYMAN_NOTARY_PROFILE:-}" ]]; then
  echo "error: set DAYMAN_NOTARY_PROFILE to a notarytool keychain profile" >&2
  exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app not found at ${APP_PATH}; run scripts/archive.sh first" >&2
  exit 1
fi

mkdir -p "$(dirname -- "${DMG_PATH}")"
hdiutil create \
  -volname DayMan \
  -srcfolder "${APP_PATH}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${DAYMAN_NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"

echo "Notarized DMG and checksum are ready at ${DMG_PATH}"
