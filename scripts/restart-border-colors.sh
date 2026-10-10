#!/bin/sh
# Restarts the color daemon (border_colors.py) without the pkill -f bug
# that kills itself: the pattern with [b] doesn't match this very line.
kill $(pgrep -f "^python3 $HOME/scripts/[b]order_colors") 2>/dev/null
sleep 1
setsid sh -c 'flock -n /tmp/border-colors.lock python3 ~/scripts/border_colors.py > /tmp/border-colors.log 2>&1' </dev/null >/dev/null 2>&1 &
sleep 9
cat /tmp/border-colors.log
