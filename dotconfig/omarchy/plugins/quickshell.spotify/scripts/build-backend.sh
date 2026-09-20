#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$source_root/backend/Cargo.toml"
runtime_dir=${OMARCHY_SPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omarchy-spotify"}
destination="$runtime_dir/omarchy-spotify-backend"
architecture=$(uname -m)
prebuilt="$source_root/backend/dist/$architecture/omarchy-spotify-backend"

if [[ -x $prebuilt ]]; then
  install -d -m 700 -- "$runtime_dir"
  install -m 755 -- "$prebuilt" "$destination"
  printf 'Installed bundled playback backend: %s\n' "$destination"
  exit 0
fi

command -v cargo >/dev/null 2>&1 || {
  echo "build-backend.sh: no bundled backend is available and cargo is missing" >&2
  exit 30
}

cargo build --locked --release --manifest-path "$manifest"
install -d -m 700 -- "$runtime_dir"
install -m 755 -- "$source_root/backend/target/release/omarchy-spotify-backend" \
  "$destination"
printf 'Built and installed playback backend: %s\n' "$destination"
