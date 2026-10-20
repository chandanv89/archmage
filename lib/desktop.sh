#!/usr/bin/env bash

desktop_enable_display_manager() {
  local desktop dm dm_pkg
  desktop="$(state_get desktop_profile)"
  [[ -z "$desktop" || "$desktop" == "none" ]] && return 0

  dm="$(profiles_get_meta "desktop_${desktop}" display_manager)"
  if [[ -z "$dm" ]]; then
    return 0
  fi

  dm_pkg="$(profiles_get_meta "desktop_${desktop}" display_manager_pkg)"
  if [[ -n "$dm_pkg" ]]; then
    arch_chroot_run "pacman -S --noconfirm ${dm_pkg}"
  else
    arch_chroot_run "pacman -S --noconfirm '${dm}'"
  fi

  arch_chroot_run "systemctl enable ${dm}.service"
  state_set display_manager "$dm"
}

desktop_enable_graphical_target() {
  local desktop
  desktop="$(packages_infer_desktop_profile)"
  [[ "$desktop" == "none" ]] && return 0
  # Hyprland (no DM) starts from a tty login shell; keep multi-user.target.
  if [[ "$desktop" == "hyprland" ]]; then
    arch_chroot_run "systemctl set-default multi-user.target"
    state_set graphical_target "0"
    return 0
  fi
  arch_chroot_run "systemctl set-default graphical.target"
  state_set graphical_target "1"
}

desktop_apply_session_groups() {
  local user_name desktop extra
  user_name="$(state_get username)"
  desktop="$(packages_infer_desktop_profile)"
  [[ -n "$user_name" ]] || return 0
  [[ "$desktop" == "none" ]] && return 0

  extra="$(profiles_get_meta "desktop_${desktop}" session_groups)"
  if [[ -z "$extra" ]]; then
    case "$desktop" in
      hyprland) extra="seat,input" ;;
      kde|gnome|xfce) extra="input,render" ;;
      *) extra="input" ;;
    esac
  fi

  arch_chroot_run "set -euo pipefail
id '${user_name}' >/dev/null
usermod -aG wheel,audio,video,storage,${extra} '${user_name}'"
}

desktop_dm_install_os_configs() {
  local desktop template
  desktop="$(packages_infer_desktop_profile)"
  case "$desktop" in
    kde)
      template="$ARCHMAGE_ROOT/config/templates/sddm-wayland.conf"
      [[ -f "$template" ]] || return 0
      install -d -m 0755 "$ARCHMAGE_MNT/etc/sddm.conf.d"
      install -m 0644 "$template" "$ARCHMAGE_MNT/etc/sddm.conf.d/archmage-wayland.conf"
      ;;
  esac
}

desktop_hyprland_install_user_config() {
  local user_name overlay lua_pkg archmage_lua home_cfg keymap
  user_name="$(state_get username)"
  [[ -n "$user_name" ]] || die "Hyprland setup requires a user account (chroot_configure step)."

  overlay="$ARCHMAGE_ROOT/config/templates/hyprland-archmage.lua"
  [[ -f "$overlay" ]] || die "Missing template: $overlay"

  keymap="$(state_get keymap)"
  [[ -z "$keymap" ]] && keymap="us"

  home_cfg="$ARCHMAGE_MNT/home/${user_name}/.config"
  install -d -m 0755 "$home_cfg/hypr" "$home_cfg/waybar"
  lua_pkg="$ARCHMAGE_MNT/usr/share/hypr/hyprland.lua"
  if [[ -f "$lua_pkg" ]]; then
    install -m 0644 "$lua_pkg" "$home_cfg/hypr/hyprland.lua"
  else
    die "Hyprland on the target system has no /usr/share/hypr/hyprland.lua (expected Hyprland 0.56+)."
  fi
  archmage_lua="$ARCHMAGE_MNT/home/${user_name}/.config/hypr/archmage.lua"
  install -m 0644 "$overlay" "$archmage_lua"
  sed -i 's/\r$//' "$archmage_lua" 2>/dev/null || true
  if [[ -f "$ARCHMAGE_ROOT/config/templates/waybar.json" ]]; then
    install -m 0644 "$ARCHMAGE_ROOT/config/templates/waybar.json" "$home_cfg/waybar/config"
  fi

  arch_chroot_run "set -euo pipefail
chown -R '${user_name}:${user_name}' '/home/${user_name}/.config'
sed -i 's/kb_layout = \"us\"/kb_layout = \"${keymap}\"/' '/home/${user_name}/.config/hypr/archmage.lua'
sed -i 's/local menu        = \"hyprlauncher\"/local menu        = \"wofi --show drun\"/' '/home/${user_name}/.config/hypr/hyprland.lua' || true
if ! grep -q 'require(\"archmage\")' '/home/${user_name}/.config/hypr/hyprland.lua'; then
  printf '%s\n' 'require(\"archmage\")' >> '/home/${user_name}/.config/hypr/hyprland.lua'
fi
rm -f '/home/${user_name}/.config/hypr/hyprland.conf'"
}

desktop_hyprland_autostart_profile() {
  local user_name keymap frag profile_path
  user_name="$(state_get username)"
  keymap="$(state_get keymap)"
  [[ -n "$user_name" ]] || return 0
  [[ -z "$keymap" ]] && keymap="us"

  frag="$ARCHMAGE_ROOT/config/templates/hyprland-autostart.fragment"
  [[ -f "$frag" ]] || die "Missing template: $frag"
  profile_path="$ARCHMAGE_MNT/home/${user_name}/.bash_profile"
  install -d -m 0755 "$ARCHMAGE_MNT/home/${user_name}" "$ARCHMAGE_MNT/etc/archmage"
  touch "$profile_path"
  install -m 0644 "$frag" "$ARCHMAGE_MNT/etc/archmage/hypr-autostart.fragment"
  sed -i 's/\r$//' "$ARCHMAGE_MNT/etc/archmage/hypr-autostart.fragment" 2>/dev/null || true

  arch_chroot_run "set -euo pipefail
id '${user_name}' >/dev/null
systemctl enable seatd.service
loginctl enable-linger '${user_name}' 2>/dev/null || true
touch /home/${user_name}/.bash_profile
chown '${user_name}:${user_name}' /home/${user_name}/.bash_profile
if ! grep -q 'archmage-hyprland-autostart' /home/${user_name}/.bash_profile; then
  if ! grep -q '\\.bashrc' /home/${user_name}/.bash_profile 2>/dev/null; then
    printf '%s\n' '[[ -f ~/.bashrc ]] && . ~/.bashrc' >> /home/${user_name}/.bash_profile
  fi
  cat /etc/archmage/hypr-autostart.fragment >> /home/${user_name}/.bash_profile
  sed -i 's/\\r$//' /home/${user_name}/.bash_profile
  chown '${user_name}:${user_name}' /home/${user_name}/.bash_profile
fi
rm -f /etc/archmage/hypr-autostart.fragment"
}

desktop_hyprland_post() {
  local desktop
  desktop="$(packages_infer_desktop_profile)"
  [[ "$desktop" != "hyprland" ]] && return 0

  state_set desktop_profile "hyprland"
  desktop_hyprland_install_user_config
  desktop_hyprland_autostart_profile
  state_set hyprland_configured "1"
}

desktop_dm_post() {
  local desktop
  desktop="$(packages_infer_desktop_profile)"
  case "$desktop" in
    kde|gnome|xfce)
      state_set desktop_profile "$desktop"
      desktop_dm_install_os_configs
      state_set dm_desktop_configured "1"
      ;;
  esac
}

desktop_finish_notes() {
  local desktop dm user_name notes
  desktop="$(packages_infer_desktop_profile)"
  user_name="$(state_get username)"
  [[ "$desktop" == "none" ]] && return 0

  notes="$(profiles_get_meta "desktop_${desktop}" notes)"
  if [[ -n "$notes" ]]; then
    ui_msg "Desktop (${desktop}): ${notes}"
  fi

  case "$desktop" in
    hyprland)
      ui_msg "Hyprland: no login manager. At boot use tty1 (Ctrl+Alt+F1), log in as ${user_name}."
      ui_msg "System seatd is used; start with: dbus-run-session -- start-hyprland (not seatd-launch)."
      ui_msg "If login loops, Hyprland crashed: read ~/.local/share/hyprland/hyprland.log"
      ui_msg "Docs: https://wiki.hypr.land/Getting-Started/Installation/"
      ;;
    kde|gnome|xfce)
      dm="$(state_get display_manager)"
      [[ -z "$dm" ]] && dm="$(profiles_get_meta "desktop_${desktop}" display_manager)"
      ui_msg "After reboot you should see the ${dm} login screen (graphical.target)."
      ui_msg "Still on a TTY? Run: systemctl status ${dm} && systemctl start ${dm}"
      ;;
  esac
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

  desktop_enable_graphical_target
  desktop_apply_session_groups
  desktop_enable_display_manager
  desktop_dm_post
  desktop_hyprland_post

  ui_msg "Desktop profile '$desktop' configured (packages were installed during pacstrap)."
}
