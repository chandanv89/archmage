#!/usr/bin/env bash
# Terminal colors and quiet command execution (full logs go to ARCHMAGE_LOG).

ARCHMAGE_VERBOSE="${ARCHMAGE_VERBOSE:-0}"

C_RESET=""
C_DIM=""
C_BOLD=""
C_RED=""
C_GREEN=""
C_YELLOW=""
C_CYAN=""

color_init() {
  if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 2 ]]; then
    C_RESET=""
    C_DIM=""
    C_BOLD=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_CYAN=""
    return 0
  fi
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
}

color_is_tty() {
  [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]
}

_log_file_append() {
  local line="$1"
  local file="${ARCHMAGE_LOG:-/var/log/archmage.log}"
  printf '%s\n' "$line" >> "$file"
}

color_print_stderr() {
  local style="$1"
  shift
  local text="$*"
  case "$style" in
    dim) printf '%b%s%b\n' "$C_DIM" "$text" "$C_RESET" >&2 ;;
    red) printf '%b%s%b\n' "$C_RED" "$text" "$C_RESET" >&2 ;;
    yellow) printf '%b%s%b\n' "$C_YELLOW" "$text" "$C_RESET" >&2 ;;
    green) printf '%b%s%b\n' "$C_GREEN" "$text" "$C_RESET" >&2 ;;
    cyan) printf '%b%s%b\n' "$C_CYAN" "$text" "$C_RESET" >&2 ;;
    cyan_bold) printf '%b%b%s%b\n' "$C_BOLD" "$C_CYAN" "$text" "$C_RESET" >&2 ;;
    *) printf '%s\n' "$text" >&2 ;;
  esac
}

task_status_truncate() {
  local text="$1"
  local max="${2:-72}"
  if [[ ${#text} -gt $max ]]; then
    printf '%s...' "${text:0:$((max - 3))}"
  else
    printf '%s' "$text"
  fi
}

# One updating status line on stderr; clear previous content so short lines do not leave junk.
task_status_tty_line() {
  local label="$1"
  local suffix="$2"
  local cols line pad max
  cols="${COLUMNS:-80}"
  max=$((cols - 1))
  [[ "$max" -lt 40 ]] && max=40
  line="  ${label}  ${suffix}"
  if [[ ${#line} -gt $max ]]; then
    line="${line:0:max}"
  fi
  printf '\r\033[K%b%s%b' "$C_CYAN" "$line" "$C_RESET" >&2
  pad=$((max - ${#line}))
  if (( pad > 0 )); then
    printf '%*s' "$pad" '' >&2
  fi
}

# Last meaningful line from a growing command log (pacstrap, reflector, etc.).
task_status_pick_line() {
  local file="$1"
  local kind="$2"
  local line=""

  [[ -f "$file" ]] || return 0

  case "$kind" in
    pacstrap)
      line="$(grep -E '^\([0-9]+/[0-9]+\) (installing|reinstalling|upgrading|downloading|checking|removing)' "$file" 2>/dev/null | tail -1)"
      if [[ -z "$line" ]]; then
        line="$(grep -E '^(installing|downloading|upgrading|reinstalling) ' "$file" 2>/dev/null | tail -1)"
      fi
      if [[ -z "$line" ]]; then
        line="$(grep -E '^:: (Processing|Running)' "$file" 2>/dev/null | tail -1)"
      fi
      ;;
    reflector)
      line="$(grep -iE 'Rating|Fetching|Testing|Downloading|Filtering|mirror' "$file" 2>/dev/null | tail -1)"
      ;;
    *)
      line="$(task_status_pick_line "$file" pacstrap)"
      if [[ -z "$line" ]]; then
        line="$(task_status_pick_line "$file" reflector)"
      fi
      ;;
  esac

  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s' "$line"
}

task_run_detect_activity() {
  case "$1" in
    pacstrap) printf '%s' "pacstrap" ;;
    reflector) printf '%s' "reflector" ;;
    *) printf '%s' "" ;;
  esac
}

# Run a command: spinner on TTY, stdout/stderr to log only unless ARCHMAGE_VERBOSE=1.
task_run() {
  local label="$1"
  shift
  local log_out log_ec pid spin i=0 activity detail
  local log_file="${ARCHMAGE_LOG:-/var/log/archmage.log}"

  activity="$(task_run_detect_activity "$1")"

  if [[ "${ARCHMAGE_VERBOSE:-0}" -eq 1 ]] || ! color_is_tty; then
    if [[ "${ARCHMAGE_VERBOSE:-0}" -eq 1 ]] && color_is_tty; then
      color_print_stderr dim "  > $*"
    fi
    if "$@" >>"$log_file" 2>&1; then
      return 0
    fi
    color_print_stderr red "Failed: $label"
    color_print_stderr dim "  See log: $log_file"
    return 1
  fi

  log_out="$(mktemp)"
  (
    "$@" >"$log_out" 2>&1
    echo $? > "${log_out}.ec"
  ) &
  pid=$!
  spin='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    detail=""
    if [[ -n "$activity" ]]; then
      detail="$(task_status_pick_line "$log_out" "$activity")"
    fi
    if [[ -n "$detail" ]]; then
      detail="$(task_status_truncate "$detail")"
      task_status_tty_line "$label" "$detail"
    else
      task_status_tty_line "$label" "${spin:i%4:1}"
    fi
    i=$((i + 1))
    sleep 0.15
  done
  wait "$pid" 2>/dev/null || true
  log_ec="$(cat "${log_out}.ec" 2>/dev/null || echo 1)"
  cat "$log_out" >>"$log_file"
  printf '\r\033[K' >&2
  if [[ "$log_ec" -eq 0 ]]; then
    color_print_stderr green "  OK ${label}"
    rm -f "$log_out" "${log_out}.ec"
    return 0
  fi
  color_print_stderr red "  FAILED: ${label}"
  color_print_stderr dim "  Last lines (full log: ${log_file}):"
  tail -n 8 "$log_out" | while IFS= read -r line; do
    color_print_stderr dim "    $line"
  done
  rm -f "$log_out" "${log_out}.ec"
  return "$log_ec"
}
