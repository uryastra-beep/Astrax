#!/usr/bin/env bash
# opti on|off|toggle|status  -- optimized mode (from a performance audit)
#
# WHAT "on" DOES:
#   1. Hyprland blur: passes 4 -> 2   (measured: +14.6% fps at 200Hz,
#      Hyprland goes from 92.3% to 83.6% of the gfx engine)
#   2. stops taskbar_visibility.py, which polls at 10Hz spawning
#      ~20 hyprctl processes per second to drive an eww taskbar
#      (measured along with the rest: forks/s from 48 -> 4.5)
#
# WHAT IT DOESN'T TOUCH: the HDMI's 200Hz, scaling, animations, shadows,
# rounding, transparency, caelestia's gameMode or the cursor.
#
# The state is saved in ~/.local/state/opti and re-applied by itself on every
# "hyprctl reload" and every startup (hook in config/autostart.lua). Without that,
# the blur would silently go back to 4 -- e.g. when turning off caelestia's gameMode,
# which internally does a reload.

set -u

STATE_FILE="$HOME/.local/state/opti"
DECOR="$HOME/.config/hypr/config/decorations.lua"
TASKBAR="$HOME/scripts/taskbar_visibility.py"
BLUR_ON=2

mkdir -p "$(dirname "$STATE_FILE")"

state() { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo off; }

# "normal" passes value: read from decorations.lua so it doesn't get out of sync
# if you change it by hand. Fallback 4.
blur_default() {
    local v
    v=$(sed -n 's/.*passes[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$DECOR" 2>/dev/null | head -1)
    [ -n "$v" ] && echo "$v" || echo 4
}

set_blur() {
    hyprctl repl "hl.config({ decoration = { blur = { passes = $1 } } })" >/dev/null 2>&1
}

cur_blur() { hyprctl getoption decoration:blur:passes 2>/dev/null | sed -n 's/^int: //p'; }

# PIDs of the watcher chain (sh -c -> flock -> python), excluding this
# script and its parent so it doesn't kill itself (the classic pgrep -f bug).
taskbar_pids() {
    ps -eo pid=,args= | awk -v self="$$" -v parent="$PPID" \
        '$1 != self && $1 != parent && /taskbar_visibility/ && !/opti-ctl/ { print $1 }'
}

stop_taskbar() {
    local pids
    pids=$(taskbar_pids)
    [ -z "$pids" ] && return 0
    kill $pids 2>/dev/null
    sleep 0.4
    pids=$(taskbar_pids)
    [ -n "$pids" ] && kill -9 $pids 2>/dev/null
    return 0
}

start_taskbar() {
    [ -n "$(taskbar_pids)" ] && return 0
    [ -f "$TASKBAR" ] || return 0
    setsid sh -c 'flock -n /tmp/taskbar-visibility.lock python3 "$HOME/scripts/taskbar_visibility.py" > /tmp/taskbar-visibility.log 2>&1' \
        < /dev/null > /dev/null 2>&1 &
    return 0
}

# At startup, autostart launches the watcher with a "sleep 1" in front, so
# an immediate stop wouldn't see it. Short reaper that sweeps for a few seconds.
reap_taskbar_bg() {
    ( for _ in 1 2 3 4 5 6 7 8; do stop_taskbar; sleep 1; done ) > /dev/null 2>&1 &
}

# Liquid Glass (island / Dock) is off while opti is on: tell the blur script after each switch
refresh_glass() { hyprctl repl "if astraxIslandBlurRefresh then astraxIslandBlurRefresh() end" >/dev/null 2>&1 || true; }

apply_on()  { echo on > "$STATE_FILE"; set_blur "$BLUR_ON"; stop_taskbar; refresh_glass; }
apply_off() { echo off > "$STATE_FILE"; set_blur "$(blur_default)"; start_taskbar; refresh_glass; }

status() {
    local st gm tb
    st=$(state)
    gm=$(caelestia shell gameMode isEnabled 2>/dev/null)
    [ -n "$(taskbar_pids)" ] && tb="running" || tb="stopped"
    echo "opti:            $st"
    echo "blur passes:     $(cur_blur)   (normal = $(blur_default), opti = $BLUR_ON)"
    if [ "$gm" = "true" ]; then
        echo "  note: caelestia's gameMode is ON -> blur is fully disabled"
    fi
    echo "taskbar watcher: $tb"
    echo "HDMI:            $(hyprctl monitors -j 2>/dev/null | sed -n 's/.*"refreshRate": \([0-9.]*\).*/\1/p' | tail -1) Hz"
}

case "${1:-status}" in
    on)
        apply_on
        echo on > "$STATE_FILE"
        echo "opti ON  -- blur passes $(cur_blur), taskbar watcher stopped"
        ;;
    off)
        apply_off
        echo off > "$STATE_FILE"
        sleep 0.3
        echo "opti OFF -- blur passes $(cur_blur), taskbar watcher restored"
        ;;
    toggle)
        if [ "$(state)" = "on" ]; then exec "$0" off; else exec "$0" on; fi
        ;;
    reapply)
        # invoked by Hyprland on config.reloaded / hyprland.start
        if [ "$(state)" = "on" ]; then
            set_blur "$BLUR_ON"
            reap_taskbar_bg
        fi
        ;;
    status|'')
        status
        ;;
    *)
        echo "usage: opti on|off|toggle|status" >&2
        exit 1
        ;;
esac
