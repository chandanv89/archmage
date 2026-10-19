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

# Run a command: spinner on TTY, stdout/stderr to log only unless ARCHMAGE_VERBOSE=1.
task_run() {
  local label="$1"
  shift
  local log_out log_ec pid spin i=0
  local log_file="${ARCHMAGE_LOG:-/var/log/archmage.log}"

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
  color_print_stderr cyan "  ${label}"
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%b  %s %s%b' "$C_CYAN" "${label}" "${spin:i%4:1}" "$C_RESET" >&2
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
