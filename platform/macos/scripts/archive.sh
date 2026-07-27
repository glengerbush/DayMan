#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACOS_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${MACOS_ROOT}/build"
ARCHIVE_PATH="${BUILD_ROOT}/DayMan.xcarchive"
EXPORT_PATH="${BUILD_ROOT}/export"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: macOS and Xcode are required to archive DayMan" >&2
  exit 1
fi

if [[ -z "${DAYMAN_DEVELOPMENT_TEAM:-}" ]]; then
  echo "error: set DAYMAN_DEVELOPMENT_TEAM to your Apple Developer Team ID" >&2
  exit 1
fi

"${SCRIPT_DIR}/bootstrap-xcode.sh"

xcodebuild archive \
  -project "${MACOS_ROOT}/DayMan.xcodeproj" \
  -scheme DayMan \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  DAYMAN_DEVELOPMENT_TEAM="${DAYMAN_DEVELOPMENT_TEAM}"

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${MACOS_ROOT}/Configuration/ExportOptions-DeveloperID.plist"

codesign --verify --deep --strict --verbose=2 "${EXPORT_PATH}/DayMan.app"

echo "Exported DayMan.app to ${EXPORT_PATH}"
