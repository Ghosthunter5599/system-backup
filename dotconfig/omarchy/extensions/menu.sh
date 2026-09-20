#!/bin/bash

# Omarchy Power & CPU Scheduler Menu Extension

show_setup_power_menu() {
  local choice
  choice=$(menu "Power & CPU Setup" "󱐋  Power Profile\n⚡  CPU Scheduler (scx)")

  case "$choice" in
  *"Power Profile"*)
    local profile
    profile=$(menu "Power Profile" "$(omarchy-powerprofiles-list)" "" "$(powerprofilesctl get)")
    if [[ -n $profile && $profile != "CNCLD" ]]; then
      powerprofilesctl set "$profile"
    else
      back_to show_setup_power_menu
    fi
    ;;
  *"CPU Scheduler"*)
    show_cpu_scheduler_menu
    ;;
  *)
    back_to show_setup_menu
    ;;
  esac
}

show_cpu_scheduler_menu() {
  local current_sched="BORE (Kernel Default)"
  if [[ -f /sys/kernel/sched_ext/state ]]; then
    local state
    state=$(cat /sys/kernel/sched_ext/state 2>/dev/null)
    if [[ $state != "disabled" && -n $state ]]; then
      current_sched="$state"
    fi
  fi

  local sched_options="󰓅  scx_bpfland (Gaming & Daily)\n󰓅  scx_lavd (Low Latency / Laptop)\n󰓅  scx_rusty (Multi-core Workloads)\n󰜉  BORE / Kernel Default (Disable scx)\n󰍲  Open CachyOS SCX GUI Manager"
  local selected
  selected=$(menu "CPU Scheduler" "$sched_options" "" "$current_sched")

  case "$selected" in
  *bpfland*)
    pkexec pkill -9 -f 'scx_' 2>/dev/null || true
    pkexec /usr/bin/scx_bpfland >/dev/null 2>&1 &
    notify-send -u normal "⚡ CPU Scheduler" "Switched to scx_bpfland (Gaming & Daily)" -i cpu
    ;;
  *lavd*)
    pkexec pkill -9 -f 'scx_' 2>/dev/null || true
    pkexec /usr/bin/scx_lavd >/dev/null 2>&1 &
    notify-send -u normal "⚡ CPU Scheduler" "Switched to scx_lavd (Low Latency)" -i cpu
    ;;
  *rusty*)
    pkexec pkill -9 -f 'scx_' 2>/dev/null || true
    pkexec /usr/bin/scx_rusty >/dev/null 2>&1 &
    notify-send -u normal "⚡ CPU Scheduler" "Switched to scx_rusty (Multi-core)" -i cpu
    ;;
  *Disable* | *BORE*)
    pkexec pkill -9 -f 'scx_' 2>/dev/null || true
    notify-send -u normal "⚡ CPU Scheduler" "Reverted to BORE (Kernel Default)" -i cpu
    ;;
  *GUI*)
    scx-manager &
    ;;
  *)
    back_to show_setup_power_menu
    ;;
  esac
}
