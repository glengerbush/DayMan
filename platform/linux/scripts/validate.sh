#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_dir=$(cd -- "$script_dir/.." && pwd)
failures=0

check() {
  local label=$1
  shift
  if "$@"; then
    echo "ok - $label"
  else
    echo "not ok - $label" >&2
    failures=$((failures + 1))
  fi
}

check_json() {
  jq empty "$1"
}

check_fixture() {
  jq -e '
    .schemaVersion == 1 and
    (.calculatedAt | type == "string") and
    (.expiresAt | type == "string") and
    (.dateKey | type == "string") and
    (.timezone | type == "string") and
    (.location.latitude >= -90 and .location.latitude <= 90) and
    (.location.longitude >= -180 and .location.longitude <= 180) and
    (.arcs | type == "array") and
    (all(.arcs[];
      (.ranges | type == "array") and
      all(.ranges[];
        (.startMinute >= 0 and .startMinute <= 1440) and
        (.endMinute >= 0 and .endMinute <= 1440)))) and
    (.events | type == "array") and
    (.referenceMinute >= 0 and .referenceMinute <= 1440) and
    (.accessibilityText | length > 0)
  ' "$1" >/dev/null
}

check_state_fixture() {
  jq -e '
    . as $state |
    .schemaVersion == 1 and
    (.updatedAt | type == "string") and
    (.settings.location | type == "object") and
    (.snapshot.schemaVersion == 1) and
    (.snapshots | type == "array") and
    (.snapshots | length > 0) and
    (all(.snapshots[]; .schemaVersion == 1)) and
    (any(.snapshots[]; .dateKey == $state.snapshot.dateKey))
  ' "$1" >/dev/null || return 1
  jq -e '
    def valid_snapshot:
    (.dateKey | type == "string") and
    (.timezone | type == "string") and
    (.arcs | type == "array") and
    (all(.arcs[];
      (.ranges | type == "array") and
      all(.ranges[];
        (.startMinute >= 0 and .startMinute <= 1440) and
        (.endMinute >= 0 and .endMinute <= 1440)))) and
    (.accessibilityText | length > 0);
    (.snapshot | valid_snapshot) and
    (all(.snapshots[]; valid_snapshot))
  ' "$1" >/dev/null
}

check_qml() {
  qmlformat -n "$1" >/dev/null
}

check_cargo_metadata() {
  cargo metadata \
    --manifest-path "$linux_dir/src-tauri/Cargo.toml" --locked --no-deps \
    --format-version 1 >/dev/null
}

check_yaml() {
  "$python_command" -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$1"
}

check_appstream() {
  appstreamcli validate --no-net "$1" >/dev/null
}

check_plasma_package() {
  kpackagetool6 --type Plasma/Applet --appstream-metainfo "$1" >/dev/null
}

check_widget_selection() {
  node --test "$1" >/dev/null
}

check_tauri_files() {
  local config="$linux_dir/src-tauri/tauri.conf.json"
  local sources
  sources=$(jq -r '
    .bundle.linux |
    [.deb.files, .rpm.files, .appimage.files] |
    map(to_entries[]) | .[].value
  ' "$config") || return 1
  while IFS= read -r relative; do
    [[ -e "$linux_dir/src-tauri/$relative" ]] || {
      echo "Missing Tauri bundle source: $relative" >&2
      return 1
    }
  done <<< "$sources"
}

check_flatpak_sources() {
  node "$linux_dir/scripts/generate-flatpak-sources.mjs" --check
}

for json in \
  "$linux_dir/src-tauri/tauri.conf.json" \
  "$linux_dir/src-tauri/capabilities/default.json" \
  "$linux_dir/packaging/flatpak/cargo-sources.json" \
  "$linux_dir/schema/clock-snapshot-v1.schema.json" \
  "$linux_dir/schema/platform-state-v1.schema.json" \
  "$linux_dir/fixtures/dayman-state-v1.json" \
  "$linux_dir/plasma/org.dayman.DayMan/metadata.json" \
  "$linux_dir/gnome/dayman@dayman.app/metadata.json"; do
  check "valid JSON: ${json#"$linux_dir/"}" check_json "$json"
done

check "Linux platform-state v1 fixture invariants" \
  check_state_fixture "$linux_dir/fixtures/dayman-state-v1.json"
for fixture in "$linux_dir"/../../fixtures/clock-snapshots/*.json; do
  check "shared ClockSnapshot: ${fixture##*/}" check_fixture "$fixture"
done
if [[ -x /usr/bin/python3 ]]; then
  python_command=/usr/bin/python3
else
  python_command=python3
fi

check "Tauri package source paths" check_tauri_files
check "Flatpak Cargo sources match Cargo.lock" check_flatpak_sources
if "$python_command" -c 'import yaml' >/dev/null 2>&1; then
  check "Flatpak YAML syntax" check_yaml \
    "$linux_dir/packaging/flatpak/com.dayman.DayMan.yml"
else
  echo "skip - Flatpak YAML syntax (PyYAML not installed)"
fi

for script in "$linux_dir"/scripts/*.sh; do
  check "shell syntax: ${script#"$linux_dir/"}" bash -n "$script"
done
check "PKGBUILD shell syntax" bash -n "$linux_dir/packaging/aur/PKGBUILD"
check "GNOME extension JavaScript syntax" \
  node --check "$linux_dir/gnome/dayman@dayman.app/extension.js"
check "widget snapshot-selection behavior" \
  check_widget_selection "$linux_dir/tests/snapshot-selection.test.mjs"

if command -v qmlformat >/dev/null 2>&1; then
  check "Plasma QML parse" check_qml \
    "$linux_dir/plasma/org.dayman.DayMan/contents/ui/main.qml"
else
  echo "skip - Plasma QML parse (qmlformat not installed)"
fi

if command -v xmllint >/dev/null 2>&1; then
  check "AppStream XML well-formed" xmllint --noout \
    "$linux_dir/packaging/shared/com.dayman.DayMan.metainfo.xml"
else
  echo "skip - AppStream XML (xmllint not installed)"
fi

if command -v appstreamcli >/dev/null 2>&1; then
  check "AppStream metadata" check_appstream \
    "$linux_dir/packaging/shared/com.dayman.DayMan.metainfo.xml"
else
  echo "skip - AppStream metadata (appstreamcli not installed)"
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
  check "desktop entry" desktop-file-validate \
    "$linux_dir/packaging/shared/com.dayman.DayMan.desktop"
else
  echo "skip - desktop entry (desktop-file-validate not installed)"
fi

if command -v kpackagetool6 >/dev/null 2>&1; then
  check "Plasma package metadata" check_plasma_package \
    "$linux_dir/plasma/org.dayman.DayMan"
else
  echo "skip - Plasma package metadata (kpackagetool6 not installed)"
fi

check "Rust formatting" cargo fmt \
  --manifest-path "$linux_dir/src-tauri/Cargo.toml" --check
check "locked Cargo metadata" check_cargo_metadata

if ((failures)); then
  echo "$failures validation check(s) failed." >&2
  exit 1
fi

echo "All available Linux validations passed."
