#!/usr/bin/env bash
# widget2 / widgets2 play|pause|off|restart|p1|p2|opti|status|help
#
# Clock + lyrics (sptlrx) + fullscreen Cava on top -- a single
# wlr-layer-shell surface via Quickshell (~/.config/quickshell/widgets2/shell.qml),
# same as widgets3: real click-through, unfocusable, stays behind
# any real app.
#
#
# MULTI-INSTANCE per monitor: "widgets2 p1" and then
# "widgets2 p2" leave TWO instances running at once, one per screen.
# Each monitor has its own pidfile/log; the
# mutual exclusion with the other 3 sets is PER SCREEN (see
# close_other_sets_on in widget-opti-common.sh): widgets2 on eDP-1 doesn't close
# widgets3 if widgets3 is on HDMI-A-1, but it would close any other
# set that is ALSO on eDP-1.
#
# Colors and lyrics mode (pipes/lyrics) are still written by border_colors.py
# to /tmp/widget-colors.json and /tmp/widget-sptlrx-mode -- the QML reads them
# live (FileView with watchChanges, atomic write on the Python side), so
# a song change doesn't need to restart anything in this set.

set -u

source "$HOME/scripts/widget-opti-common.sh"

# Same lock as the other 3 sets: serializes any invocation among them.
exec 9>/tmp/widget-ctl.lock
flock 9

CACHE_DIR="$HOME/.cache/widgets2"
POWER_STATE_FILE="$HOME/.local/state/widget2-power"
# "widgets2 opti on|off" -- 30fps (on) vs 60fps (off) for cava2. Independent
# from opti-ctl.sh's global "opti" (that one tunes blur/taskbar, not fps). A single
# config shared by ALL instances -- opti is global to the set, not
# per monitor.
OPTI_STATE_FILE="$HOME/.local/state/widget2-opti"
CAVA_CONFIG2="$HOME/.config/cava/config-widget2"

mkdir -p "$CACHE_DIR" "$(dirname "$POWER_STATE_FILE")"

pidfile_for() { widgets2_pidfile_for "$1"; }   # see widget-opti-common.sh
logfile_for() { echo "$CACHE_DIR/widgets2-$1.log"; }

get_pid() {
    local mon="$1" f
    f=$(pidfile_for "$mon")
    [ -f "$f" ] || return 1
    local pid
    pid=$(cat "$f" 2>/dev/null)
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    pid_is_widget "$pid" widgets2 || { rm -f "$f"; return 1; }
    printf '%s\n' "$pid"
}

running_on() { get_pid "$1" > /dev/null 2>&1; }

# any instance running, on ANY monitor
any_running() {
    for m in "${MONITORS[@]}"; do running_on "$m" && return 0; done
    return 1
}

# lists the monitors with a live instance right now
running_monitors() {
    for m in "${MONITORS[@]}"; do running_on "$m" && echo "$m"; done
}

is_stopped() {
    local pid="$1" state
    state=$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null)
    [ "$state" = "T" ]
}

focused_monitor() {
    hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' | head -1
}

sync_cava_framerate() {
    set_cava_framerate "$CAVA_CONFIG2" "$(opti_fps "$OPTI_STATE_FILE")"
}

start_process() {
    local mon="$1"
    sync_cava_framerate
    local qs_bin
    qs_bin=$(command -v qs || command -v quickshell || true)
    if [ -z "$qs_bin" ]; then
        echo "ERROR: Quickshell (qs) not found." >&2
        return 1
    fi
    # WIDGETS2_MONITOR: the QML reads it SYNCHRONOUSLY (Quickshell.env) to
    # set "screen:" before the surface is created -- passing it through a
    # file+FileView was a real race.
    setsid env "WIDGETS2_MONITOR=${mon}" "$qs_bin" -c widgets2 9>&- < /dev/null > "$(logfile_for "$mon")" 2>&1 &
    local pid=$!
    echo "$pid" > "$(pidfile_for "$mon")"
    for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null && break
        sleep 0.1
    done
    sleep 0.2
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: widgets2 ($mon) didn't start. Last log lines:" >&2
        tail -n 40 "$(logfile_for "$mon")" 2>/dev/null >&2
        rm -f "$(pidfile_for "$mon")"
        return 1
    fi
}

stop_process() {
    local mon="$1" pid
    pid=$(get_pid "$mon") || return 0
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null || true
    rm -f "$(pidfile_for "$mon")"
}

# widgets2 opti on|off -- restarts ONLY the cava subprocess of EACH
# instance (not the surface): shell.qml relaunches it by itself when it detects it
# exited, already with the new framerate. No window flicker.
apply_opti() {
    local val="$1"
    case "$val" in
        on|off) ;;
        *) echo "usage: widgets2 opti on|off" >&2; return 1 ;;
    esac
    echo "$val" > "$OPTI_STATE_FILE"
    local fps
    fps=$(opti_fps "$OPTI_STATE_FILE")
    set_cava_framerate "$CAVA_CONFIG2" "$fps"
    if any_running; then
        pkill -f "cava -p ${CAVA_CONFIG2}" 2>/dev/null || true
    fi
    echo "widgets2 opti: $val (cava2 at ${fps}fps, all instances)"
}

# do_play <explicit monitor|""> -- if empty, uses the monitor focused
# right now (the usual behaviour for a bare "widgets2 play").
do_play() {
    local mon="$1"
    [ -n "$mon" ] || mon=$(focused_monitor)
    if [ -z "$mon" ]; then
        echo "couldn't resolve a valid monitor" >&2
        return 1
    fi
    close_other_sets_on "$mon" 2
    echo "on" > "$POWER_STATE_FILE"
    if running_on "$mon"; then
        local pid
        pid=$(get_pid "$mon")
        if is_stopped "$pid"; then
            kill -CONT "$pid"
            echo "widgets2 active (resumed) -> $mon"
        else
            echo "widgets2 was already active -> $mon"
        fi
        return 0
    fi
    if start_process "$mon"; then
        echo "widgets2 active -> $mon"
    else
        return 1
    fi
}

do_pause() {
    any_running || { echo "widgets2 isn't active"; return 0; }
    for mon in $(running_monitors); do
        kill -STOP "$(get_pid "$mon")"
    done
    echo "widgets2 paused"
}

# off turns off ALL instances (every screen) -- "off" was always
# each set's "turn everything off", not a per-monitor off.
do_off() {
    echo "off" > "$POWER_STATE_FILE"
    for mon in "${MONITORS[@]}"; do
        stop_process "$mon"
    done
    # Mop-up: kills any orphan "qs -c widgets2" the pidfile didn't
    # know about (e.g. from an old/lost pidfile of a previous scheme -- it
    # happened once). off() turns off the WHOLE set on
    # ALL screens, so a pkill by pattern is safe here (it doesn't
    # hit a sibling instance on another monitor, because none is left).
    pkill -f "qs -c widgets2$" 2>/dev/null || true
    # NOTE: "off" NO longer closes the other sets. Since all 4 can
    # coexist spread across screens (widgets2 p1 + widgets3 p2 at once),
    # a "universal off" would hit a set that had nothing to do with
    # this one -- each one turns off with its own "off".
    echo "widgets2 closed (they stay off until 'widgets2 play')"
}

# restart relaunches EACH instance that was already running, on its own monitor
do_restart() {
    any_running || { echo "widgets2 was not active"; return 0; }
    local mons
    mons=$(running_monitors)
    for mon in $mons; do
        stop_process "$mon"
    done
    for mon in $mons; do
        start_process "$mon"
    done
    echo "widgets2 restarted -> $(echo "$mons" | tr '\n' ' ')"
}

do_status() {
    local opti_val fps any="OFF"
    any_running && any="ON"
    opti_val=$(opti_state "$OPTI_STATE_FILE")
    fps=$(opti_fps "$OPTI_STATE_FILE")
    echo "widgets2:    $any"
    echo "opti:        $opti_val"
    echo "target FPS:  $fps (cava2, all instances)"
    for mon in "${MONITORS[@]}"; do
        if running_on "$mon"; then
            echo "  $mon: active"
        else
            echo "  $mon: off"
        fi
    done
}

do_help() {
    cat <<'EOF'
usage: widgets2 <command>
  play                -- enable on the monitor FOCUSED right now
  pause               -- freeze all active instances, without closing
  off                 -- close EVERYTHING (all screens), until 'play'
  restart             -- relaunch each instance that was already active
  any-running         -- yes/no (on any screen)
  p1 | p2             -- enable on eDP-1 / HDMI-A-1 -- if the other monitor already
                         had an instance, it keeps running (they coexist)
  p1 opti on|off      -- combined: enable on that screen AND set opti
  p2 opti on|off
  opti on             -- ~30 FPS on cava2 (performance mode, all instances)
  opti off            -- ~60 FPS on cava2 (full quality, default)
  status              -- current state per screen
  help                -- this help

You can have "widgets2" on both screens at once (p1 + p2). What you CAN'T
have is two different SETS on the SAME screen -- enabling any
of the other 3 (widgets/widgets3/widgets4) on a screen that already has
widgets2 closes it there, but not on the other one.
Note: "opti" here is PER SET (cava2 fps, applies to all instances at
once). Different from the global "opti" (bare 'opti' command), which tunes
blur/taskbar for all of Hyprland.
EOF
}

on_exit() {
    local status=$?
    if [ "$status" -eq 0 ] && [ -t 1 ]; then
        kill -TERM "$PPID" 2>/dev/null
    fi
}
trap on_exit EXIT

action="${1:-help}"

case "$action" in
    play|on)
        do_play ""
        ;;
    pause)
        do_pause
        ;;
    off|stop)
        do_off
        ;;
    restart)
        do_restart
        ;;
    any-running)
        any_running && echo yes || echo no
        ;;
    p1)
        do_play "eDP-1"
        if [ "${2:-}" = "opti" ] && [ -n "${3:-}" ]; then
            apply_opti "$3"
        fi
        ;;
    p2)
        do_play "HDMI-A-1"
        if [ "${2:-}" = "opti" ] && [ -n "${3:-}" ]; then
            apply_opti "$3"
        fi
        ;;
    opti)
        apply_opti "${2:-}"
        ;;
    status)
        do_status
        ;;
    help|*)
        do_help
        ;;
esac
