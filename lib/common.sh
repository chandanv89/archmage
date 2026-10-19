#!/usr/bin/env bash
# Shared utilities for Archmage.

ARCHMAGE_VERSION="0.1.0"
ARCHMAGE_STATE_DIR="${ARCHMAGE_STATE_DIR:-/var/lib/archmage}"
ARCHMAGE_LOG="${ARCHMAGE_LOG:-/var/log/archmage.log}"
ARCHMAGE_MNT="${ARCHMAGE_MNT:-/mnt}"

ARCHMAGE_DRY_RUN=0
ARCHMAGE_RESUME=0
ARCHMAGE_RESET=0
ARCHMAGE_SHOW_PATHS=0
ARCHMAGE_EXPORT_ONLY=0
ARCHMAGE_EXPORT_CONFIG=""
ARCHMAGE_CONFIG=""
ARCHMAGE_FROM_STEP=""
ARCHMAGE_ONLY_STEP=""

archmage_print_paths() {
  ui_msg "Archmage artifact paths:"
  ui_msg "  Log file:              $ARCHMAGE_LOG"
  ui_msg "  State (env):           $ARCHMAGE_STATE_FILE"
  ui_msg "  State (JSON, needs jq): $ARCHMAGE_STATE_JSON"
  ui_msg "  Exported answers:      $ARCHMAGE_STATE_DIR/exported-answers.json"
  ui_msg "  Package profiles:      $ARCHMAGE_ROOT/config/profiles.yaml"
  ui_msg "  Example --config:      $ARCHMAGE_ROOT/examples/answers.json"
  ui_msg ""
}

log() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '[%s] [%s] %s\n' "$ts" "$level" "$msg" | tee -a "$ARCHMAGE_LOG" >&2
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }

die() {
  log_error "$@"
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "This installer must be run as root."
  fi
}

require_cmd() {
  local cmd="$1"
  local pkg="${2:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -n "$pkg" ]]; then
    die "Required command not found: ${cmd}. On Arch Linux: pacman -Sy --needed ${pkg}"
  fi
  die "Required command not found: ${cmd}"
}

init_logging() {
  mkdir -p "$(dirname "$ARCHMAGE_LOG")" "$ARCHMAGE_STATE_DIR"
  touch "$ARCHMAGE_LOG"
  log_info "Archmage $ARCHMAGE_VERSION starting (dry_run=$ARCHMAGE_DRY_RUN)"
}

run_cmd() {
  log_info "+ $*"
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  "$@"
}

run_cmd_eval() {
  log_info "+ $*"
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  eval "$@"
}

is_live_environment() {
  if [[ -f /etc/arch-release ]] && [[ -d /run/archiso ]]; then
    return 0
  fi
  if grep -qs archiso /proc/cmdline 2>/dev/null; then
    return 0
  fi
  return 1
}

detect_boot_mode() {
  if [[ -r /sys/firmware/efi/fw_platform_size ]]; then
    local size
    size="$(cat /sys/firmware/efi/fw_platform_size)"
    if [[ "$size" == "64" ]]; then
      echo uefi
      return
    fi
    if [[ "$size" == "32" ]]; then
      echo uefi32
      return
    fi
  fi
  echo bios
}

detect_cpu_microcode_pkg() {
  if grep -qiE 'GenuineIntel|Intel' /proc/cpuinfo 2>/dev/null; then
    echo intel-ucode
  elif grep -qiE 'AuthenticAMD|AMD' /proc/cpuinfo 2>/dev/null; then
    echo amd-ucode
  else
    echo ""
  fi
}

device_is_safe_target() {
  local dev="$1"
  if [[ -z "$dev" || ! -b "$dev" ]]; then
    return 1
  fi
  if findmnt -rn -S "$dev" >/dev/null 2>&1; then
    return 1
  fi
  local base="${dev#/dev/}"
  if [[ "$base" == loop* || "$base" == ram* ]]; then
    return 1
  fi
  if lsblk -no NAME "$dev" 2>/dev/null | grep -qE '^(loop|ram)'; then
    return 1
  fi
  return 0
}

disk_normalize_path() {
  local raw="$1"
  raw="${raw//$'\r'/}"
  raw="${raw%%$'\n'*}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  printf '%s' "$raw"
}

disk_validate_path() {
  local disk="$1"
  [[ "$disk" =~ ^/dev/[a-zA-Z0-9_-]+$ ]] || return 1
  [[ -b "$disk" ]] || return 1
  return 0
}

confirm_disk_wipe() {
  local disk="$1"
  disk="$(disk_normalize_path "$disk")"
  disk_validate_path "$disk" || die "Invalid install disk: '$1'"
  ui_heading "Destructive disk operation"
  ui_msg "Target disk: $disk"
  ui_msg ""
  lsblk -f "$disk" 2>/dev/null || true
  ui_msg ""
  ui_msg "Type exactly: YES $disk"
  ui_msg "(YES must be uppercase; spacing as shown.)"
  local answer expected
  answer="$(ui_input "Confirmation")"
  answer="$(disk_normalize_path "$answer")"
  expected="YES ${disk}"
  if [[ "$answer" != "$expected" ]]; then
    log_error "Expected: '$expected' but got: '$answer'"
    die "Disk wipe not confirmed."
  fi
}

chroot_target() {
  echo "$ARCHMAGE_MNT"
}

arch_chroot_run() {
  local script="$1"
  require_cmd arch-chroot
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] arch-chroot $ARCHMAGE_MNT bash -c $(printf '%q' "$script")"
    return 0
  fi
  arch-chroot "$ARCHMAGE_MNT" /bin/bash -euo pipefail -c "$script"
}

load_config_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    die "Config file not found: $file"
  fi
  prereqs_ensure jq jq 1
  if command -v jq >/dev/null 2>&1; then
    local keys
    keys="$(jq -r 'keys[]' "$file")"
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      if [[ "$key" == "root_password" || "$key" == "user_password" ]]; then
        continue
      fi
      local val
      val="$(jq -r --arg k "$key" '.[$k] | if type=="array" then @json else . end' "$file")"
      if [[ "$val" == "null" ]]; then
        continue
      fi
      state_set "$key" "$val"
    done <<< "$keys"
  else
    die "jq is required for --config. Install it, then re-run: pacman -Sy --needed jq"
  fi
}

parse_cli_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resume)
        ARCHMAGE_RESUME=1
        ;;
      --reset)
        ARCHMAGE_RESET=1
        ;;
      --show-paths)
        ARCHMAGE_SHOW_PATHS=1
        ;;
      --export-config)
        shift
        ARCHMAGE_EXPORT_ONLY=1
        if [[ $# -ge 1 && "$1" != -* ]]; then
          ARCHMAGE_EXPORT_CONFIG="$1"
          shift
        else
          ARCHMAGE_EXPORT_CONFIG="${ARCHMAGE_STATE_DIR}/exported-answers.json"
        fi
        ;;
      --dry-run)
        ARCHMAGE_DRY_RUN=1
        ;;
      --config)
        shift
        ARCHMAGE_CONFIG="${1:-}"
        [[ -n "$ARCHMAGE_CONFIG" ]] || die "--config requires a path"
        ;;
      --from-step)
        shift
        ARCHMAGE_FROM_STEP="${1:-}"
        [[ -n "$ARCHMAGE_FROM_STEP" ]] || die "--from-step requires a step id"
        ;;
      --only-step)
        shift
        ARCHMAGE_ONLY_STEP="${1:-}"
        [[ -n "$ARCHMAGE_ONLY_STEP" ]] || die "--only-step requires a step id"
        ;;
      -h|--help)
        cat <<'EOF'
Archmage - guided Arch Linux installation wizard

Usage: install.sh [options]

  --resume          Continue using saved state
  --reset           Clear saved progress and start from the first step
  --show-paths      Print log, state, and config file locations
  --export-config [FILE]  Write answers JSON from saved state and exit
  --dry-run         Print commands without executing destructive actions
  --config FILE     Non-interactive answers (JSON, requires jq)
  --from-step ID    Start at step ID
  --only-step ID    Run a single step ID
  -h, --help        Show this help

Environment: NO_COLOR, ARCHMAGE_NO_BANNER=1, ARCHMAGE_NO_CLEAR=1

Run from the official Arch Linux live ISO as root.
EOF
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}
