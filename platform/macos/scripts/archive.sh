#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACOS_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${MACOS_ROOT}/build"
EXPORT_PATH="${BUILD_ROOT}/export"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
VERSION_NAME="${DAYMAN_VERSION_NAME:-}"
BUILD_NUMBER="${DAYMAN_BUILD_NUMBER:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: macOS and Xcode are required to build DayMan" >&2
  exit 1
fi

"${SCRIPT_DIR}/bootstrap-xcode.sh"

BUILD_SETTINGS=(
  "CODE_SIGNING_ALLOWED=NO"
)

if [[ -n "${VERSION_NAME}" ]]; then
  BUILD_SETTINGS+=("MARKETING_VERSION=${VERSION_NAME}")
fi

if [[ -n "${BUILD_NUMBER}" ]]; then
  BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=${BUILD_NUMBER}")
fi

xcodebuild clean build \
  -project "${MACOS_ROOT}/DayMan.xcodeproj" \
  -scheme DayMan \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  "${BUILD_SETTINGS[@]}"

PRODUCT_APP="${DERIVED_DATA_PATH}/Build/Products/Release/DayMan.app"
EXPORTED_APP="${EXPORT_PATH}/DayMan.app"
WIDGET_APP="${EXPORTED_APP}/Contents/PlugIns/DayManWidget.appex"
APP_ENTITLEMENTS="${BUILD_ROOT}/DayMan.adhoc.entitlements"
WIDGET_ENTITLEMENTS="${BUILD_ROOT}/DayManWidget.adhoc.entitlements"

if [[ ! -d "${PRODUCT_APP}" ]]; then
  echo "error: built app not found at ${PRODUCT_APP}" >&2
  exit 1
fi

mkdir -p "${EXPORT_PATH}"
if [[ -e "${EXPORTED_APP}" ]]; then
  rm -rf -- "${EXPORTED_APP}"
fi
ditto "${PRODUCT_APP}" "${EXPORTED_APP}"

cp "${MACOS_ROOT}/Configuration/DayMan.entitlements" "${APP_ENTITLEMENTS}"
cp "${MACOS_ROOT}/Configuration/DayManWidget.entitlements" "${WIDGET_ENTITLEMENTS}"
/usr/libexec/PlistBuddy \
  -c "Delete :com.apple.security.application-groups" \
  "${APP_ENTITLEMENTS}" 2>/dev/null || true
/usr/libexec/PlistBuddy \
  -c "Delete :com.apple.security.application-groups" \
  "${WIDGET_ENTITLEMENTS}" 2>/dev/null || true

codesign \
  --force \
  --sign - \
  --entitlements "${WIDGET_ENTITLEMENTS}" \
  "${WIDGET_APP}"
codesign \
  --force \
  --sign - \
  --entitlements "${APP_ENTITLEMENTS}" \
  "${EXPORTED_APP}"
codesign --verify --deep --strict --verbose=2 "${EXPORTED_APP}"

echo "Exported ad-hoc-signed DayMan.app to ${EXPORT_PATH}"
