#!/usr/bin/env bash

choices_pick_keymap() {
  local keymap
  keymap="$(ui_choose_state keymap "Console keymap" "us" \
    "us|US English (QWERTY)" \
    "uk|British English (QWERTY)" \
    "de|German (QWERTZ)" \
    "fr|French (AZERTY)" \
    "es|Spanish" \
    "it|Italian" \
    "dvorak|US Dvorak" \
    "no-latin1|Norwegian" \
    "__custom__|Other (type keymap name)")"

  if [[ "$keymap" == "us" || -z "$keymap" ]]; then
    state_set keymap "us"
    printf '%s' "us"
    return 0
  fi

  if command -v loadkeys >/dev/null 2>&1; then
    if ! run_cmd loadkeys "$keymap"; then
      log_warn "Keymap '$keymap' could not be loaded; continuing anyway."
    fi
  fi
  state_set keymap "$keymap"
  printf '%s' "$keymap"
}

choices_pick_console_font() {
  local font
  font="$(ui_choose_state console_font "Console font (live session)" "" \
    "__default__|ISO default (8x16, 1024x768 and up)" \
    "ter-116n|Terminus 12pt (1080p laptops)" \
    "ter-128n|Terminus 14pt (1440p / large laptop)" \
    "ter-132n|Terminus 16pt (4K / high-DPI)" \
    "lat9w-16|Latin-9 wide 16px (crisp 1080p)" \
    "sun12x22|Sun 12x22 (large, very readable)" \
    "__custom__|Other (type font name from /usr/share/kbd/consolefonts)")"

  [[ "$font" == "__default__" ]] && font=""
  if [[ -n "$font" ]] && command -v setfont >/dev/null 2>&1; then
    if ! run_cmd setfont "$font"; then
      log_warn "Font '$font' not found; keeping default console font."
      font=""
    fi
  fi
  state_set console_font "$font"
  printf '%s' "$font"
}

choices_pick_timezone() {
  ui_choose_state timezone "Timezone" "UTC" \
    "UTC|UTC" \
    "Europe/London|Europe/London (UK)" \
    "Europe/Dublin|Europe/Dublin (Ireland)" \
    "Europe/Berlin|Europe/Berlin (Germany)" \
    "Europe/Paris|Europe/Paris (France)" \
    "Europe/Amsterdam|Europe/Amsterdam" \
    "America/New_York|America/New_York (US East)" \
    "America/Chicago|America/Chicago (US Central)" \
    "America/Denver|America/Denver (US Mountain)" \
    "America/Los_Angeles|America/Los_Angeles (US West)" \
    "Asia/Kolkata|Asia/Kolkata (India)" \
    "Asia/Singapore|Asia/Singapore" \
    "Asia/Tokyo|Asia/Tokyo" \
    "Australia/Sydney|Australia/Sydney" \
    "__custom__|Other (Area/City, e.g. Europe/Rome)"
}

choices_pick_locale() {
  ui_choose_state locale "System locale" "en_US.UTF-8" \
    "en_US.UTF-8|English (United States)" \
    "en_GB.UTF-8|English (United Kingdom)" \
    "en_IE.UTF-8|English (Ireland)" \
    "de_DE.UTF-8|German (Germany)" \
    "fr_FR.UTF-8|French (France)" \
    "es_ES.UTF-8|Spanish (Spain)" \
    "it_IT.UTF-8|Italian (Italy)" \
    "pt_PT.UTF-8|Portuguese (Portugal)" \
    "pl_PL.UTF-8|Polish (Poland)" \
    "__custom__|Other (e.g. en_IN.UTF-8)"
}

choices_pick_mirror_country() {
  local guessed default_cc choice
  guessed="$(mirrors_guess_country)"
  default_cc="${guessed:-US}"
  choice="$(ui_choose_state mirror_country "Mirror country (reflector)" "$default_cc" \
    "FAST|Fastest HTTPS (any country)" \
    "IE|Ireland (falls back to UK/NL if needed)" \
    "GB|United Kingdom" \
    "US|United States" \
    "DE|Germany" \
    "FR|France" \
    "NL|Netherlands" \
    "CA|Canada" \
    "AU|Australia" \
    "IN|India" \
    "SG|Singapore" \
    "JP|Japan" \
    "__custom__|Other (two-letter country code)")"
  printf '%s' "$choice"
}
