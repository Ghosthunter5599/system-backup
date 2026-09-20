#!/usr/bin/env bash
set -euo pipefail

purge=0
if [[ ${1:-} == "--purge" ]]; then
  purge=1
  shift
fi
if (( $# > 0 )); then
  echo "Usage: scripts/remove-runtime.sh [--purge]" >&2
  exit 2
fi

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
backend_unit_file="$config_root/systemd/user/omarchy-spotify.service"
fallback_unit_file="$config_root/systemd/user/omarchy-spotifyd.service"
config_dir="$config_root/omarchy-spotify"
cache_dir="$cache_root/spotifyd"
runtime_dir=${OMARCHY_SPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omarchy-spotify"}
backend_binary="$runtime_dir/omarchy-spotify-backend"

systemctl --user stop omarchy-spotify.service 2>/dev/null || true
systemctl --user stop omarchy-spotifyd.service 2>/dev/null || true
rm -f -- "$backend_unit_file" "$fallback_unit_file" "$backend_binary"
systemctl --user daemon-reload

if [[ -d $config_dir ]]; then
  if (( purge )); then
    [[ $config_dir == "$config_root/omarchy-spotify" ]] || exit 3
    rm -rf -- "$config_dir"
    echo "Removed spotifyd configuration."
  else
    backup="${config_dir}.bak.$(date -u +%Y%m%d%H%M%S)"
    mv -- "$config_dir" "$backup"
    echo "Moved configuration to: $backup"
  fi
fi

if (( purge )); then
  if [[ -d $cache_dir ]]; then
    [[ $cache_dir == "$cache_root/spotifyd" ]] || exit 3
    rm -rf -- "$cache_dir"
    echo "Removed spotifyd cached credentials and audio."
  fi
  if command -v secret-tool >/dev/null 2>&1; then
    for _ in {1..20}; do
      secret-tool clear service quickshell-spotify kind refresh-token >/dev/null 2>&1 || break
    done
    echo "Cleared matching Omarchy Spotify keyring entries."
  fi
fi

echo "Runtime integration removed. The spotifyd package was left installed."
