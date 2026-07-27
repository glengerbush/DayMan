#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACOS_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPOSITORY_ROOT="$(cd -- "${MACOS_ROOT}/../.." && pwd)"

(
  cd "${REPOSITORY_ROOT}"
  npm ci
)

"${SCRIPT_DIR}/sync-web-assets.sh" "${REPOSITORY_ROOT}"
"${SCRIPT_DIR}/generate-app-icons.sh" "${REPOSITORY_ROOT}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: XcodeGen is required (brew install xcodegen)" >&2
  exit 1
fi

(
  cd "${MACOS_ROOT}"
  xcodegen generate
)

echo "Open ${MACOS_ROOT}/DayMan.xcodeproj in Xcode."
