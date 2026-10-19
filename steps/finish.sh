#!/usr/bin/env bash

step_finish_can_skip() {
  false
}

step_finish_run() {
  ui_heading "Installation summary"
  ui_msg "Disk:        $(state_get disk)"
  ui_msg "Root:        $(state_get part_root) ($(state_get root_fs))"
  ui_msg "Boot mode:   $(state_get boot_mode)"
  ui_msg "Bootloader:  $(state_get bootloader_installed)"
  ui_msg "Hostname:    $(state_get hostname)"
  ui_msg "User:        $(state_get username)"
  ui_msg "Desktop:     $(state_get desktop_profile)"
  ui_msg "Log file:    $ARCHMAGE_LOG"
  ui_msg "State:       $ARCHMAGE_STATE_FILE"
  if [[ -f "$ARCHMAGE_STATE_JSON" ]]; then
    ui_msg "State JSON:  $ARCHMAGE_STATE_JSON"
  fi
  state_export_answers "$ARCHMAGE_STATE_DIR/exported-answers.json" || true
  if [[ -f "$ARCHMAGE_STATE_DIR/exported-answers.json" ]]; then
    ui_msg "Answers JSON: $ARCHMAGE_STATE_DIR/exported-answers.json"
  fi
  ui_msg "Profiles:    $ARCHMAGE_ROOT/config/profiles.yaml"
  ui_msg ""
  ui_msg "Archmage installation complete."

  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    ui_msg "Dry-run mode: no changes were applied to disk."
    return 0
  fi

  if ui_yesno "Unmount /mnt before reboot?" 1; then
    umount -R "$ARCHMAGE_MNT" 2>/dev/null || log_warn "Some mounts may still be busy."
  fi

  if ui_yesno "Reboot now?" 0; then
    reboot
  else
    ui_msg "Remember to remove the installation medium, then reboot when ready."
  fi
}
