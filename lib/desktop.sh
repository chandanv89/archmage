#!/usr/bin/env bash

desktop_enable_display_manager() {
  local desktop dm
  desktop="$(state_get desktop_profile)"
  [[ -z "$desktop" || "$desktop" == "none" ]] && return 0

  dm="$(profiles_get_meta "desktop_${desktop}" display_manager)"
  if [[ -z "$dm" ]]; then
    return 0
  fi

  local dm_pkg
  dm_pkg="$(profiles_get_meta "desktop_${desktop}" display_manager_pkg)"
  if [[ -n "$dm_pkg" ]]; then
    arch_chroot_run "pacman -S --noconfirm '$dm_pkg'"
  fi

  arch_chroot_run "systemctl enable ${dm}.service"
  state_set display_manager "$dm"
}

desktop_hyprland_post() {
  local desktop
  desktop="$(state_get desktop_profile)"
  [[ "$desktop" != "hyprland" ]] && return 0
  arch_chroot_run "systemctl enable seatd.service"
}

step_desktop_can_skip() {
  state_step_done desktop
}

step_desktop_run() {
  local desktop
  desktop="$(packages_infer_desktop_profile)"
  if [[ -z "$(state_get desktop_profile)" && "$desktop" != "none" ]]; then
    state_set desktop_profile "$desktop"
  elif [[ -z "$(state_get desktop_profile)" ]]; then
    desktop="$(packages_select_desktop)"
  fi

  if [[ "$desktop" == "none" ]]; then
    ui_msg "No desktop environment selected."
    return 0
  fi

  desktop_enable_display_manager
  desktop_hyprland_post

  local notes
  notes="$(profiles_get_meta "desktop_${desktop}" notes)"
  if [[ -n "$notes" ]]; then
    ui_msg "Note: $notes"
  fi
  ui_msg "Desktop profile '$desktop' configured (packages were installed during pacstrap)."
}
