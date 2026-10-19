#!/usr/bin/env bash

ARCHMAGE_ROOT_PASS=""
ARCHMAGE_USER_PASS=""

users_load_config_secrets() {
  if [[ -z "$ARCHMAGE_CONFIG" || ! -f "$ARCHMAGE_CONFIG" ]]; then
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  ARCHMAGE_ROOT_PASS="$(jq -r '.root_password // empty' "$ARCHMAGE_CONFIG")"
  ARCHMAGE_USER_PASS="$(jq -r '.user_password // empty' "$ARCHMAGE_CONFIG")"
}

users_collect_credentials() {
  users_load_config_secrets
  if [[ -n "$ARCHMAGE_ROOT_PASS" ]]; then
    return 0
  fi

  local root_pass user_pass user_name
  root_pass="$(ui_password "Root password")"
  user_name="$(config_or_prompt username "Primary username" "archuser")"
  user_pass="$(ui_password "Password for $user_name")"

  ARCHMAGE_ROOT_PASS="$root_pass"
  ARCHMAGE_USER_PASS="$user_pass"
  state_set username "$user_name"
  state_set credentials_collected "1"
}

users_apply_in_chroot() {
  users_collect_credentials

  local root_pass user_pass user_name
  root_pass="$ARCHMAGE_ROOT_PASS"
  user_pass="$ARCHMAGE_USER_PASS"
  user_name="$(state_get username)"

  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] configure users in chroot"
    return 0
  fi

  local chpwd_file="$ARCHMAGE_MNT/etc/archmage-chpasswd"
  umask 077
  {
    printf 'root:%s\n' "$root_pass"
    printf '%s:%s\n' "$user_name" "$user_pass"
  } > "$chpwd_file"
  chmod 600 "$chpwd_file"

  arch_chroot_run "set -euo pipefail
if ! id '${user_name}' >/dev/null 2>&1; then
  useradd -m -G wheel,audio,video,storage -s /bin/bash '${user_name}'
fi
chpasswd < /etc/archmage-chpasswd
rm -f /etc/archmage-chpasswd
install -d -m 0750 /etc/sudoers.d
printf '%s\n' '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel"
}
