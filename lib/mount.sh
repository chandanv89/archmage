#!/usr/bin/env bash

mount_install_tree() {
  local root esp swap
  root="$(state_get part_root)"
  esp="$(state_get part_esp)"
  swap="$(state_get part_swap)"

  [[ -n "$root" ]] || die "Root partition missing in state."

  run_cmd mount "$root" "$ARCHMAGE_MNT"

  if [[ -n "$esp" ]]; then
    run_cmd mount --mkdir "$esp" "$ARCHMAGE_MNT/boot"
  fi

  if [[ -n "$swap" ]]; then
    run_cmd swapon "$swap"
  fi

  state_set mounted "1"
}

step_mount_can_skip() {
  [[ "$(state_get mounted)" == "1" ]] && mountpoint -q "$ARCHMAGE_MNT"
}

step_mount_run() {
  if mountpoint -q "$ARCHMAGE_MNT" 2>/dev/null; then
    if ! ui_yesno "$ARCHMAGE_MNT is already mounted. Remount?" 0; then
      state_set mounted "1"
      return 0
    fi
    run_cmd umount -R "$ARCHMAGE_MNT" 2>/dev/null || true
  fi
  mount_install_tree
  findmnt "$ARCHMAGE_MNT"
}
