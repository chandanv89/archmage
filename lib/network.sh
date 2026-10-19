#!/usr/bin/env bash

network_list_interfaces() {
  ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' || true
}

network_ensure_up() {
  local iface="$1"
  if ip link show "$iface" | grep -q 'state DOWN'; then
    run_cmd ip link set "$iface" up
  fi
}

network_wifi_connect() {
  local iface="$1"
  prereqs_ensure iwctl iwd 0
  ui_msg "Wi-Fi setup uses iwctl. Ensure rfkill is unblocked."
  if command -v rfkill >/dev/null 2>&1; then
    rfkill list || true
  fi

  ui_msg "Scanning networks on $iface ..."
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] iwctl station $iface scan"
    return 0
  fi

  iwctl station "$iface" scan
  sleep 2
  ui_msg "Available networks:"
  iwctl station "$iface" get-networks || true

  local ssid
  ssid="$(ui_input "SSID")"
  local psk
  psk="$(ui_password "Wi-Fi passphrase")"
  iwctl --passphrase "$psk" station "$iface" connect "$ssid"
  state_set wifi_ssid "$ssid"
}

network_verify_connectivity() {
  require_cmd ping
  if run_cmd ping -c 3 -W 5 ping.archlinux.org; then
    state_set network_ok "1"
    return 0
  fi
  die "Network check failed (ping ping.archlinux.org)."
}

step_network_can_skip() {
  state_step_done network && [[ "$(state_get network_ok)" == "1" ]]
}

step_network_run() {
  ui_msg "Network interfaces:"
  network_list_interfaces | sed 's/^/  /'

  local choice
  choice="$(ui_menu "How will you connect?" \
    "Ethernet (DHCP)" \
    "Wi-Fi (iwctl)" \
    "Already connected - verify only")"

  case "$choice" in
    "Ethernet"*)
      local iface
      iface="$(config_or_prompt net_iface "Ethernet interface" "eth0")"
      network_ensure_up "$iface"
      ;;
    "Wi-Fi"*)
      local wifi_iface
      wifi_iface="$(config_or_prompt wifi_iface "Wireless interface" "wlan0")"
      network_ensure_up "$wifi_iface"
      network_wifi_connect "$wifi_iface"
      ;;
    *)
      ;;
  esac

  network_verify_connectivity
  ui_msg "Network connectivity verified."
}

step_clock_can_skip() {
  state_step_done clock
}

step_clock_run() {
  if command -v timedatectl >/dev/null 2>&1; then
    run_cmd timedatectl set-ntp true || true
    timedatectl status || true
  fi
  state_set clock_synced "1"
}
