#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACOS_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPOSITORY_ROOT="$(cd -- "${MACOS_ROOT}/../.." && pwd)"
FIXTURE_ROOT="${REPOSITORY_ROOT}/fixtures/clock-snapshots"

bash -n "${SCRIPT_DIR}"/*.sh

if command -v xmllint >/dev/null 2>&1; then
  while IFS= read -r -d '' plist; do
    xmllint --noout "${plist}"
  done < <(find "${MACOS_ROOT}/Configuration" -name '*.plist' -print0)
fi

fixture_count=0
while IFS= read -r -d '' fixture; do
  jq -e '
    .schemaVersion == 1
    and (.calculatedAt | type == "string")
    and (.expiresAt | type == "string")
    and (.timezone | type == "string")
    and (.location.latitude | type == "number")
    and (.geometry.viewBox > 0)
    and (.arcs | type == "array")
    and (.events | type == "array")
    and (.accessibilityText | length > 0)
    and ([.arcs[].ranges[] | .startMinute <= .endMinute] | all)
  ' "${fixture}" >/dev/null
  fixture_count=$((fixture_count + 1))
done < <(find "${FIXTURE_ROOT}" -maxdepth 1 -name '*.json' -print0)

if (( fixture_count < 7 )); then
  echo "error: expected at least seven shared ClockSnapshot fixtures" >&2
  exit 1
fi

if command -v ruby >/dev/null 2>&1; then
  ruby -e \
    'require "yaml"; YAML.load_file(ARGV.fetch(0), aliases: true)' \
    "${MACOS_ROOT}/project.yml"
fi

if [[ -f "${MACOS_ROOT}/Resources/Web/index.html" ]]; then
  if grep -Eq 'vite-plugin-pwa:register-sw|rel="manifest"' \
    "${MACOS_ROOT}/Resources/Web/index.html"; then
    echo "error: native index still contains PWA-only registration" >&2
    exit 1
  fi

  if grep -RPq \
    '(?<![.])/(moon-nearside\.webp|data/zcta-2025\.json)' \
    "${MACOS_ROOT}/Resources/Web/assets"; then
    echo "error: native JavaScript contains a root-relative bundled asset" >&2
    exit 1
  fi
fi

grep -Fq 'daymanState' "${REPOSITORY_ROOT}/src/lib/platform-bridge.ts"
grep -Fq 'snapshots: ClockSnapshot[]' "${REPOSITORY_ROOT}/src/lib/platform-bridge.ts"
grep -Fq 'daymanState' "${MACOS_ROOT}/DayManApp/NativeBridge.swift"
grep -Fq 'let snapshots: [ClockSnapshot]' "${MACOS_ROOT}/Shared/ClockModels.swift"

echo "macOS static validation passed (${fixture_count} shared fixtures)."
