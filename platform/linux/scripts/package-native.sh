#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_dir=$(cd -- "$script_dir/.." && pwd)
repo_root=$(cd -- "$linux_dir/../.." && pwd)
output_dir=${DAYMAN_RELEASE_DIR:-"$repo_root/release/linux"}
bundles=${1:-deb,rpm,appimage}

if [[ "$bundles" == "--help" || "$bundles" == "-h" ]]; then
  echo "Usage: $0 [deb,rpm,appimage]"
  exit 0
fi

if ! cargo tauri --version >/dev/null 2>&1; then
  echo "cargo-tauri is required. Install it with:" >&2
  echo "  cargo install tauri-cli --version '^2' --locked" >&2
  exit 1
fi

cd "$repo_root"
npm run build:native

cd "$linux_dir"
cargo tauri build --bundles "$bundles"

mkdir -p "$output_dir"
find "$linux_dir/src-tauri/target/release/bundle" -maxdepth 3 -type f \
  \( -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \) \
  -exec cp -v '{}' "$output_dir/" \;

widget_archive="$output_dir/dayman-widgets-0.1.0.tar.gz"
tar -C "$linux_dir" -czf "$widget_archive" \
  plasma gnome scripts/install-widgets.sh scripts/uninstall-widgets.sh \
  schema/clock-snapshot-v1.schema.json schema/platform-state-v1.schema.json

(
  cd "$output_dir"
  find . -maxdepth 1 -type f \
    \( -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' -o -name '*.tar.gz' \) \
    -print0 |
    sort -z |
    xargs -0 -r sha256sum > SHA256SUMS
)

echo "Linux release artifacts are in $output_dir"
