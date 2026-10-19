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
