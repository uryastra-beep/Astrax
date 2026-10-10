#!/usr/bin/env bash
# Called from windowrules.lua every time a widget-* closes. If
# widget-ctl.sh is NOT actively restarting right now (i.e. the
# close came from elsewhere, like Super+Q), it sets a 5s cooldown so
# widget_visibility.py doesn't reopen it immediately. If it IS restarting
# (song change, glow, etc.), it marks nothing -- reopens normally.

CTL_COOLDOWN="/tmp/widget-ctl-cooldown"
MANUAL_COOLDOWN="/tmp/widget-manual-close-cooldown"
FRESH_SECONDS=2

now=$(date +%s)
ctl_mtime=$(stat -c %Y "$CTL_COOLDOWN" 2>/dev/null || echo 0)

if (( now - ctl_mtime > FRESH_SECONDS )); then
    touch "$MANUAL_COOLDOWN"
fi
