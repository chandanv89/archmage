#!/usr/bin/env bash
# Wizard UI: dialog when available, otherwise numbered menus.

UI_USE_DIALOG=0

ui_is_non_interactive() {
  [[ -n "$ARCHMAGE_CONFIG" ]] || [[ ! -t 0 ]]
}

ui_init() {
  if command -v dialog >/dev/null 2>&1 && [[ -t 1 ]]; then
    UI_USE_DIALOG=1
  fi
}

ui_heading() {
  local title="$1"
  echo "" >&2
  color_print_stderr cyan_bold "=== $title ==="
  echo "" >&2
}

ui_msg() {
  color_print_stderr dim "$1"
}

ui_pause() {
  if [[ -n "$ARCHMAGE_CONFIG" ]] || [[ ! -t 0 ]]; then
    return 0
  fi
  local msg="${1:-Press Enter to continue...}"
  if [[ "$UI_USE_DIALOG" -eq 1 ]]; then
    dialog --title "Archmage" --msgbox "$msg" 10 70
  else
    read -r -p "$msg" _
  fi
}

ui_input() {
  local prompt="$1"
  local default="${2:-}"
  local result=""
  if [[ -n "$ARCHMAGE_CONFIG" ]]; then
    printf '%s' "$default"
    return 0
  fi
  if [[ "$UI_USE_DIALOG" -eq 1 ]]; then
    result="$(dialog --stdout --inputbox "$prompt" 10 70 "$default")" || return 1
  else
    if [[ -n "$default" ]]; then
      printf '%b%s %b[%s]:%b ' "$C_YELLOW" "$prompt" "$C_DIM" "$default" "$C_RESET" >&2
      read -r result
      result="${result:-$default}"
    else
      printf '%b%s:%b ' "$C_YELLOW" "$prompt" "$C_RESET" >&2
      read -r result
    fi
  fi
  printf '%s' "$result"
}

ui_password() {
  local prompt="$1"
  local result=""
  if [[ "$UI_USE_DIALOG" -eq 1 ]]; then
    result="$(dialog --stdout --insecure --passwordbox "$prompt" 10 70)" || return 1
  else
    printf '%b%s:%b ' "$C_YELLOW" "$prompt" "$C_RESET" >&2
    read -r -s result
    echo "" >&2
  fi
  printf '%s' "$result"
}

ui_menu() {
  local prompt="$1"
  shift
  local options=("$@")
  local i choice

  if ui_is_non_interactive; then
    log_warn "Non-interactive: menu '${prompt}' -> default '${options[0]}'"
    printf '%s' "${options[0]}"
    return 0
  fi

  if [[ "$UI_USE_DIALOG" -eq 1 ]]; then
    local args=()
    local tag=0
    for opt in "${options[@]}"; do
      args+=("$tag" "$opt")
      tag=$((tag + 1))
    done
    choice="$(dialog --stdout --menu "$prompt" 18 70 12 "${args[@]}")" || return 1
    printf '%s' "${options[$choice]}"
    return 0
  fi

  ui_heading "$prompt"
  i=1
  for opt in "${options[@]}"; do
    printf '%b  %s) %s%b\n' "$C_DIM" "$i" "$opt" "$C_RESET" >&2
    i=$((i + 1))
  done
  while true; do
    printf '%bChoice [1-%s]:%b ' "$C_GREEN" "${#options[@]}" "$C_RESET" >&2
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      printf '%s' "${options[$((choice - 1))]}"
      return 0
    fi
    color_print_stderr yellow "Invalid choice."
  done
}

ui_yesno() {
  local prompt="$1"
  local default_yes="${2:-0}"
  if ui_is_non_interactive; then
    [[ "$default_yes" -eq 1 ]] && return 0
    return 1
  fi
  if [[ "$UI_USE_DIALOG" -eq 1 ]]; then
    if dialog --title "Archmage" --yesno "$prompt" 10 70; then
      return 0
    fi
    return 1
  fi
  local hint="y/N"
  [[ "$default_yes" -eq 1 ]] && hint="Y/n"
  local ans
  printf '%b%s %b[%s]:%b ' "$C_YELLOW" "$prompt" "$C_DIM" "$hint" "$C_RESET" >&2
  read -r ans
  ans="${ans,,}"
  if [[ -z "$ans" ]]; then
    [[ "$default_yes" -eq 1 ]] && return 0
    return 1
  fi
  [[ "$ans" == "y" || "$ans" == "yes" ]]
}

config_or_prompt() {
  local key="$1"
  local prompt="$2"
  local default="${3:-}"
  local existing
  existing="$(state_get "$key")"
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return 0
  fi
  if [[ -n "$ARCHMAGE_CONFIG" ]]; then
    echo "$default"
    state_set "$key" "$default"
    return 0
  fi
  local val
  val="$(ui_input "$prompt" "$default")"
  state_set "$key" "$val"
  echo "$val"
}
