#!/usr/bin/env bash

profiles_yaml_path() {
  echo "$ARCHMAGE_ROOT/config/profiles.yaml"
}

profiles_list_packages() {
  local profile="$1"
  local file
  file="$(profiles_yaml_path)"
  awk -v profile="$profile" '
    $0 ~ "^" profile ":" { found=1; next }
    found && /^[a-zA-Z0-9_]+:/ { exit }
    found && /^[[:space:]]+- / {
      sub(/^.*-[[:space:]]+/, "")
      gsub(/[[:space:]]+$/, "")
      if (length($0)) print
    }
  ' "$file"
}

profiles_get_meta() {
  local profile="$1"
  local key="$2"
  local file
  file="$(profiles_yaml_path)"
  awk -v profile="$profile" -v key="$key" '
    $0 ~ "^" profile ":" { found=1; next }
    found && /^[a-zA-Z0-9_]+:/ && $0 !~ /^  / { exit }
    found && $0 ~ "^  " key ":" {
      sub(/^  [^:]+:[[:space:]]*/, "")
      gsub(/^"/, ""); gsub(/"$/, "")
      print
      exit
    }
  ' "$file"
}

packages_normalize_choice() {
  disk_normalize_path "$1"
}

packages_infer_desktop_profile() {
  local saved pkgs
  saved="$(state_get desktop_profile)"
  if [[ -n "$saved" ]]; then
    printf '%s' "$saved"
    return 0
  fi
  pkgs="$(state_get pacstrap_packages)"
  case " ${pkgs} " in
    *" hyprland "*) printf '%s' "hyprland" ;;
    *" plasma-meta "*) printf '%s' "kde" ;;
    *" gnome "*) printf '%s' "gnome" ;;
    *" xfce4 "*) printf '%s' "xfce" ;;
    *) printf '%s' "none" ;;
  esac
}

packages_select_kernel() {
  local k
  k="$(state_get kernel_pkg)"
  if [[ -n "$k" ]]; then
    printf '%s' "$k"
    return 0
  fi
  k="$(ui_menu "Kernel package" "linux" "linux-lts" "linux-zen")"
  k="$(packages_normalize_choice "$k")"
  state_set kernel_pkg "$k"
  printf '%s' "$k"
}

packages_select_desktop() {
  local d
  d="$(packages_infer_desktop_profile)"
  if [[ -n "$d" && "$d" != "none" ]]; then
    state_set desktop_profile "$d"
    printf '%s' "$d"
    return 0
  fi
  d="$(state_get desktop_profile)"
  if [[ -n "$d" ]]; then
    printf '%s' "$d"
    return 0
  fi
  d="$(ui_menu "Desktop environment" \
    "none" \
    "kde" \
    "gnome" \
    "xfce" \
    "hyprland")"
  d="$(packages_normalize_choice "$d")"
  state_set desktop_profile "$d"
  printf '%s' "$d"
}

packages_select_bootloader() {
  local mode bl
  mode="$(state_get boot_mode)"
  bl="$(state_get bootloader)"
  if [[ -n "$bl" ]]; then
    if [[ "$mode" != uefi* && "$bl" == "systemd-boot" ]]; then
      log_warn "systemd-boot needs UEFI; using grub on BIOS firmware."
      bl="grub"
      state_set bootloader "$bl"
    fi
    echo "$bl"
    return 0
  fi
  if [[ "$mode" == uefi* ]]; then
    bl="$(ui_menu "Boot loader (UEFI)" "systemd-boot" "grub")"
  else
    bl="grub"
    state_set bootloader "$bl"
    echo "$bl"
    return 0
  fi
  state_set bootloader "$bl"
  echo "$bl"
}

packages_build_pacstrap_list() {
  local -a pkgs=()
  local p kernel micro bl desktop

  while IFS= read -r p; do
    [[ -n "$p" ]] && pkgs+=("$p")
  done < <(profiles_list_packages base_always)

  kernel="$(packages_select_kernel)"
  pkgs+=("$kernel")

  micro="$(detect_cpu_microcode_pkg)"
  [[ -n "$micro" ]] && pkgs+=("$micro")

  bl="$(packages_select_bootloader)"
  case "$bl" in
    systemd-boot)
      while IFS= read -r p; do [[ -n "$p" ]] && pkgs+=("$p"); done < <(profiles_list_packages bootloader_systemd_boot)
      ;;
    grub)
      while IFS= read -r p; do [[ -n "$p" ]] && pkgs+=("$p"); done < <(profiles_list_packages bootloader_grub)
      ;;
  esac

  if [[ "$(state_get extras_audio)" == "1" ]]; then
    while IFS= read -r p; do [[ -n "$p" ]] && pkgs+=("$p"); done < <(profiles_list_packages extras_audio)
  elif ui_yesno "Install Pipewire audio stack?" 1; then
    while IFS= read -r p; do [[ -n "$p" ]] && pkgs+=("$p"); done < <(profiles_list_packages extras_audio)
    state_set extras_audio "1"
  fi

  if [[ "$(state_get extras_bluetooth)" == "1" ]]; then
    while IFS= read -r p; do [[ -n "$p" ]] && pkgs+=("$p"); done < <(profiles_list_packages extras_bluetooth)
  elif ui_yesno "Install Bluetooth (bluez)?" 0; then
    while IFS= read -r p; do [[ -n "$p" ]] && pkgs+=("$p"); done < <(profiles_list_packages extras_bluetooth)
    state_set extras_bluetooth "1"
  fi

  desktop="$(packages_select_desktop)"
  if [[ "$desktop" != "none" ]]; then
    while IFS= read -r p; do [[ -n "$p" ]] && pkgs+=("$p"); done < <(profiles_list_packages "desktop_${desktop}")
  fi

  local unique line
  printf '%s\n' "${pkgs[@]}" | awk '!seen[$0]++'
}

step_pacstrap_can_skip() {
  state_step_done pacstrap && [[ -d "$ARCHMAGE_MNT/etc" ]]
}

step_pacstrap_run() {
  require_cmd pacstrap
  local -a pkgs=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && pkgs+=("$line")
  done < <(packages_build_pacstrap_list)

  state_set pacstrap_packages "$(printf '%s ' "${pkgs[@]}")"

  log_info "Pacstrap packages: ${pkgs[*]}"
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] pacstrap -K $ARCHMAGE_MNT ${pkgs[*]}"
    return 0
  fi

  run_cmd pacstrap -K "$ARCHMAGE_MNT" "${pkgs[@]}"
}

step_fstab_can_skip() {
  [[ -f "$ARCHMAGE_MNT/etc/fstab" ]] && state_step_done fstab
}

step_fstab_run() {
  require_cmd genfstab
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] genfstab -U $ARCHMAGE_MNT"
    color_print_stderr dim "  [dry-run] genfstab"
    return 0
  fi
  task_run "Generating fstab..." bash -c "genfstab -U $(printf '%q' "$ARCHMAGE_MNT") > $(printf '%q' "$ARCHMAGE_MNT/etc/fstab")"
  ui_msg "Generated fstab:"
  while IFS= read -r line; do
    color_print_stderr dim "  $line"
  done < "$ARCHMAGE_MNT/etc/fstab"
  if ui_yesno "Edit fstab in nano before continuing?" 0; then
    nano "$ARCHMAGE_MNT/etc/fstab"
  fi
}
