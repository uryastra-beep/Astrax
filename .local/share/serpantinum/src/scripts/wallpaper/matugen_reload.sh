#!/usr/bin/env bash

source "$SCRIPT_DIR/../caching.sh"

quickshell -p "$MAIN_QML" ipc call theme reloadColors >/dev/null 2>&1 &

killall -USR1 .kitty-wrapped
# ghostty: same colors as kitty (see ~/scripts/ghostty-colors.sh)
bash "$HOME/scripts/ghostty-colors.sh" &

wait
