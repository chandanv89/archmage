#!/usr/bin/env bash
# Archmage terminal banner (ANSI colors; respects NO_COLOR).

ARCHMAGE_NAME="Archmage"
ARCHMAGE_TAGLINE="Summon your system. Roll with confidence."

banner_color_enabled() {
  if [[ -n "${NO_COLOR:-}" ]]; then
    return 1
  fi
  if [[ ! -t 1 ]]; then
    return 1
  fi
  return 0
}

banner_c() {
  local code="$1"
  if banner_color_enabled; then
    printf '\033[%sm' "$code"
  fi
}

banner_reset() {
  if banner_color_enabled; then
    printf '\033[0m'
  fi
}

banner_print_art() {
  banner_c '1;38;5;39'
  cat <<'EOF'
┌──────────────────────────────────────────────────────────────────────────────┐
│       d8888                 888      888b     d888                           │
│      d88888                 888      8888b   d8888                           │
│     d88P888                 888      88888b.d88888                           │
│    d88P 888 888d888 .d8888b 88888b.  888Y88888P888  8888b.   .d88b.   .d88b. │
│   d88P  888 888P"  d88P"    888 "88b 888 Y888P 888     "88b d88P"88b d8P  Y8b│
│  d88P   888 888    888      888  888 888  Y8P  888 .d888888 888  888 88888888│
│ d8888888888 888    Y88b.    888  888 888   "   888 888  888 Y88b 888 Y8b.    │
│d88P     888 888     "Y8888P 888  888 888       888 "Y888888  "Y88888  "Y8888 │
│                                                                  888         │
│                                                             Y8b d88P         │
│                                                              "Y88P"          │
└──────────────────────────────────────────────────────────────────────────────┘
EOF
  banner_reset
}

banner_show() {
  if [[ "${ARCHMAGE_NO_BANNER:-0}" == "1" ]]; then
    banner_show_compact
    return 0
  fi

  if [[ -t 1 ]] && [[ "${ARCHMAGE_NO_CLEAR:-0}" != "1" ]]; then
    clear
  fi

  echo ""
  banner_print_art
  echo ""
  banner_c '1;38;5;141'
  printf '  %s\n' "$ARCHMAGE_TAGLINE"
  banner_reset
  banner_c '2;38;5;245'
  printf '  guided arch linux installer  |  archwiki-aligned  |  v%s\n' "$ARCHMAGE_VERSION"
  banner_reset
  echo ""
}

banner_show_compact() {
  banner_c '1;38;5;39'
  printf 'Archmage'
  banner_reset
  printf ' v%s - %s\n' "$ARCHMAGE_VERSION" "$ARCHMAGE_TAGLINE"
}
