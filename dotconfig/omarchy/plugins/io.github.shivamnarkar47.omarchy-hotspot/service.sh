#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$HOME/.config/omarchy"
PASS_FILE="$CONFIG_DIR/hotspot-password"
SSID_FILE="$CONFIG_DIR/hotspot-ssid"
COUNTRY="IN"

ensure_config() {
  mkdir -p "$CONFIG_DIR"
  if [[ ! -s "$PASS_FILE" ]]; then
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10 >"$PASS_FILE"
    chmod 600 "$PASS_FILE"
  fi
  if [[ ! -s "$SSID_FILE" ]]; then
    printf 'OmarchyHotspot' >"$SSID_FILE"
  fi
}

get_password() {
  ensure_config
  cat "$PASS_FILE"
}

get_ssid() {
  ensure_config
  if [[ -s "$SSID_FILE" ]]; then
    cat "$SSID_FILE"
  else
    echo "OmarchyHotspot"
  fi
}

uplink_iface() {
  ip route get 8.8.8.8 2>/dev/null | awk '{ for (i=1; i<=NF; i++) if ($i == "dev") print $(i+1); exit }' || echo "wlp8s0"
}

wifi_iface() {
  nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep -E ':wifi$' | head -1 | cut -d: -f1 || echo "wlp8s0"
}

active_wifi_con() {
  local wif; wif="$(wifi_iface)"
  nmcli -t -f DEVICE,NAME connection show --active 2>/dev/null | awk -F: -v dev="$wif" '$1==dev {print $2; exit}' || echo ""
}

wifi_channel() {
  local iface; iface="$(wifi_iface)"
  iw dev "$iface" info 2>/dev/null | awk '/channel/ { print $2; exit }' || echo ""
}

is_dfs_channel() {
  local ch="${1:-}"
  [[ -z "$ch" ]] && return 1
  if (( (ch >= 52 && ch <= 64) || (ch >= 100 && ch <= 144) )); then
    return 0
  fi
  return 1
}

running_ap_iface() {
  if iw dev ap0 info >/dev/null 2>&1; then
    echo "ap0"
    return
  fi
  pkexec /usr/bin/create_ap --list-running 2>/dev/null | awk 'NR>1 { if ($3 ~ /^\(.*\)$/) { gsub(/[()]/, "", $3); print $3; exit } else { print $2; exit } }' || echo ""
}

running_base_iface() {
  pkexec /usr/bin/create_ap --list-running 2>/dev/null | awk 'NR>1 { print $2; exit }' || echo ""
}

status_text() {
  local ap_if; ap_if="$(running_ap_iface)"
  if [[ -z "$ap_if" ]] || ! iw dev "$ap_if" info >/dev/null 2>&1; then
    echo "off"
    return
  fi
  local ch; ch="$(iw dev "$ap_if" info 2>/dev/null | awk '/channel/ { print $2; exit }')"
  local clients; clients="$(pkexec /usr/bin/create_ap --list-clients "$ap_if" 2>/dev/null | awk '/^[0-9a-fA-F:]+/ {count++} END {print count+0}')"
  local up; up="$(uplink_iface)"
  local ssid; ssid="$(get_ssid)"
  echo "on $ssid $up ${ch:-11} ${clients:-0}"
}

stop_hotspot() {
  local run_if; run_if="$(running_base_iface)"
  if [[ -n "$run_if" ]]; then
    pkexec /usr/bin/create_ap --stop "$run_if" 2>/dev/null || true
  fi
  local ap_if; ap_if="$(running_ap_iface)"
  if [[ -n "$ap_if" && "$ap_if" != "$run_if" ]]; then
    pkexec /usr/bin/create_ap --stop "$ap_if" 2>/dev/null || true
  fi
  pkexec /usr/bin/create_ap --stop "$(wifi_iface)" 2>/dev/null || true
  echo "off"
}

start_hotspot() {
  stop_hotspot >/dev/null 2>&1 || true
  ensure_config
  local pw; pw="$(get_password)"
  local ssid; ssid="$(get_ssid)"
  local wif; wif="$(wifi_iface)"
  local up; up="$(uplink_iface)"
  local ch; ch="$(wifi_channel)"

  # If connected on a DFS channel (e.g. Channel 52), switch the station connection to 2.4 GHz
  if [[ "$up" == "$wif" ]] && is_dfs_channel "$ch"; then
    local active_con; active_con="$(active_wifi_con)"
    if [[ -n "$active_con" ]]; then
      nmcli connection modify "$active_con" 802-11-wireless.band bg 2>/dev/null || true
      nmcli connection up "$active_con" >/dev/null 2>&1 || true
      sleep 2
      ch="$(wifi_channel)"
    fi
  fi

  if [[ -z "$ch" ]] || ( [[ "$up" == "$wif" ]] && is_dfs_channel "$ch" ); then
    ch=11
  fi

  local opts=(--daemon --country "$COUNTRY")
  if [[ -n "$ch" && "$up" == "$wif" ]]; then
    opts+=(-c "$ch")
  else
    opts+=(-c 1)
  fi

  if ! pkexec /usr/bin/create_ap "${opts[@]}" "$wif" "$up" "$ssid" "$pw"; then
    echo "ERR: Failed to start hotspot via create_ap" >&2
    exit 1
  fi
  sleep 1.5
  status_text
}

set_password_cmd() {
  local newpass
  IFS= read -r newpass
  if [[ -z "$newpass" ]]; then
    echo "No password provided on stdin" >&2
    return 1
  fi
  local total printable
  total="$(printf '%s' "$newpass" | wc -c)"
  printable="$(printf '%s' "$newpass" | LC_ALL=C tr -cd '[:print:]' | wc -c)"
  if [[ "$total" -ne "$printable" || "$total" -lt 8 || "$total" -gt 63 ]]; then
    echo "Password must be 8-63 printable ASCII characters" >&2
    return 1
  fi
  printf '%s' "$newpass" >"$PASS_FILE"
  chmod 600 "$PASS_FILE"

  local run_if; run_if="$(running_base_iface)"
  if [[ -n "$run_if" ]]; then
    start_hotspot
  fi
  echo "ok"
}

set_ssid_cmd() {
  local newssid="${1:-}"
  if [[ -z "$newssid" ]]; then
    IFS= read -r newssid || true
  fi
  if [[ -z "$newssid" ]]; then
    echo "No SSID provided" >&2
    return 1
  fi
  printf '%s' "$newssid" >"$SSID_FILE"

  local run_if; run_if="$(running_base_iface)"
  if [[ -n "$run_if" ]]; then
    start_hotspot
  fi
  echo "ok"
}

case "${1:-status}" in
  status) status_text ;;
  toggle)
    if [[ "$(running_base_iface)" != "" || "$(running_ap_iface)" != "" ]]; then
      stop_hotspot
    else
      start_hotspot
    fi
    ;;
  start) start_hotspot ;;
  stop) stop_hotspot ;;
  set-password) set_password_cmd ;;
  get-password) get_password ;;
  set-ssid) shift; set_ssid_cmd "${1:-}" ;;
  get-ssid) get_ssid ;;
  *) echo "Usage: $0 {status|toggle|start|stop|set-password|get-password|set-ssid|get-ssid}" >&2; exit 2 ;;
esac
