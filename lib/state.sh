#!/usr/bin/env bash
# Persistent installer state (bash associative array + JSON mirror).

declare -gA ARCHMAGE_STATE=()
ARCHMAGE_STATE_FILE="${ARCHMAGE_STATE_DIR}/state.env"
ARCHMAGE_STATE_JSON="${ARCHMAGE_STATE_DIR}/state.json"

state_init() {
  mkdir -p "$ARCHMAGE_STATE_DIR"
  if [[ ! -f "$ARCHMAGE_STATE_FILE" ]]; then
    return 0
  fi
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    [[ -n "$key" ]] || continue
    ARCHMAGE_STATE["$key"]="$val"
  done < "$ARCHMAGE_STATE_FILE"
}

state_get() {
  local key="$1"
  local default="${2:-}"
  echo "${ARCHMAGE_STATE[$key]:-$default}"
}

state_set() {
  local key="$1"
  local val="$2"
  ARCHMAGE_STATE["$key"]="$val"
  state_persist
}

state_mark_step_done() {
  local step="$1"
  state_set "step_${step}_done" "1"
}

state_step_done() {
  local step="$1"
  [[ "$(state_get "step_${step}_done")" == "1" ]]
}

state_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

state_persist() {
  {
    echo "# Archmage state - do not edit while the wizard is running"
    local k
    for k in "${!ARCHMAGE_STATE[@]}"; do
      printf '%s=%s\n' "$k" "$(state_escape "${ARCHMAGE_STATE[$k]}")"
    done | sort
  } > "$ARCHMAGE_STATE_FILE"

  if command -v jq >/dev/null 2>&1; then
    local json='{}'
    local k
    for k in "${!ARCHMAGE_STATE[@]}"; do
      json="$(jq -n --argjson base "$json" --arg k "$k" --arg v "${ARCHMAGE_STATE[$k]}" '$base + {($k): $v}')"
    done
    printf '%s\n' "$json" > "$ARCHMAGE_STATE_JSON"
  fi
}

state_reset() {
  ARCHMAGE_STATE=()
  rm -f "$ARCHMAGE_STATE_FILE" "$ARCHMAGE_STATE_JSON"
  touch "$ARCHMAGE_STATE_FILE"
  echo "# Archmage state" > "$ARCHMAGE_STATE_FILE"
}

state_export_answers() {
  local dest="${1:-$ARCHMAGE_STATE_DIR/exported-answers.json}"
  if ! command -v jq >/dev/null 2>&1; then
    log_warn "jq is not installed; cannot write $dest (see $ARCHMAGE_STATE_FILE)"
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  jq -n \
    --arg keymap "$(state_get keymap)" \
    --arg mirror_country "$(state_get mirror_country)" \
    --arg disk "$(state_get disk)" \
    --arg root_fs "$(state_get root_fs)" \
    --arg use_swap "$(state_get use_swap)" \
    --arg kernel_pkg "$(state_get kernel_pkg)" \
    --arg bootloader "$(state_get bootloader)" \
    --arg desktop_profile "$(state_get desktop_profile)" \
    --arg extras_audio "$(state_get extras_audio)" \
    --arg extras_bluetooth "$(state_get extras_bluetooth)" \
    --arg timezone "$(state_get timezone)" \
    --arg locale "$(state_get locale)" \
    --arg hostname "$(state_get hostname)" \
    --arg username "$(state_get username)" \
    --arg note "Passwords are not stored in state. Add root_password and user_password before using --config." \
    '{
      keymap: (if $keymap == "" then null else $keymap end),
      mirror_country: (if $mirror_country == "" then null else $mirror_country end),
      disk: (if $disk == "" then null else $disk end),
      root_fs: (if $root_fs == "" then null else $root_fs end),
      use_swap: (if $use_swap == "" then null else $use_swap end),
      kernel_pkg: (if $kernel_pkg == "" then null else $kernel_pkg end),
      bootloader: (if $bootloader == "" then null else $bootloader end),
      desktop_profile: (if $desktop_profile == "" then null else $desktop_profile end),
      extras_audio: (if $extras_audio == "" then null else $extras_audio end),
      extras_bluetooth: (if $extras_bluetooth == "" then null else $extras_bluetooth end),
      timezone: (if $timezone == "" then null else $timezone end),
      locale: (if $locale == "" then null else $locale end),
      hostname: (if $hostname == "" then null else $hostname end),
      username: (if $username == "" then null else $username end),
      _archmage_note: $note
    }' > "$dest"
  log_info "Exported answers template: $dest"
  return 0
}
