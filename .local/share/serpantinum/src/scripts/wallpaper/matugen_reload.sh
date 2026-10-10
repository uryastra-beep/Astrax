#!/usr/bin/env bash

source "$SCRIPT_DIR/../caching.sh"

quickshell -p "$MAIN_QML" ipc call theme reloadColors >/dev/null 2>&1 &

# kitty reloads its config (and colors.conf) on SIGUSR1. The process is "kitty"
# on Arch; ".kitty-wrapped" is the NixOS wrapper name -- signal whichever exists.
pkill -USR1 -x kitty 2>/dev/null
pkill -USR1 -x .kitty-wrapped 2>/dev/null
# ghostty: same colors as kitty (see ~/scripts/ghostty-colors.sh)
bash "$HOME/scripts/ghostty-colors.sh" &

wait
