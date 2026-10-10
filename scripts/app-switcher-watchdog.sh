#!/usr/bin/env bash
# Hyprland sometimes kills astrax-app-switcher ("error in client communication")
# and nothing brought it back -- ALT+Tab/Menu stayed dead until a restart.
# Checks every 10s and relaunches it if it isn't running.
while true; do
    if ! qs list --all 2>/dev/null | grep -q "astrax-app-switcher/shell.qml"; then
        mkdir -p ~/.local/state/astrax-app-switcher
        qs -c astrax-app-switcher -d > /tmp/astrax-app-switcher.log 2>&1
        echo "$(date '+%F %T') app-switcher relanzado" >> /tmp/app-switcher-watchdog.log
    fi
    sleep 10
done
