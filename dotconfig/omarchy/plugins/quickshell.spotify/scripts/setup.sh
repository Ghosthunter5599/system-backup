#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
install_spotifyd=0
force_config=0
skip_backend_build=${OMARCHY_SPOTIFY_SKIP_BACKEND_BUILD:-0}
device_name="Omarchy Spotify"

usage() {
  cat <<'EOF'
Usage: scripts/setup.sh [--install-spotifyd] [--skip-backend-build] [--force-config] [--device-name NAME]

Build and install the plugin-owned playback backend and its static user unit.
spotifyd remains an optional fallback. Neither unit is enabled at login.
EOF
}

while (( $# > 0 )); do
  case $1 in
    --install-spotifyd)
      install_spotifyd=1
      shift
      ;;
    --force-config)
      force_config=1
      shift
      ;;
    --skip-backend-build)
      skip_backend_build=1
      shift
      ;;
    --device-name)
      [[ $# -ge 2 ]] || { echo "setup.sh: --device-name requires a value" >&2; exit 2; }
      device_name=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "setup.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if (( install_spotifyd )) && ! command -v spotifyd >/dev/null 2>&1; then
  command -v pacman >/dev/null 2>&1 || {
    echo "setup.sh: --install-spotifyd is supported only on pacman-based Omarchy systems" >&2
    exit 1
  }
  sudo pacman -S --needed spotifyd
fi

for command_name in secret-tool openssl socat xdg-open systemctl awk install python3 avahi-browse; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "setup.sh: required Omarchy base command is missing: $command_name" >&2
    exit 1
  }
done

"$source_root/scripts/spotify-connect-device.py" self-test >/dev/null || {
  echo "setup.sh: the local Spotify Connect encryption helper failed its self-test" >&2
  exit 1
}

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
config_dir="$config_root/omarchy-spotify"
config_file="$config_dir/spotifyd.conf"
unit_dir="$config_root/systemd/user"
backend_unit_file="$unit_dir/omarchy-spotify.service"
fallback_unit_file="$unit_dir/omarchy-spotifyd.service"

backend_binary=${OMARCHY_SPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omarchy-spotify"}/omarchy-spotify-backend
backend_ready=0
if [[ -x $backend_binary ]]; then
  backend_ready=1
elif (( ! skip_backend_build )); then
  if "$source_root/scripts/build-backend.sh"; then
    backend_ready=1
  else
    echo "Warning: the plugin-owned backend could not be built; checking spotifyd fallback." >&2
  fi
fi

if (( ! backend_ready )) && ! command -v spotifyd >/dev/null 2>&1; then
  echo "setup.sh: neither the plugin backend nor spotifyd is available" >&2
  echo "Install Rust to build the backend, or install spotifyd as a fallback." >&2
  exit 30
fi

install -d -m 700 -- "$config_dir"
install -d -m 700 -- "$unit_dir"

if [[ -f $config_file && $force_config -eq 0 ]]; then
  echo "Keeping existing configuration: $config_file"
else
  if [[ -f $config_file ]]; then
    backup="${config_file}.bak.$(date -u +%Y%m%d%H%M%S)"
    cp -p -- "$config_file" "$backup"
    echo "Backed up previous configuration to: $backup"
  fi
  install -m 600 -- "$source_root/config/spotifyd.conf" "$config_file"
fi

printf '%s\n' "$device_name" | "$source_root/scripts/configure-spotifyd.sh"
if (( backend_ready )); then
  install -m 644 -- "$source_root/systemd/omarchy-spotify.service" "$backend_unit_file"
fi
if command -v spotifyd >/dev/null 2>&1; then
  install -m 644 -- "$source_root/systemd/omarchy-spotifyd.service" "$fallback_unit_file"
fi
systemctl --user daemon-reload

for unit_name in omarchy-spotify.service omarchy-spotifyd.service; do
  unit_state=$(systemctl --user is-enabled "$unit_name" 2>/dev/null || true)
  if [[ $unit_state == "enabled" || $unit_state == "enabled-runtime" ]]; then
    echo "Warning: $unit_name was already enabled at login." >&2
    echo "For on-demand behavior, run: systemctl --user disable $unit_name" >&2
  fi
done

if (( backend_ready )); then
  echo "Installed plugin playback unit: $backend_unit_file"
fi
if [[ -f $fallback_unit_file ]]; then
  echo "Kept spotifyd fallback unit: $fallback_unit_file"
fi
echo "Installed private config: $config_file"
echo "Playback remains stopped and will be started on demand by the plugin."
