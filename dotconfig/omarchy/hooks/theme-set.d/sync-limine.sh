#!/bin/bash
# Omarchy theme-set hook: synchronize theme colors to Limine bootloader

SCRIPT_PATH="$HOME/.config/omarchy/scripts/sync-limine.py"
COLORS_PATH="$HOME/.local/state/omarchy/current/theme/colors.toml"

if [[ ! -f "$SCRIPT_PATH" || ! -f "$COLORS_PATH" ]]; then
  exit 0
fi

# Try passwordless sudo first, otherwise fallback to pkexec
if sudo -n true 2>/dev/null; then
  sudo python3 "$SCRIPT_PATH" "$COLORS_PATH" >/tmp/sync-limine.log 2>&1 &
else
  pkexec python3 "$SCRIPT_PATH" "$COLORS_PATH" >/tmp/sync-limine.log 2>&1 &
fi
