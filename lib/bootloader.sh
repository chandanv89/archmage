#!/usr/bin/env bash

bootloader_root_uuid() {
  local root
  root="$(state_get part_root)"
  blkid -s UUID -o value "$root"
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
  disk="$(state_get disk)"
  mode="$(state_get boot_mode)"
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
