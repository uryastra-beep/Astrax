#!/usr/bin/env bash
# sleep-ctl on|off|toggle|status  -- sleep mode (CTRL+SUPER+N)
#
# WHAT "on" DOES:
#   1. Turns the screens off (DPMS off): total black, and Hyprland stops
#      rendering on them (no frames, no callbacks to quickshell).
#   2. If there are MORE THAN 2 open windows, freezes (SIGSTOP) the ones that aren't
#      playing sound -- doesn't close them, you lose nothing. With 2 or fewer it touches nothing.
#   3. Freezes mpvpaper / cava / quickshell (wallpaper, visualizers, bar/shell).
#   4. Before turning off: outro (wave) + lock screen; on unlock the
#      intro plays (launched by Lock.qml; if there was no lock, by this script).
#   5. Audio (Spotify, etc.) keeps going: an app with an active audio
#      stream is never frozen.
#
# WAKE UP: CTRL+SUPER+N again, or any key (the mouse does NOT wake it,
# so a brush doesn't turn the screen on at night). A lightweight watcher
# (1 query every 3s) detects the screen turning on and restores everything.
#
# State: ~/.local/state/sleep-mode (frozen PIDs, one per line).

set -u

STATE="$HOME/.local/state/sleep-mode"
MAX_AWAKE_WINDOWS=2
mkdir -p "$(dirname "$STATE")"

is_on() { [ -f "$STATE" ]; }

dpms() { hyprctl dispatch "hl.dispatch(hl.dsp.dpms({ action = \"$1\" }))" >/dev/null 2>&1; }

wake_opts() {  # $1 = true|false -> key press wakes the screen
    hyprctl repl "hl.config({ misc = { key_press_enables_dpms = $1, mouse_move_enables_dpms = false } })" >/dev/null 2>&1
}

# any real screen back on = wake up (don't wait for every output: a monitor that
# stays off would leave the frozen lock screen unresponsive on the other one)
screens_any_on() {
    hyprctl monitors -j 2>/dev/null | python3 -c '
import sys, json
ms = [m for m in json.load(sys.stdin) if not m["name"].startswith("HEADLESS")]
sys.exit(0 if any(m["dpmsStatus"] for m in ms) else 1)'
}

# PIDs of windows that must NOT be frozen: apps with an audio stream (matched by
# PipeWire app name against class/executable) + Spotify always.
audio_names() {
    pactl list sink-inputs 2>/dev/null | sed -n \
        -e 's/.*application.name = "\(.*\)"/\1/p' \
        -e 's/.*application.process.binary = "\(.*\)"/\1/p' | tr 'A-Z' 'a-z'
}

freeze_windows() {
    local names
    names="$(audio_names)"
    hyprctl clients -j | NAMES="$names" python3 -c '
import sys, json, os
names = [n for n in os.environ["NAMES"].splitlines() if n]
cl = [c for c in json.load(sys.stdin) if c["mapped"]]
if len(cl) <= '"$MAX_AWAKE_WINDOWS"':
    sys.exit(0)
for c in cl:
    cls = c["class"].lower()
    if "spotify" in cls or any(n in cls or cls in n for n in names):
        continue
    print(c["pid"])' | sort -un
}

# children included (Electron/Chromium spreads work across child processes)
with_children() {
    local p
    for p in "$@"; do
        echo "$p"
        pgrep -P "$p" 2>/dev/null
    done | sort -un
}

# main quickshell shell; NOT the outro/intro instances (astrax-power-wave,
# astrax-intro), which must be able to draw/clear on lock and wake
main_shell_pids() {
    ps -eo pid=,comm=,args= | awk '$2 == "quickshell" && $0 !~ /astrax-power-wave|astrax-intro/ { print $1 }'
}

LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/serpantinum/lock/locked"
# created by Lock.qml only once the compositor confirms every screen is covered
SECURE_FLAG="${XDG_RUNTIME_DIR:-/tmp}/serpantinum/lock/secure"

# outro (wave rises, logo turns off, stays covered ~5s) + lock screen.
# Returns non-zero unless the lock really engaged.
do_lock() {
    if [ "$(bash "$HOME/scripts/active-shell.sh")" = "serpantinum" ]; then
        bash "$HOME/.local/share/serpantinum/src/scripts/lock.sh" || return 1   # outro + lock
        for _ in $(seq 1 50); do
            [ -e "$SECURE_FLAG" ] && return 0
            sleep 0.1
        done
        return 1
    else
        bash "$HOME/scripts/outro-cover.sh"
        caelestia shell lock lock >/dev/null 2>&1
    fi
}

lock_failed() {
    rm -f "$STATE"
    qs -c astrax-power-wave ipc call wave clear >/dev/null 2>&1
    notify-send -u critical "Couldn't lock" "Sleep mode cancelled: not turning the screens off with the session unlocked" 2>/dev/null
    echo "sleep: cancelled, the lock screen didn't engage" >&2
    return 1
}

pids_by_name() { ps -eo pid=,comm= | awk -v n="$1" '$2 == n { print $1 }'; }

apply_on() {
    local pids all
    : > "$STATE"          # mark "asleep" right away: avoids double activation during the outro
    do_lock || { lock_failed; return 1; }
    pids="$(freeze_windows)"
    all="$( { with_children $pids; pids_by_name mpvpaper; pids_by_name cava; main_shell_pids; } | sort -un )"
    for p in $all; do
        # never freeze the compositor or the audio
        case "$(ps -o comm= -p "$p" 2>/dev/null)" in
            Hyprland|pipewire*|wireplumber|"") continue ;;
        esac
        [ "$p" = "$$" ] && continue
        kill -STOP "$p" 2>/dev/null && echo "$p" >> "$STATE"
    done
    # wait for you to release the keys: otherwise the key-up wakes the screen
    sleep 0.8
    dpms off
    sleep 1.5
    wake_opts true
    # watcher: any key turns the screen on -> restore everything
    setsid bash -c '
        sleep 3
        while [ -f "'"$STATE"'" ]; do
            if "'"$0"'" _screens_on; then "'"$0"'" off; break; fi
            sleep 2
        done' </dev/null >/dev/null 2>&1 &
}

apply_off() {
    local p
    if [ -f "$STATE" ]; then
        while read -r p; do kill -CONT "$p" 2>/dev/null; done < "$STATE"
        rm -f "$STATE"
    fi
    wake_opts false
    dpms on
    # without a Serpantinum lock Lock.qml doesn't launch the intro: launch it here
    [ -e "$LOCKFILE" ] || bash "$HOME/scripts/intro.sh" >/dev/null 2>&1 &
}

case "${1:-status}" in
    on)     is_on || apply_on || exit 1 ;;
    off)    apply_off ;;
    toggle) if is_on; then apply_off; else apply_on || exit 1; fi ;;
    _screens_on) screens_any_on ;;
    status)
        if is_on; then echo "sleep: ON ($(wc -l < "$STATE") frozen processes)"; else echo "sleep: off"; fi ;;
    *) echo "usage: sleep-ctl on|off|toggle|status" >&2; exit 1 ;;
esac
