#!/usr/bin/env bash

step_live_keyboard_can_skip() {
  state_step_done live_keyboard
}

step_live_keyboard_run() {
  local keymap
  keymap="$(config_or_prompt keymap "Console keymap (empty for US default)" "us")"
  if [[ -n "$keymap" && "$keymap" != "us" ]]; then
    if command -v loadkeys >/dev/null 2>&1; then
      run_cmd loadkeys "$keymap"
    fi
    state_set keymap "$keymap"
  else
    state_set keymap "us"
  fi

  local font
  font="$(config_or_prompt console_font "Console font (empty to skip)" "")"
  if [[ -n "$font" ]] && command -v setfont >/dev/null 2>&1; then
    run_cmd setfont "$font"
    state_set console_font "$font"
  fi
}
