#!/usr/bin/env bash

disk_list_candidates() {
  lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -vE 'loop|ram' || true
}

disk_partition_path() {
  local disk="$1"
  local part_num="$2"
  if [[ "$disk" =~ [0-9]$ ]]; then
    echo "${disk}p${part_num}"
  else
    echo "${disk}${part_num}"
  fi
}

disk_pick_device() {
  local existing
  existing="$(state_get disk)"
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return 0
  fi

  ui_msg "Available disks:"
  disk_list_candidates | sed 's/^/  /'

  local disk
  disk="$(config_or_prompt disk "Target disk (e.g. /dev/vda)" "")"
  [[ -n "$disk" ]] || die "Disk is required."
  [[ -b "$disk" ]] || die "Not a block device: $disk"
  device_is_safe_target "$disk" || die "Disk $disk is mounted or not a safe target."

  state_set disk "$disk"
  echo "$disk"
}

disk_root_fs_type() {
  local fs
  fs="$(state_get root_fs)"
  if [[ -n "$fs" ]]; then
    echo "$fs"
    return 0
  fi
  fs="$(ui_menu "Root filesystem type" "ext4" "btrfs")"
  state_set root_fs "$fs"
  echo "$fs"
}

disk_want_swap() {
  local swap
  swap="$(state_get use_swap)"
  if [[ "$swap" == "1" ]]; then
    return 0
  fi
  if [[ "$swap" == "0" ]]; then
    return 1
  fi
  if ui_yesno "Create a swap partition (4 GiB)?" 1; then
    state_set use_swap "1"
    return 0
  fi
  state_set use_swap "0"
  return 1
}

disk_partition_uefi_gpt() {
  local disk="$1"
  local want_swap="$2"
  local script
  if [[ "$want_swap" == "1" ]]; then
    script="$(cat <<EOF
label: gpt
, size=1G, type=uefi
, size=4G, type=swap
, type=linux
EOF
)"
  else
    script="$(cat <<EOF
label: gpt
, size=1G, type=uefi
, type=linux
EOF
)"
  fi
  log_info "Partitioning $disk (UEFI GPT)"
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] sfdisk $disk << layout"
    printf '%s\n' "$script"
    state_set part_esp "$(disk_partition_path "$disk" 1)"
    if [[ "$want_swap" == "1" ]]; then
      state_set part_swap "$(disk_partition_path "$disk" 2)"
      state_set part_root "$(disk_partition_path "$disk" 3)"
    else
      state_set part_root "$(disk_partition_path "$disk" 2)"
    fi
    return 0
  fi
  confirm_disk_wipe "$disk"
  printf '%s\n' "$script" | sfdisk "$disk"
  partprobe "$disk" 2>/dev/null || true
  sleep 1

  state_set part_esp "$(disk_partition_path "$disk" 1)"
  if [[ "$want_swap" == "1" ]]; then
    state_set part_swap "$(disk_partition_path "$disk" 2)"
    state_set part_root "$(disk_partition_path "$disk" 3)"
  else
    state_set part_root "$(disk_partition_path "$disk" 2)"
  fi
}

disk_partition_bios_mbr() {
  local disk="$1"
  local want_swap="$2"
  local script
  if [[ "$want_swap" == "1" ]]; then
    script="$(cat <<EOF
label: dos
, size=4G, type=swap
, type=linux
EOF
)"
  else
    script="$(cat <<EOF
label: dos
, type=linux
EOF
)"
  fi
  log_info "Partitioning $disk (BIOS MBR)"
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] sfdisk $disk"
    if [[ "$want_swap" == "1" ]]; then
      state_set part_swap "$(disk_partition_path "$disk" 1)"
      state_set part_root "$(disk_partition_path "$disk" 2)"
    else
      state_set part_root "$(disk_partition_path "$disk" 1)"
    fi
    return 0
  fi
  confirm_disk_wipe "$disk"
  printf '%s\n' "$script" | sfdisk "$disk"
  partprobe "$disk" 2>/dev/null || true
  sleep 1

  if [[ "$want_swap" == "1" ]]; then
    state_set part_swap "$(disk_partition_path "$disk" 1)"
    state_set part_root "$(disk_partition_path "$disk" 2)"
  else
    state_set part_root "$(disk_partition_path "$disk" 1)"
  fi
}

disk_format_partitions() {
  local fs root esp swap
  root="$(state_get part_root)"
  esp="$(state_get part_esp)"
  swap="$(state_get part_swap)"
  fs="$(disk_root_fs_type)"

  [[ -n "$root" ]] || die "Root partition not set."

  if [[ -n "$esp" ]]; then
    run_cmd mkfs.fat -F 32 "$esp"
  fi

  case "$fs" in
    ext4) run_cmd mkfs.ext4 -F "$root" ;;
    btrfs) run_cmd mkfs.btrfs -f "$root" ;;
    *) die "Unsupported filesystem: $fs" ;;
  esac

  if [[ -n "$swap" ]]; then
    run_cmd mkswap "$swap"
  fi

  state_set root_fs "$fs"
}

step_disk_can_skip() {
  state_step_done disk && [[ -n "$(state_get part_root)" ]]
}

step_disk_run() {
  if ui_yesno "Open manual fdisk instead of guided partitioning?" 0; then
    local disk
    disk="$(disk_pick_device)"
    ui_msg "Use fdisk on $disk, then return here."
    run_cmd fdisk "$disk" || true
    ui_pause "After partitioning, press Enter..."
    ui_msg "Enter partition paths manually:"
    local mode
    mode="$(state_get boot_mode)"
    if [[ "$mode" == uefi* ]]; then
      state_set part_esp "$(ui_input "EFI partition" "")"
    fi
    state_set part_root "$(ui_input "Root partition" "")"
    if ui_yesno "Swap partition created?" 0; then
      state_set part_swap "$(ui_input "Swap partition" "")"
    fi
    disk_format_partitions
    return 0
  fi

  local disk mode want_swap
  disk="$(disk_pick_device)"
  mode="$(state_get boot_mode)"
  if disk_want_swap; then
    want_swap="1"
  else
    want_swap="0"
  fi

  case "$mode" in
    uefi|uefi32)
      disk_partition_uefi_gpt "$disk" "$want_swap"
      ;;
    bios)
      disk_partition_bios_mbr "$disk" "$want_swap"
      ;;
    *)
      die "Unknown boot mode: $mode"
      ;;
  esac

  disk_format_partitions
  lsblk -f "$disk" || true
}
