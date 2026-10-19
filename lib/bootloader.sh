#!/usr/bin/env bash

bootloader_root_uuid() {
  local root uuid
  root="$(state_get part_root)"
  uuid="$(blkid -s UUID -o value "$root" 2>/dev/null || true)"
  if [[ -n "$uuid" ]]; then
    echo "$uuid"
    return 0
  fi
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] no UUID on $root; using placeholder for bootloader config"
    echo "00000000-0000-0000-0000-000000000000"
    return 0
  fi
  die "Could not read UUID for root partition: $root"
}

bootloader_install_systemd_boot() {
  local uuid kernel
  uuid="$(bootloader_root_uuid)"
  kernel="$(state_get kernel_pkg)"
  [[ -z "$kernel" ]] && kernel="linux"

  local script
  script="$(cat <<EOS
set -euo pipefail
bootctl install
mkdir -p /boot/loader/entries
ROOT_UUID='${uuid}'
KERNEL='${kernel}'
cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
editor  no
EOF
cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-\${KERNEL}
initrd  /initramfs-\${KERNEL}.img
options root=UUID=\${ROOT_UUID} rw
EOF
EOS
)"
  arch_chroot_run "$script"
}

bootloader_install_grub() {
  local disk mode uuid kernel
  disk_ensure_install_disk_state
  disk="$(state_get disk)"
  mode="$(state_get boot_mode)"
  [[ -n "$disk" ]] || die "GRUB install needs install disk (e.g. /dev/sda) in state."
  uuid="$(bootloader_root_uuid)"
  kernel="$(state_get kernel_pkg)"
  [[ -z "$kernel" ]] && kernel="linux"

  if [[ "$mode" == uefi* ]]; then
    local script
    script="$(cat <<EOS
set -euo pipefail
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOS
)"
    arch_chroot_run "$script"
  else
    local script
    script="$(cat <<EOS
set -euo pipefail
grub-install --target=i386-pc '${disk}'
grub-mkconfig -o /boot/grub/grub.cfg
EOS
)"
    arch_chroot_run "$script"
  fi
}

step_bootloader_can_skip() {
  state_step_done bootloader
}

step_bootloader_run() {
  local bl
  bl="$(packages_select_bootloader)"

  case "$bl" in
    systemd-boot)
      bootloader_install_systemd_boot
      ;;
    grub)
      bootloader_install_grub
      ;;
    *)
      die "Unknown bootloader: $bl"
      ;;
  esac
  state_set bootloader_installed "$bl"
}
