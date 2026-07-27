#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
linux_dir=$(cd -- "$script_dir/.." && pwd)
repo_root=$(cd -- "$linux_dir/../.." && pwd)
profile=${1:-release}

case "$profile" in
  release)
    cargo_args=(--release --locked)
    ;;
  debug)
    cargo_args=(--locked)
    ;;
  *)
    echo "Usage: $0 [release|debug]" >&2
    exit 2
    ;;
esac

cd "$repo_root"
npm run build:native
cargo build \
  --manifest-path "$linux_dir/src-tauri/Cargo.toml" \
  "${cargo_args[@]}"

echo "Built DayMan web assets and the Linux $profile binary."
