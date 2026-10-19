#!/usr/bin/env bash
# Optional tools: install via pacman on the live ISO or exit with instructions.

prereqs_pacman_hint() {
  local pkg="$1"
  printf 'pacman -Sy --needed %s' "$pkg"
}

prereqs_try_pacman_install() {
  local pkg="$1"
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] would install package: $pkg"
    return 0
  fi
  if ! command -v pacman >/dev/null 2>&1; then
    return 1
  fi
  log_info "Installing package: $pkg ($(prereqs_pacman_hint "$pkg"))"
  pacman -Sy --needed --noconfirm "$pkg"
}

# Ensure command exists; on the live ISO offer or auto-install the given pacman package.
prereqs_ensure() {
  local cmd="$1"
  local pkg="${2:-$1}"
  local auto="${3:-0}"

  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi

  local hint
  hint="$(prereqs_pacman_hint "$pkg")"

  if is_live_environment && command -v pacman >/dev/null 2>&1; then
    local do_install=0
    if [[ "$auto" -eq 1 || -n "$ARCHMAGE_CONFIG" ]]; then
      do_install=1
    elif ui_yesno "Missing '${cmd}'. Install package '${pkg}' now? (${hint})" 1; then
      do_install=1
    fi

    if [[ "$do_install" -eq 1 ]]; then
      if ! prereqs_try_pacman_install "$pkg"; then
        die "Could not install ${pkg}. Check network and mirrors, then run: ${hint}"
      fi
      if command -v "$cmd" >/dev/null 2>&1; then
        return 0
      fi
      die "Package ${pkg} was installed but '${cmd}' is still missing."
    fi
  fi

  die "Missing '${cmd}'. Install it, then re-run Archmage: ${hint}"
}

prereqs_check_core() {
  local cmd
  for cmd in pacstrap arch-chroot genfstab lsblk sfdisk mkfs.ext4 mount ping; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "Missing '${cmd}'. Run Archmage from the official Arch Linux live ISO."
    fi
  done
}

prereqs_before_config() {
  [[ -z "$ARCHMAGE_CONFIG" ]] && return 0
  prereqs_ensure jq jq 1
}
