#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

cd "${repo_root}"

# The macOS sync creates a fresh relative-base native bundle. Android consumes
# the same build, so the platform checks never validate stale generated assets.
platform/macos/scripts/sync-web-assets.sh "${repo_root}"
node platform/android/scripts/sync-web.mjs

node platform/android/scripts/validate.mjs
platform/macos/scripts/validate-linux.sh
platform/linux/scripts/validate.sh
cargo test \
  --locked \
  --manifest-path platform/linux/src-tauri/Cargo.toml

echo "All host-available platform checks passed."
