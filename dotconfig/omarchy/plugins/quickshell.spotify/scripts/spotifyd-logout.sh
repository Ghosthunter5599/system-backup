#!/usr/bin/env bash
set -euo pipefail

# Local playback's OAuth credential is separate from the Web API refresh token.
# Remove only that exact file when the user explicitly logs out in the UI.
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
credentials_file="$cache_root/spotifyd/oauth/credentials.json"

[[ $cache_root == /* && $cache_root != / ]] || {
  echo "spotifyd-logout.sh: refusing an unsafe cache path" >&2
  exit 3
}
[[ $credentials_file == "$cache_root/spotifyd/oauth/credentials.json" ]] || exit 3

systemctl --user stop omarchy-spotify.service 2>/dev/null || true
systemctl --user stop omarchy-spotifyd.service 2>/dev/null || true
rm -f -- "$credentials_file"
