#!/usr/bin/env bash

mirrors_guess_country() {
  local cc=""
  if command -v curl >/dev/null 2>&1; then
    cc="$(curl -fsS --max-time 5 https://ipinfo.io/country 2>/dev/null || true)"
    cc="$(echo "$cc" | tr -d '[:space:]')"
  fi
  echo "$cc"
}

step_mirrors_can_skip() {
  state_step_done mirrors
}

step_mirrors_run() {
  prereqs_ensure reflector reflector 0

  local country
  country="$(state_get mirror_country)"
  if [[ -z "$country" ]]; then
    local guessed
    guessed="$(mirrors_guess_country)"
    country="$(config_or_prompt mirror_country "Mirror country code (e.g. US, IE)" "$guessed")"
  fi
  [[ -n "$country" ]] || die "Country code required for reflector."

  local mirrorlist="/etc/pacman.d/mirrorlist"
  if [[ -f "$mirrorlist" ]]; then
    cp -a "$mirrorlist" "${mirrorlist}.archmage.bak"
  fi

  run_cmd reflector --country "$country" --protocol https --sort rate --save "$mirrorlist"
  state_set mirror_country "$country"
  ui_msg "Mirrorlist updated for country: $country"
  head -n 5 "$mirrorlist" 2>/dev/null || true
}
