#!/usr/bin/env bash
# widget6 / widgets6 p1 | p2 | off | restart | status | help
#
# Desktop set with FIXED geometry per monitor (decorative unimatrix +
# lavat + btop), saved as window_rule (move/size) in windowrules.lua
# -- geometry taken live with a guide terminal.
# Unlike widgets4/5 (anchored to
# a specific workspace with their own visibility watcher), widgets6 uses
# DIFFERENT classes per monitor (widget6-* for p1/eDP-1, widget6-p2-* for
# p2/HDMI-A-1) and anchors to the ACTIVE workspace of the requested monitor at the
# moment of "widgets6 p1"/"p2" -- no watcher, simpler.

set -u

source "$HOME/scripts/widget-opti-common.sh"

# Same lock as the other sets: serializes any invocation among them.
exec 9>/tmp/widget-ctl.lock
flock 9

POWER_STATE_FILE="$HOME/.local/state/widget6-power"
WORKSPACE_FILE="$HOME/.config/widgets6/workspace"
mkdir -p "$(dirname "$POWER_STATE_FILE")" "$(dirname "$WORKSPACE_FILE")"

KITTY_CLASSES_P1=(widget6-unimatrix widget6-lavat widget6-btop)
KITTY_CLASSES_P2=(widget6-p2-unimatrix widget6-p2-lavat widget6-p2-btop)
ALL_CLASSES=("${KITTY_CLASSES_P1[@]}" "${KITTY_CLASSES_P2[@]}")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

lavat_color_args() {
    local colors_file="/tmp/widget-colors.json"
    local primary tertiary
    primary=$(jq -r '.primary // empty' "$colors_file" 2>/dev/null)
    tertiary=$(jq -r '.tertiary // empty' "$colors_file" 2>/dev/null)
    [ -n "$primary" ] || primary="a855f7"
    [ -n "$tertiary" ] || tertiary="7552b3"
    echo "-g -c ${primary} -k ${tertiary}"
}

# generic class name ("widget6-unimatrix" or "widget6-p2-unimatrix") ->
# widget type ("unimatrix"/"lavat"/"btop"), dropping the p2 prefix if
# needed.
widget_type() {
    local cls="${1#widget6-}"
    cls="${cls#p2-}"
    echo "$cls"
}

app_for_class() {
    case "$(widget_type "$1")" in
        unimatrix) echo "unimatrix" ;;
        lavat)     echo "lavat $(lavat_color_args)" ;;
        btop)      echo "btop" ;;
    esac
}

kitty_opts_for_class() {
    case "$(widget_type "$1")" in
        unimatrix) echo "-o background_opacity=0.55 -o window_padding_width=0" ;;
        lavat)     echo "-o background_opacity=0.75 -o window_padding_width=0" ;;
        btop)      echo "-o background_opacity=0.75 -o window_padding_width=6" ;;
    esac
}

find_pid_widget6() {
    pgrep -f "kitty --class $1 -o" | head -1
}

any_running() {
    local cls
    for cls in "${ALL_CLASSES[@]}"; do
        [ -n "$(find_pid_widget6 "$cls")" ] && return 0
    done
    return 1
}

classes_running() {
    local cls
    for cls in "$@"; do
        [ -n "$(find_pid_widget6 "$cls")" ] && return 0
    done
    return 1
}

spawn_widget6_kitty() {
    local cls="$1" ws="$2"
    local app opts
    app=$(app_for_class "$cls")
    opts=$(kitty_opts_for_class "$cls")
    setsid bash -c "kitty --class ${cls} -o confirm_os_window_close=0 ${opts} -e ${app}" \
        9>&- < /dev/null > /dev/null 2>&1 &
    for _ in $(seq 1 30); do
        hyprctl clients -j 2>/dev/null | jq -e --arg c "$cls" 'any(.[]; .class == $c)' > /dev/null 2>&1 && break
        sleep 0.1
    done
    move_widget6_window "$cls" "$ws"
}

move_widget6_window() {
    local cls="$1" ws="$2"
    hyprctl dispatch "hl.dsp.window.move({ window = hl.get_windows({ class = '${cls}' })[1], workspace = '${ws}' })" > /dev/null 2>&1
}

kill_classes() {
    local cls pid
    for cls in "$@"; do
        pid=$(find_pid_widget6 "$cls")
        [ -n "$pid" ] && kill "$pid"
    done
}

# workspace where the window of that class is NOW (empty if it doesn't exist)
class_workspace_id() {
    hyprctl clients -j 2>/dev/null | jq -r --arg c "$1" 'first(.[] | select(.class == $c) | .workspace.id) // empty'
}

monitor_active_workspace_id() {
    hyprctl monitors -j 2>/dev/null | jq -r --arg m "$1" '.[] | select(.name==$m) | .activeWorkspace.id'
}

# ---------------------------------------------------------------------------
# Snap watcher (same mechanism as widgets5): if
# you accidentally drag/resize any widgets6 window, it goes back
# to its fixed geometry by itself every 2s. See widget6_visibility.py.
# ---------------------------------------------------------------------------

VIS_LOG_FILE="$HOME/.cache/widgets6-visibility.log"
mkdir -p "$(dirname "$VIS_LOG_FILE")"

start_visibility_watcher() {
    pgrep -f "widget6_visibility.py" > /dev/null 2>&1 && return 0
    for _ in $(seq 1 15); do
        pgrep -f "widget6_visibility.py" > /dev/null 2>&1 && return 0
        setsid sh -c "flock -n /tmp/widget6-visibility.lock python3 '$HOME/scripts/widget6_visibility.py' > '$VIS_LOG_FILE' 2>&1" \
            9>&- < /dev/null > /dev/null 2>&1 &
        sleep 0.2
        pgrep -f "widget6_visibility.py" > /dev/null 2>&1 && return 0
        sleep 0.2
    done
    echo "ERROR: widgets6 watcher didn't start after retrying. Log:" >&2
    tail -n 20 "$VIS_LOG_FILE" 2>/dev/null >&2
    return 1
}

stop_visibility_watcher() {
    pkill -f "widget6_visibility.py" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

do_target() {
    local target_mon="$1"; shift
    local -a classes=("$@")

    local ws
    ws=$(monitor_active_workspace_id "$target_mon")
    if ! [[ "$ws" =~ ^-?[0-9]+$ ]]; then
        echo "ERROR: couldn't resolve the active workspace of $target_mon" >&2
        exit 1
    fi

    echo "on" > "$POWER_STATE_FILE"
    echo "$ws" > "$WORKSPACE_FILE"

    local cls
    for cls in "${classes[@]}"; do
        if [ -n "$(find_pid_widget6 "$cls")" ]; then
            move_widget6_window "$cls" "$ws"
        else
            spawn_widget6_kitty "$cls" "$ws"
        fi
    done
    start_visibility_watcher
    echo "widgets6 ON -> $target_mon, workspace $ws"
}

do_off() {
    echo "off" > "$POWER_STATE_FILE"
    # lavat mop-up BEFORE killing its parent kitty -- scoped to the 2 PIDs
    # of this set only (same rule as widget4/5-ctl.sh: a global pkill -9
    # -x lavat would also kill the one from OTHER sets/monitors).
    local lavat_pid
    for lavat_pid in $(find_pid_widget6 "widget6-lavat") $(find_pid_widget6 "widget6-p2-lavat"); do
        [ -n "$lavat_pid" ] && pkill -9 -P "$lavat_pid" -x "lavat" 2>/dev/null || true
    done
    kill_classes "${ALL_CLASSES[@]}"
    stop_visibility_watcher
    echo "widgets6 OFF"
}

do_restart() {
    if ! any_running; then
        echo "widgets6 was not active"
        return 0
    fi
    local ws
    ws=$(cat "$WORKSPACE_FILE" 2>/dev/null)
    [ -z "$ws" ] && ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')

    # workspace of each set BEFORE killing it: p1 and p2 can be on
    # different workspaces and WORKSPACE_FILE only stores the last one used
    local -a classes=()
    local -A class_ws=()
    local cls set_ws
    if classes_running "${KITTY_CLASSES_P1[@]}"; then
        classes=("${KITTY_CLASSES_P1[@]}")
        set_ws=""
        for cls in "${KITTY_CLASSES_P1[@]}"; do
            [ -z "$set_ws" ] && set_ws=$(class_workspace_id "$cls")
        done
        for cls in "${KITTY_CLASSES_P1[@]}"; do class_ws[$cls]="${set_ws:-$ws}"; done
    fi
    if classes_running "${KITTY_CLASSES_P2[@]}"; then
        classes+=("${KITTY_CLASSES_P2[@]}")
        set_ws=""
        for cls in "${KITTY_CLASSES_P2[@]}"; do
            [ -z "$set_ws" ] && set_ws=$(class_workspace_id "$cls")
        done
        for cls in "${KITTY_CLASSES_P2[@]}"; do class_ws[$cls]="${set_ws:-$ws}"; done
    fi

    local lavat_pid
    for lavat_pid in $(find_pid_widget6 "widget6-lavat") $(find_pid_widget6 "widget6-p2-lavat"); do
        [ -n "$lavat_pid" ] && pkill -9 -P "$lavat_pid" -x "lavat" 2>/dev/null || true
    done
    kill_classes "${classes[@]}"
    for _ in $(seq 1 20); do
        classes_running "${classes[@]}" || break
        sleep 0.1
    done

    for cls in "${classes[@]}"; do
        spawn_widget6_kitty "$cls" "${class_ws[$cls]}"
    done
    stop_visibility_watcher
    start_visibility_watcher
    echo "widgets6 restarted"
}

do_status() {
    local ws state="OFF"
    ws=$(cat "$WORKSPACE_FILE" 2>/dev/null)
    any_running && state="ON"
    echo "widgets6:    $state"
    echo "workspace:   ${ws:-(not set)}"
    if [ "$state" = "ON" ]; then
        if pgrep -f "widget6_visibility.py" > /dev/null 2>&1; then
            echo "watcher:     active"
        else
            echo "watcher:     DOWN -- 'widgets6 restart' brings it back"
        fi
    fi
    local cls
    for cls in "${ALL_CLASSES[@]}"; do
        if [ -n "$(find_pid_widget6 "$cls")" ]; then
            echo "  $cls: active"
        else
            echo "  $cls: off"
        fi
    done
}

do_help() {
    cat <<'EOF'
usage: widgets6 <command>
  p1        -- enable unimatrix+lavat+btop on eDP-1, active workspace of that screen
  p2        -- enable unimatrix+lavat+btop on HDMI-A-1, active workspace of that screen
  off       -- close everything (both monitors)
  restart   -- relaunch whatever was already running (p1, p2, or both)
  status    -- current state
  help      -- this help

Fixed geometry per monitor via window_rule (windowrules.lua), taken
live with a guide terminal. p1 and p2 use different classes (widget6-* /
widget6-p2-*) and both can be on at once, each one on its
monitor. They snap back by themselves every 2s if dragged/resized by
accident (watcher, see widget6_visibility.py).
EOF
}

# Same pattern as widget4/5-ctl.sh: if run from an interactive
# terminal (e.g. the one the bind opens to launch the command), it
# closes by itself when it finishes successfully.
on_exit() {
    local status=$?
    if [ "$status" -eq 0 ] && [ -t 1 ]; then
        kill -TERM "$PPID" 2>/dev/null
    fi
}
trap on_exit EXIT

action="${1:-help}"

case "$action" in
    p1)
        do_target "eDP-1" "${KITTY_CLASSES_P1[@]}"
        ;;
    p2)
        do_target "HDMI-A-1" "${KITTY_CLASSES_P2[@]}"
        ;;
    off|stop)
        do_off
        ;;
    restart)
        do_restart
        ;;
    status)
        do_status
        ;;
    help|*)
        do_help
        ;;
esac
