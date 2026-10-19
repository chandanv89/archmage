#!/usr/bin/env bash

chroot_configure_locale_time() {
  local tz locale keymap
  tz="$(config_or_prompt timezone "Timezone (Area/Location)" "UTC")"
  locale="$(config_or_prompt locale "Locale" "en_US.UTF-8")"
  keymap="$(state_get keymap)"
  [[ -z "$keymap" ]] && keymap="us"

  local script
  script="$(cat <<EOS
set -euo pipefail
ln -sf /usr/share/zoneinfo/${tz} /etc/localtime
hwclock --systohc
sed -i 's/^#${locale}/${locale}/' /etc/locale.gen
locale-gen
echo 'LANG=${locale}' > /etc/locale.conf
echo 'KEYMAP=${keymap}' > /etc/vconsole.conf
EOS
)"

  arch_chroot_run "$script"
  state_set timezone "$tz"
  state_set locale "$locale"
}

chroot_configure_network_hostname() {
  local host
  host="$(config_or_prompt hostname "Hostname" "archlinux")"
  local script
  script="$(cat <<EOS
set -euo pipefail
echo '${host}' > /etc/hostname
systemctl enable NetworkManager.service
EOS
)"
  arch_chroot_run "$script"
  state_set hostname "$host"
}

chroot_configure_initramfs() {
  local fs
  fs="$(state_get root_fs)"
  if [[ "$fs" == "btrfs" ]]; then
    arch_chroot_run "mkinitcpio -P"
  fi
}

chroot_enable_timesync() {
  arch_chroot_run "systemctl enable systemd-timesyncd.service"
}

step_chroot_configure_can_skip() {
  state_step_done chroot_configure && [[ -n "$(state_get hostname)" ]]
}

step_chroot_configure_run() {
  chroot_configure_locale_time
  chroot_configure_network_hostname
  chroot_enable_timesync
  chroot_configure_initramfs
  users_apply_in_chroot
}
