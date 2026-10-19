#!/usr/bin/env bash

step_live_keyboard_can_skip() {
  state_step_done live_keyboard
}

step_live_keyboard_run() {
  choices_pick_keymap >/dev/null
  choices_pick_console_font >/dev/null
}
