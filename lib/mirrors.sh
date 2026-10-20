#!/usr/bin/env bash

mirrors_guess_country() {
  local cc=""
  if command -v curl >/dev/null 2>&1; then
    cc="$(curl -fsS --max-time 5 https://ipinfo.io/country 2>/dev/null || true)"
    cc="$(echo "$cc" | tr -d '[:space:]')"
  fi
  echo "$cc"
}

mirrors_normalize_country() {
  local raw="$1"
  raw="$(echo "$raw" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
  case "$raw" in
    IRELAND) raw=IE ;;
    UK|UNITEDKINGDOM) raw=GB ;;
    USA|UNITEDSTATES) raw=US ;;
    FASTEST|FAST|WORLD|WORLDWIDE|ANY) raw=FAST ;;
  esac
  printf '%s' "$raw"
}

mirrors_country_fallbacks() {
  local cc="$1"
  case "$cc" in
    IE) printf '%s' "IE,GB,NL" ;;
    IS) printf '%s' "IS,GB,NL" ;;
    LU) printf '%s' "LU,DE,FR,NL" ;;
    *) printf '%s' "$cc" ;;
  esac
}

mirrors_mirrorlist_has_servers() {
  local file="$1"
  [[ -f "$file" ]] && grep -q '^Server' "$file"
}

mirrors_reflector_activity_label() {
  local country_spec="$1"
  if [[ "$country_spec" == "*" || "$country_spec" == "FAST" ]]; then
    printf '%s' "Ranking mirrors worldwide (may take a few minutes)..."
  else
    printf '%s' "Ranking mirrors for ${country_spec}..."
  fi
}

mirrors_reflector_try() {
  local mirrorlist="$1"
  local label="$2"
  shift 2
  if [[ "$ARCHMAGE_DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] reflector $* --sort rate --latest 20 --save $mirrorlist"
    return 0
  fi
  # shellcheck disable=SC2086
  task_run "$label" reflector $* --sort rate --latest 20 --save "$mirrorlist"
}

mirrors_reflector_update() {
  local country_spec="$1"
  local mirrorlist="$2"
  local -a attempts=()
  local label
  label="$(mirrors_reflector_activity_label "$country_spec")"

  if [[ "$country_spec" == "*" || "$country_spec" == "FAST" ]]; then
    attempts+=("--protocol https --protocol http")
    attempts+=("")
  else
    attempts+=("--country $country_spec --protocol https --protocol http")
    attempts+=("--country $country_spec")
  fi

  local args
  for args in "${attempts[@]}"; do
    # shellcheck disable=SC2086
    if mirrors_reflector_try "$mirrorlist" "$label" $args && mirrors_mirrorlist_has_servers "$mirrorlist"; then
      return 0
    fi
    log_warn "Reflector found no usable mirrors for: reflector $args"
  done
  return 1
}

step_mirrors_can_skip() {
  state_step_done mirrors
}

step_mirrors_run() {
  prereqs_ensure reflector reflector 0

  local country
  country="$(state_get mirror_country)"
  if [[ -z "$country" ]]; then
    country="$(choices_pick_mirror_country)"
  fi
  if [[ -z "$country" ]]; then
    country="$(state_get mirror_country)"
  fi
  [[ -n "$country" ]] || die "Country code required for reflector."

  country="$(mirrors_normalize_country "$country")"

  local mirrorlist="/etc/pacman.d/mirrorlist"
  if [[ -f "$mirrorlist" ]]; then
    cp -a "$mirrorlist" "${mirrorlist}.archmage.bak"
  fi

  local spec tried ok=0
  spec="$country"
  if mirrors_reflector_update "$spec" "$mirrorlist"; then
    ok=1
  else
    tried="$spec"
    spec="$(mirrors_country_fallbacks "$country")"
    if [[ "$spec" != "$country" ]]; then
      ui_msg "No mirrors for ${country}; trying nearby countries: ${spec}"
      if mirrors_reflector_update "$spec" "$mirrorlist"; then
        ok=1
      fi
    fi
    if [[ "$ok" -eq 0 ]]; then
      ui_msg "Trying fastest mirrors worldwide (any country)..."
      if mirrors_reflector_update "FAST" "$mirrorlist"; then
        ok=1
        spec="*"
      fi
    fi
  fi

  if [[ "$ok" -eq 0 ]]; then
    if [[ -f "${mirrorlist}.archmage.bak" ]]; then
      cp -a "${mirrorlist}.archmage.bak" "$mirrorlist"
    fi
    die "Reflector could not build a mirrorlist (country=${tried:-$country}). Check network and try mirror country GB, DE, or FASTEST in the menu."
  fi

  state_set mirror_country "$country"
  state_set mirror_reflector_spec "$spec"
  ui_msg "Mirrorlist updated (reflector countries: ${spec})"
  head -n 5 "$mirrorlist" 2>/dev/null | while IFS= read -r line; do
    color_print_stderr dim "  $line"
  done
}
