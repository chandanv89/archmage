#!/usr/bin/env bash

step_preflight_can_skip() {
  state_step_done preflight
}

step_preflight_run() {
  require_root

  if ! is_live_environment; then
    log_warn "This does not look like the Arch live ISO (/run/archiso missing)."
    if ! ui_yesno "Continue anyway? (not recommended)" 0; then
      die "Aborted."
    fi
  fi

  local mode
  mode="$(detect_boot_mode)"
  state_set boot_mode "$mode"
  ui_msg "Firmware boot mode: $mode"

  prereqs_check_core

  ui_msg "Archmage $ARCHMAGE_VERSION is ready."
  ui_pause
}
