#!/usr/bin/env bash
set -euo pipefail

action=${1:-}
if (( $# != 1 )); then
  echo "Usage: scripts/playback-runtime.sh check|start|stop|status|unit" >&2
  exit 2
fi

backend_binary="$HOME/.local/lib/omarchy-spotify/omarchy-spotify-backend"
backend_unit=omarchy-spotify.service
fallback_unit=omarchy-spotifyd.service

unit_exists() {
  systemctl --user cat "$1" >/dev/null 2>&1
}

preferred_unit() {
  if [[ -x $backend_binary ]] && unit_exists "$backend_unit"; then
    printf '%s\n' "$backend_unit"
  elif command -v spotifyd >/dev/null 2>&1 && unit_exists "$fallback_unit"; then
    printf '%s\n' "$fallback_unit"
  else
    return 1
  fi
}

case $action in
  check)
    preferred_unit >/dev/null
    ;;
  start)
    unit=$(preferred_unit) || {
      echo "playback-runtime.sh: no installed playback runtime is available" >&2
      exit 1
    }
    systemctl --user start "$unit"
    ;;
  stop)
    systemctl --user stop "$backend_unit" 2>/dev/null || true
    systemctl --user stop "$fallback_unit" 2>/dev/null || true
    ;;
  status)
    unit=$(preferred_unit) || exit 1
    systemctl --user is-active "$unit"
    ;;
  unit)
    preferred_unit
    ;;
  *)
    echo "playback-runtime.sh: unknown action: $action" >&2
    exit 2
    ;;
esac
