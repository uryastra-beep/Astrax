#!/usr/bin/env bash
# widget3 / widgets3 play|pause|off|restart|p1|p2|opti|status|help
#
# Third desktop widget set: ONLY a fullscreen Cava visualizer,
# 100% transparent, click-through, unfocusable, undecorated, with no open/close
# animation -- "part of the wallpaper". Runs as a real
# wlr-layer-shell surface via Quickshell (~/.config/quickshell/widgets3/shell.qml).
# cava runs in "raw" mode (prints bar numbers to stdout) and the QML
# draws them and colors them by reading /tmp/widget-colors.json.
#
# MULTI-INSTANCE per monitor: "widgets3 p1" and then
# "widgets3 p2" leave TWO instances running at once, one per screen.
# Mutual exclusion with the other 3 sets is PER SCREEN (see
# close_other_sets_on in widget-opti-common.sh).

set -u

source "$HOME/scripts/widget-opti-common.sh"

# Same lock as the other 3 sets: serializes any invocation among them.
exec 9>/tmp/widget-ctl.lock
flock 9

CACHE_DIR="$HOME/.cache/widgets3"
POWER_STATE_FILE="$HOME/.local/state/widget3-power"
# "widgets3 opti on|off" -- 30fps (on) vs 60fps (off) for cava. A single
# config shared by ALL instances -- opti is global to the set.
OPTI_STATE_FILE="$HOME/.local/state/widget3-opti"
CAVA_CONFIG3="$HOME/.config/cava/config-widget3"

mkdir -p "$CACHE_DIR" "$(dirname "$OPTI_STATE_FILE")"

pidfile_for() { widgets3_pidfile_for "$1"; }   # see widget-opti-common.sh
logfile_for() { echo "$CACHE_DIR/widgets3-$1.log"; }

get_pid() {
    local mon="$1" f
    f=$(pidfile_for "$mon")
    [ -f "$f" ] || return 1
    local pid
    pid=$(cat "$f" 2>/dev/null)
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    pid_is_widget "$pid" widgets3 || { rm -f "$f"; return 1; }
    printf '%s\n' "$pid"
}

running_on() { get_pid "$1" > /dev/null 2>&1; }

any_running() {
    for m in "${MONITORS[@]}"; do running_on "$m" && return 0; done
    return 1
}

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
    set_cava_framerate "$CAVA_CONFIG3" "$(opti_fps "$OPTI_STATE_FILE")"
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
    # WIDGETS3_MONITOR: the QML reads it SYNCHRONOUSLY (Quickshell.env) --
    # passing it through a file+FileView was a real race.
    setsid env "WIDGETS3_MONITOR=${mon}" "$qs_bin" -c widgets3 9>&- < /dev/null > "$(logfile_for "$mon")" 2>&1 &
    local pid=$!
    echo "$pid" > "$(pidfile_for "$mon")"
    for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null && break
        sleep 0.1
    done
    sleep 0.2
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: widgets3 ($mon) didn't start. Last log lines:" >&2
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

# widgets3 opti on|off -- restarts ONLY the cava subprocess of EACH
# instance (not the surface).
apply_opti() {
    local val="$1"
    case "$val" in
        on|off) ;;
        *) echo "usage: widgets3 opti on|off" >&2; return 1 ;;
    esac
    echo "$val" > "$OPTI_STATE_FILE"
    local fps
    fps=$(opti_fps "$OPTI_STATE_FILE")
    set_cava_framerate "$CAVA_CONFIG3" "$fps"
    if any_running; then
        pkill -f "cava -p ${CAVA_CONFIG3}" 2>/dev/null || true
    fi
    echo "widgets3 opti: $val (cava at ${fps}fps, all instances)"
}

do_play() {
    local mon="$1"
    [ -n "$mon" ] || mon=$(focused_monitor)
    if [ -z "$mon" ]; then
        echo "couldn't resolve a valid monitor" >&2
        return 1
    fi
    close_other_sets_on "$mon" 3
    echo "on" > "$POWER_STATE_FILE"
    if running_on "$mon"; then
        local pid
        pid=$(get_pid "$mon")
        if is_stopped "$pid"; then
            kill -CONT "$pid"
            echo "widgets3 active (resumed) -> $mon"
        else
            echo "widgets3 was already active -> $mon"
        fi
        return 0
    fi
    if start_process "$mon"; then
        echo "widgets3 ON -> $mon"
    else
        return 1
    fi
}

do_pause() {
    any_running || { echo "widgets3 isn't active"; return 0; }
    for mon in $(running_monitors); do
        kill -STOP "$(get_pid "$mon")"
    done
    echo "widgets3 paused"
}

do_off() {
    echo "off" > "$POWER_STATE_FILE"
    for mon in "${MONITORS[@]}"; do
        stop_process "$mon"
    done
    # Mop-up: kills any orphan "qs -c widgets3" the pidfile didn't
    # know about (same reason as widget2-ctl.sh -- safe here because off()
    # turns off the WHOLE set on ALL screens, there's no sibling
    # instance left to protect).
    pkill -f "qs -c widgets3$" 2>/dev/null || true
    # NOTE: "off" NO longer closes the other sets (see widget2-ctl.sh for
    # why -- per-screen coexistence).
    echo "widgets3 OFF"
}

do_restart() {
    any_running || { echo "widgets3 was not active"; return 0; }
    local mons
    mons=$(running_monitors)
    for mon in $mons; do
        stop_process "$mon"
    done
    for mon in $mons; do
        start_process "$mon"
    done
    echo "widgets3 restarted -> $(echo "$mons" | tr '\n' ' ')"
}

do_status() {
    local opti_val fps any="OFF"
    any_running && any="ON"
    opti_val=$(opti_state "$OPTI_STATE_FILE")
    fps=$(opti_fps "$OPTI_STATE_FILE")
    echo "widgets3:    $any"
    echo "opti:        $opti_val"
    echo "target FPS:  $fps (cava, all instances)"
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
usage: widgets3 <command>
  play                -- enable on the monitor FOCUSED right now
  pause               -- freeze all active instances, without closing
  off                 -- close EVERYTHING (all screens), until 'play'
  restart             -- relaunch each instance that was already active
  any-running         -- yes/no (on any screen)
  p1 | p2             -- enable on eDP-1 / HDMI-A-1 -- if the other monitor already
                         had an instance, it keeps running (they coexist)
  p1 opti on|off      -- combined: enable on that screen AND set opti
  p2 opti on|off
  opti on             -- ~30 FPS on cava (performance mode, all instances)
  opti off            -- ~60 FPS on cava (full quality, default)
  status              -- current state per screen
  help                -- this help

You can have "widgets3" on both screens at once (p1 + p2). What you CAN'T
have is two different SETS on the SAME screen.
Note: "opti" here is PER SET (cava fps, applies to all instances at
once). Different from the global "opti" (bare 'opti' command).
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
