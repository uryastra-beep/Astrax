#!/usr/bin/env bash
# widget5 / widgets5 play [workspace N] | off | restart | p2 | status | help
#
# Mini desktop anchored to a specific WORKSPACE (same mechanism as
# widgets4, see that script), ONLY FOR p2 (HDMI-A-1).
# 3 floating kitty windows: mini fish terminal + decorative unimatrix +
# lavat (window_padding_width=0 -- fills 100% of ITS OWN window, it doesn't
# grow to cover the terminal's). Unlike widgets4, there's NO
# Quickshell surface (no Now Playing/cava) and lavat is never
# hidden (always visible, only its color changes).
#
# Geometry taken live.

set -u

source "$HOME/scripts/widget-opti-common.sh"

# Same lock as the other sets: serializes any invocation among them.
exec 9>/tmp/widget-ctl.lock
flock 9

CFG_DIR="$HOME/.config/widgets5"
WORKSPACE_FILE="$CFG_DIR/workspace"
POWER_STATE_FILE="$HOME/.local/state/widget5-power"
VIS_LOG_FILE="$HOME/.cache/widgets5-visibility.log"

KITTY_CLASSES=(widget5-term widget5-unimatrix widget5-lavat)

mkdir -p "$CFG_DIR" "$(dirname "$POWER_STATE_FILE")" "$(dirname "$VIS_LOG_FILE")"

# ---------------------------------------------------------------------------
# Helpers: mini terminal / unimatrix / lavat (normal kitty windows)
# ---------------------------------------------------------------------------

# Same mechanism as widget4-ctl.sh: reads /tmp/widget-colors.json (written
# by border_colors.py -- color of the song playing, or of the wallpaper
# if there's no music, or a fixed purple if there's no music AND the wallpaper is a
# video -- see revert_widgets()/any_wallpaper_animated() in that script).
lavat_color_args() {
    local colors_file="/tmp/widget-colors.json"
    local primary tertiary
    primary=$(jq -r '.primary // empty' "$colors_file" 2>/dev/null)
    tertiary=$(jq -r '.tertiary // empty' "$colors_file" 2>/dev/null)
    [ -n "$primary" ] || primary="a855f7"
    [ -n "$tertiary" ] || tertiary="7552b3"
    echo "-g -c ${primary} -k ${tertiary}"
}

app_for_widget5() {
    case "$1" in
        widget5-term)       echo "fish -C 'function fish_greeting; end'" ;;
        widget5-unimatrix)  echo "unimatrix" ;;
        widget5-lavat)      echo "lavat $(lavat_color_args)" ;;
    esac
}

kitty_opts_for_widget5() {
    case "$1" in
        widget5-term)       echo "-o background_opacity=0.78 -o window_padding_width=10" ;;
        widget5-unimatrix)  echo "-o background_opacity=0.55 -o window_padding_width=0" ;;
        widget5-lavat)      echo "-o background_opacity=0.75 -o window_padding_width=0" ;;
    esac
}

cmd_for_widget5() {
    local cls="$1" app
    app=$(app_for_widget5 "$cls")
    local base="kitty --class ${cls} -o confirm_os_window_close=0 $(kitty_opts_for_widget5 "$cls")"
    if [ -n "$app" ]; then
        echo "${base} -e ${app}"
    else
        echo "${base}"
    fi
}

find_pid_widget5() {
    pgrep -f "kitty --class $1 -o" | head -1
}

pin_to_workspace() {
    local cls="$1" ws="$2"
    hyprctl repl "hl.window_rule({ match = { class = \"^(${cls})\$\" }, workspace = \"${ws}\" })" > /dev/null 2>&1
}

spawn_widget5_kitty() {
    local cls="$1" ws="$2"
    pin_to_workspace "$cls" "$ws"
    setsid bash -c "$(cmd_for_widget5 "$cls")" 9>&- < /dev/null > /dev/null 2>&1 &
    for _ in $(seq 1 30); do
        hyprctl clients -j 2>/dev/null | jq -e --arg c "$cls" 'any(.[]; .class == $c)' > /dev/null 2>&1 && break
        sleep 0.1
    done
}

move_widget5_window() {
    local cls="$1" ws="$2"
    hyprctl dispatch "hl.dsp.window.move({ window = hl.get_windows({ class = '${cls}' })[1], workspace = '${ws}' })" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Native Serpantinum preset (desktop widgets, NOT the kitty ones
# above): "widgets5 p2" also applies the
# "widgets5" preset of Serpantinum's editor, and "widgets5 off" restores
# the "Default" preset (the "normal" state before widgets5). The function
# apply_widget_preset() is shared (see widget-opti-common.sh) -- it's
# also used by widget-ctl.sh and widget4-ctl.sh.
# ---------------------------------------------------------------------------

ON_PRESET_NAME="widgets5"
OFF_PRESET_NAME="Default"

# ---------------------------------------------------------------------------
# Helpers: workspace / monitor
# ---------------------------------------------------------------------------

workspace_monitor() {
    hyprctl workspaces -j 2>/dev/null | jq -r --argjson id "$1" '.[] | select(.id==$id) | .monitor'
}

active_workspace_id() {
    hyprctl activeworkspace -j 2>/dev/null | jq -r '.id'
}

monitor_active_workspace_id() {
    hyprctl monitors -j 2>/dev/null | jq -r --arg m "$1" '.[] | select(.name==$m) | .activeWorkspace.id'
}

# ---------------------------------------------------------------------------
# Helpers: visibility watcher (workspace-scoped + snap every 2s, see
# widget5_visibility.py)
# ---------------------------------------------------------------------------

start_visibility_watcher() {
    pgrep -f "widget5_visibility.py" > /dev/null 2>&1 && return 0
    # same retry+verify fix as widget4-ctl.sh (see that function for
    # why: flock -n loses the race against the old dying watcher).
    for _ in $(seq 1 15); do
        pgrep -f "widget5_visibility.py" > /dev/null 2>&1 && return 0
        setsid sh -c "flock -n /tmp/widget5-visibility.lock python3 '$HOME/scripts/widget5_visibility.py' > '$VIS_LOG_FILE' 2>&1" \
            9>&- < /dev/null > /dev/null 2>&1 &
        sleep 0.2
        pgrep -f "widget5_visibility.py" > /dev/null 2>&1 && return 0
        sleep 0.2
    done
    echo "ERROR: widgets5 watcher didn't start after retrying. Log:" >&2
    tail -n 20 "$VIS_LOG_FILE" 2>/dev/null >&2
    return 1
}

stop_visibility_watcher() {
    pkill -f "widget5_visibility.py" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Acciones
# ---------------------------------------------------------------------------

do_play() {
    local requested_ws="${1:-}"

    local ws="$requested_ws"
    if [ -z "$ws" ]; then
        ws=$(active_workspace_id)
    fi
    if ! [[ "$ws" =~ ^-?[0-9]+$ ]]; then
        echo "couldn't resolve a valid workspace" >&2
        return 1
    fi

    local mon
    mon=$(workspace_monitor "$ws")
    if [ "$mon" != "HDMI-A-1" ]; then
        echo "widgets5 is only for p2 (HDMI-A-1) -- that workspace is on '$mon'" >&2
        return 1
    fi

    # per-screen mutual exclusion -- Real BUG (external audit): this
    # was never called, so widgets5 could accidentally coexist with
    # another set on the same monitor.
    close_other_sets_on "$mon" 5

    echo "on" > "$POWER_STATE_FILE"
    echo "$ws" > "$WORKSPACE_FILE"

    for cls in "${KITTY_CLASSES[@]}"; do
        if [ -n "$(find_pid_widget5 "$cls")" ]; then
            move_widget5_window "$cls" "$ws" # already exists: relocating keeps the session
        else
            spawn_widget5_kitty "$cls" "$ws"
        fi
    done

    start_visibility_watcher
    apply_widget_preset "$ON_PRESET_NAME" "HDMI-A-1"
    echo "widgets5 ON -> workspace $ws (monitor $mon)"
}

do_off() {
    echo "off" > "$POWER_STATE_FILE"
    # lavat mop-up BEFORE killing its parent kitty -- scoped to this PID
    # only (Real BUG found in an external audit: a global "pkill -9 -x
    # lavat" ALSO killed the lavat of widgets4/widget-ctl.sh on the
    # other monitor, not only this set's orphan).
    lavat_pid=$(find_pid_widget5 "widget5-lavat")
    [ -n "$lavat_pid" ] && pkill -9 -P "$lavat_pid" -x "lavat" 2>/dev/null || true
    for cls in "${KITTY_CLASSES[@]}"; do
        pid=$(find_pid_widget5 "$cls")
        [ -n "$pid" ] && kill "$pid"
    done
    stop_visibility_watcher
    apply_widget_preset "$OFF_PRESET_NAME" "HDMI-A-1"
    echo "widgets5 OFF"
}

do_restart() {
    local ws
    ws=$(cat "$WORKSPACE_FILE" 2>/dev/null)
    local any_running=0
    for cls in "${KITTY_CLASSES[@]}"; do
        [ -n "$(find_pid_widget5 "$cls")" ] && any_running=1
    done
    if [ "$any_running" -eq 0 ]; then
        echo "widgets5 was not active"
        return 0
    fi
    if [ -z "$ws" ]; then
        ws=$(active_workspace_id)
    fi

    lavat_pid=$(find_pid_widget5 "widget5-lavat")
    for cls in "${KITTY_CLASSES[@]}"; do
        pid=$(find_pid_widget5 "$cls")
        [ -n "$pid" ] && kill "$pid"
    done
    for _ in $(seq 1 20); do
        alive=0
        for cls in "${KITTY_CLASSES[@]}"; do
            [ -n "$(find_pid_widget5 "$cls")" ] && alive=1
        done
        [ "$alive" -eq 0 ] && break
        sleep 0.1
    done
    # scoped to this PID only -- see do_off for why (a global pkill
    # by binary name killed lavat of OTHER sets/monitors too).
    [ -n "$lavat_pid" ] && pkill -9 -P "$lavat_pid" -x "lavat" 2>/dev/null || true

    for cls in "${KITTY_CLASSES[@]}"; do
        spawn_widget5_kitty "$cls" "$ws"
    done
    stop_visibility_watcher
    start_visibility_watcher
    apply_widget_preset "$ON_PRESET_NAME" "HDMI-A-1"
    echo "widgets5 reiniciado -> workspace $ws"
}

do_status() {
    local ws state="OFF"
    ws=$(cat "$WORKSPACE_FILE" 2>/dev/null)
    for cls in "${KITTY_CLASSES[@]}"; do
        [ -n "$(find_pid_widget5 "$cls")" ] && state="ON"
    done
    echo "widgets5:    $state"
    echo "workspace:   ${ws:-(not set)}"
    if [ "$state" = "ON" ]; then
        if pgrep -f "widget5_visibility.py" > /dev/null 2>&1; then
            echo "watcher:     active"
        else
            echo "watcher:     DOWN -- 'widgets5 restart' brings it back"
        fi
    fi
    for cls in "${KITTY_CLASSES[@]}"; do
        if [ -n "$(find_pid_widget5 "$cls")" ]; then
            echo "  $cls: active"
        else
            echo "  $cls: off"
        fi
    done
}

do_help() {
    cat <<'EOF'
usage: widgets5 <command>
  play                -- enable, uses the CURRENT workspace (must be on p2/HDMI-A-1)
  play workspace N    -- enable anchored specifically to workspace N (must be on p2)
  off                 -- close everything, stays off until 'play'
  restart             -- relaunch if it was already active
  p2                  -- anchor to the active workspace of HDMI-A-1
  status              -- current state
  help                -- this help

Only exists for p2 (HDMI-A-1). Term + unimatrix +
lavat (lavat fills 100% of its own window, no padding).
They snap back by themselves every 2s if dragged/resized by accident.
Hides instantly (without closing the terminal) when you leave
the target workspace.
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
        if [ "${2:-}" = "workspace" ] && [ -n "${3:-}" ]; then
            do_play "$3"
        else
            do_play ""
        fi
        ;;
    off|stop)
        do_off
        ;;
    restart)
        do_restart
        ;;
    p2)
        target_ws=$(monitor_active_workspace_id "HDMI-A-1")
        if ! [[ "$target_ws" =~ ^-?[0-9]+$ ]]; then
            echo "couldn't resolve the active workspace of HDMI-A-1" >&2
            exit 1
        fi
        do_play "$target_ws"
        ;;
    status)
        do_status
        ;;
    help|*)
        do_help
        ;;
esac
