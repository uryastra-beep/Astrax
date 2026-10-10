#!/usr/bin/env bash
# widget4 / widgets4 play [workspace N] | off | restart | p1 | p2 | opti | status | help
#
# Mini desktop anchored to a specific WORKSPACE (not to a monitor like
# widgets/2/3): mini terminal + "Now Playing"+mini Cava panel + mini btop +
# decorative unimatrix. "Now Playing"+cava are a wlr-layer-shell surface
# (click-through, behind apps -- SAME technique as widgets2/3).
# The terminal,
# btop and unimatrix are normal kitty windows (interactive or not, but
# none can be click-through) that widget4_visibility.py hides/shows
# by MOVING them to a special workspace (it never kills them -- the terminal
# keeps its history). unimatrix, like the old pipes, is purely
# decorative (no_focus=true) and is NOT hidden when there's a real app -- only
# term/btop are hidden for that (see rule B in widget4_visibility.py).

set -u

source "$HOME/scripts/widget-opti-common.sh"

# Same lock as the other 3 sets: serializes any invocation among them.
exec 9>/tmp/widget-ctl.lock
flock 9

CFG_DIR="$HOME/.config/widgets4"
CACHE_DIR="$HOME/.cache/widgets4"
WORKSPACE_FILE="$CFG_DIR/workspace"
QS_PID_FILE="$CACHE_DIR/quickshell.pid"
QS_LOG_FILE="$CACHE_DIR/widgets4.log"
VIS_LOG_FILE="$CACHE_DIR/visibility.log"
POWER_STATE_FILE="$HOME/.local/state/widget4-power"
# "widgets4 opti on|off" -- 30fps (on) vs 60fps (off) for the mini cava.
# Independent from opti-ctl.sh's global "opti" (that one tunes blur/taskbar).
OPTI_STATE_FILE="$HOME/.local/state/widget4-opti"
CAVA_CONFIG4="$HOME/.config/cava/config-widget4"

KITTY_CLASSES=(widget4-term widget4-btop widget4-unimatrix widget4-lavat)

mkdir -p "$CFG_DIR" "$CACHE_DIR" "$(dirname "$OPTI_STATE_FILE")"

# ---------------------------------------------------------------------------
# Helpers: visual (Quickshell: Now Playing + mini cava)
# ---------------------------------------------------------------------------

qs_get_pid() {
    [ -f "$QS_PID_FILE" ] || return 1
    local pid
    pid=$(cat "$QS_PID_FILE" 2>/dev/null)
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || { rm -f "$QS_PID_FILE"; return 1; }
    printf '%s\n' "$pid"
}
qs_running() { qs_get_pid > /dev/null 2>&1; }

sync_cava_framerate() {
    set_cava_framerate "$CAVA_CONFIG4" "$(opti_fps "$OPTI_STATE_FILE")"
}

spawn_visual() {
    local mon="$1"
    sync_cava_framerate
    local qs_bin
    qs_bin=$(command -v qs || command -v quickshell || true)
    if [ -z "$qs_bin" ]; then
        echo "ERROR: Quickshell (qs) not found." >&2
        return 1
    fi
    setsid env "WIDGETS4_MONITOR=${mon}" "$qs_bin" -c widgets4 9>&- < /dev/null > "$QS_LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$QS_PID_FILE"
    for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null && break
        sleep 0.1
    done
    sleep 0.2
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: widgets4 (visual) didn't start. Last log lines:" >&2
        tail -n 40 "$QS_LOG_FILE" 2>/dev/null >&2
        rm -f "$QS_PID_FILE"
        return 1
    fi
}

stop_visual() {
    local pid
    pid=$(qs_get_pid) || return 0
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null || true
    rm -f "$QS_PID_FILE"
}

# ---------------------------------------------------------------------------
# Helpers: mini terminal / btop (normal kitty windows)
# ---------------------------------------------------------------------------

# Reads /tmp/widget-colors.json (same file border_colors.py writes,
# with either the color of the song playing or the wallpaper's if there's no music) and
# builds lavat's gradient flags. If the file doesn't exist yet,
# falls back to the same default colors the widgets4 QML uses
# (root.primaryColor/tertiaryColor).
lavat_color_args() {
    local colors_file="/tmp/widget-colors.json"
    local primary tertiary
    primary=$(jq -r '.primary // empty' "$colors_file" 2>/dev/null)
    tertiary=$(jq -r '.tertiary // empty' "$colors_file" 2>/dev/null)
    [ -n "$primary" ] || primary="cfbfeb"
    [ -n "$tertiary" ] || tertiary="ffdcf0"
    echo "-g -c ${primary} -k ${tertiary}"
}

app_for_widget4() {
    case "$1" in
        # normal fish (CachyOS config.fish), but with fish_greeting
        # redefined as a no-op only for THIS session -- without that, cachyos-config
        # runs "fastfetch" as a greeting in every new mini terminal. -C runs
        # the command and then stays interactive (doesn't replace the shell).
        widget4-term)       echo "fish -C 'function fish_greeting; end'" ;;
        widget4-btop)       echo "btop" ;;
        # no flags -- the package's real --help couldn't be checked
        # when this was written.
        # Adjust flags later if needed.
        widget4-unimatrix)  echo "unimatrix" ;;
        # the only widgets4 widget that reacts to the wallpaper/song color
        # (this set's cava/Now Playing has its own color
        # logic, untouched -- only
        # lavat changes color). lavat supports a real truecolor gradient via -g -c/-k.
        widget4-lavat)      echo "lavat $(lavat_color_args)" ;;
    esac
}

kitty_opts_for_widget4() {
    case "$1" in
        widget4-term)       echo "-o background_opacity=0.78 -o window_padding_width=10" ;;
        widget4-btop)       echo "-o background_opacity=0.75 -o window_padding_width=6" ;;
        widget4-unimatrix)  echo "-o background_opacity=0.55 -o window_padding_width=0" ;;
        widget4-lavat)      echo "-o background_opacity=0.75 -o window_padding_width=0" ;;
    esac
}

cmd_for_widget4() {
    local cls="$1" app
    app=$(app_for_widget4 "$cls")
    local base="kitty --class ${cls} -o confirm_os_window_close=0 $(kitty_opts_for_widget4 "$cls")"
    if [ -n "$app" ]; then
        echo "${base} -e ${app}"
    else
        echo "${base}"
    fi
}

find_pid_widget4() {
    pgrep -f "kitty --class $1 -o" | head -1
}

# Pins the class to a specific WORKSPACE via a "live" window_rule (same
# trick as pin_to_home_monitor in widget-ctl.sh, but with "workspace" instead
# of "monitor") -- makes the window open there regardless of which
# workspace is focused at that moment.
pin_to_workspace() {
    local cls="$1" ws="$2"
    hyprctl repl "hl.window_rule({ match = { class = \"^(${cls})\$\" }, workspace = \"${ws}\" })" > /dev/null 2>&1
}

spawn_widget4_kitty() {
    local cls="$1" ws="$2"
    pin_to_workspace "$cls" "$ws"
    setsid bash -c "$(cmd_for_widget4 "$cls")" 9>&- < /dev/null > /dev/null 2>&1 &
    for _ in $(seq 1 30); do
        hyprctl clients -j 2>/dev/null | jq -e --arg c "$cls" 'any(.[]; .class == $c)' > /dev/null 2>&1 && break
        sleep 0.1
    done
}

# Moves an already existing window to another workspace WITHOUT killing it (keeps
# session/history for the terminal). The
# "window" selector of hl.dsp.* doesn't accept a text address (confirmed
# no-op in mode-ctl.sh), it needs the real object from hl.get_windows(...).
move_widget4_window() {
    local cls="$1" ws="$2"
    hyprctl dispatch "hl.dsp.window.move({ window = hl.get_windows({ class = '${cls}' })[1], workspace = '${ws}' })" > /dev/null 2>&1
}

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
# Helpers: visibility watcher (workspace-scoped, see widget4_visibility.py)
# ---------------------------------------------------------------------------

start_visibility_watcher() {
    pgrep -f "widget4_visibility.py" > /dev/null 2>&1 && return 0
    # Real BUG: "flock -n" is non-blocking -- if this
    # is called right after stop_visibility_watcher() (e.g. in "restart",
    # or in a quick "off"+"play"), the OLD watcher may still be
    # dying (still holding the lock) at the instant the new one
    # tries to take it. flock -n loses that race, fails silently (the
    # "&" below hides the error), and the new watcher never starts.
    # Fix: retry a few times with a short wait instead of a single
    # non-blocking attempt, and CHECK that it really stayed alive (same
    # pattern as spawn_visual()).
    for _ in $(seq 1 15); do
        pgrep -f "widget4_visibility.py" > /dev/null 2>&1 && return 0
        # 9>&- : close the lock fd BEFORE the watcher (long-lived
        # process) inherits it -- otherwise it holds it forever and all
        # future invocations of any of the 4 ctl scripts
        # (they share this same lock) hang waiting for it. Same bug already
        # documented for spawn_widget() in widget-ctl.sh.
        setsid sh -c "flock -n /tmp/widget4-visibility.lock python3 '$HOME/scripts/widget4_visibility.py' > '$VIS_LOG_FILE' 2>&1" \
            9>&- < /dev/null > /dev/null 2>&1 &
        sleep 0.2
        pgrep -f "widget4_visibility.py" > /dev/null 2>&1 && return 0
        sleep 0.2
    done
    echo "ERROR: widgets4 watcher didn't start after retrying. Log:" >&2
    tail -n 20 "$VIS_LOG_FILE" 2>/dev/null >&2
    return 1
}

stop_visibility_watcher() {
    pkill -f "widget4_visibility.py" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Mutual exclusion with widgets/widgets2/widgets3
# ---------------------------------------------------------------------------

# Mutual exclusion PER SCREEN: closes any other set on the
# SAME monitor widgets4 is about to take (not on the other -- so
# "widgets2 p1" + "widgets4 p2" can coexist).
close_other_sets_here() {
    local mon="$1"
    [ -n "$mon" ] && close_other_sets_on "$mon" 4
}

# ---------------------------------------------------------------------------
# widgets4 opti on|off -- restarts ONLY the cava subprocess (not the whole
# surface nor the kitty windows) -- same clean approach as widgets2/3.
# ---------------------------------------------------------------------------

apply_opti() {
    local val="$1"
    case "$val" in
        on|off) ;;
        *) echo "usage: widgets4 opti on|off" >&2; return 1 ;;
    esac
    echo "$val" > "$OPTI_STATE_FILE"
    local fps
    fps=$(opti_fps "$OPTI_STATE_FILE")
    set_cava_framerate "$CAVA_CONFIG4" "$fps"
    if qs_running; then
        pkill -f "cava -p ${CAVA_CONFIG4}" 2>/dev/null || true
    fi
    echo "widgets4 opti: $val (mini cava a ${fps}fps)"
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

    echo "on" > "$POWER_STATE_FILE"
    local old_ws
    old_ws=$(cat "$WORKSPACE_FILE" 2>/dev/null)
    echo "$ws" > "$WORKSPACE_FILE"

    local old_mon="" new_mon
    [ -n "$old_ws" ] && old_mon=$(workspace_monitor "$old_ws")
    new_mon=$(workspace_monitor "$ws")
    if [ -z "$new_mon" ]; then
        echo "workspace $ws no existe" >&2
        return 1
    fi

    close_other_sets_here "$new_mon"

    if qs_running; then
        if [ "$old_mon" != "$new_mon" ]; then
            stop_visual
            spawn_visual "$new_mon" || return 1
        fi
    else
        spawn_visual "$new_mon" || return 1
    fi

    for cls in "${KITTY_CLASSES[@]}"; do
        if [ -n "$(find_pid_widget4 "$cls")" ]; then
            move_widget4_window "$cls" "$ws" # already exists: relocating keeps the session
        else
            spawn_widget4_kitty "$cls" "$ws"
        fi
    done

    start_visibility_watcher
    # "widgets4 p2" (and p1) also applies Serpantinum's native
    # "widgets4" editor preset on that screen.
    apply_widget_preset "widgets4" "$new_mon"
    echo "widgets4 ON -> workspace $ws (monitor $new_mon)"
}

do_off() {
    echo "off" > "$POWER_STATE_FILE"
    stop_visual
    # captured BEFORE killing its parent kitty -- see the mop-up note below.
    lavat_pid=$(find_pid_widget4 "widget4-lavat")
    for cls in "${KITTY_CLASSES[@]}"; do
        pid=$(find_pid_widget4 "$cls")
        [ -n "$pid" ] && kill "$pid"
    done
    stop_visibility_watcher
    # Mop-up: kills any orphan "qs -c widgets4" the pidfile didn't
    # know about (same reason as widget2/3-ctl.sh).
    pkill -f "qs -c widgets4$" 2>/dev/null || true
    # lavat-specific mop-up: found orphaned live (a
    # "lavat" process surviving without its parent kitty, e.g. if kitty detaches it from the
    # process group or it was left from a manual invocation). find_pid_widget4
    # only kills the kitty process -- this makes sure the binary itself
    # always dies too, whether or not it's under a live kitty.
    # Real BUG found in an external audit: a bare "pkill -9 -x lavat"
    # ALSO killed the lavat of widgets5/widget-ctl.sh on the other
    # monitor -- scoped to the parent PID captured above.
    [ -n "$lavat_pid" ] && pkill -9 -P "$lavat_pid" -x "lavat" 2>/dev/null || true
    # NOTE: "off" NO longer closes the other sets (see widget2-ctl.sh for
    # why -- per-screen coexistence).
    echo "widgets4 OFF"
}

do_restart() {
    local ws
    ws=$(cat "$WORKSPACE_FILE" 2>/dev/null)
    local any_running=0
    qs_running && any_running=1
    for cls in "${KITTY_CLASSES[@]}"; do
        [ -n "$(find_pid_widget4 "$cls")" ] && any_running=1
    done
    if [ "$any_running" -eq 0 ]; then
        echo "widgets4 was not active"
        return 0
    fi
    if [ -z "$ws" ]; then
        ws=$(active_workspace_id)
    fi

    stop_visual
    lavat_pid=$(find_pid_widget4 "widget4-lavat")
    for cls in "${KITTY_CLASSES[@]}"; do
        pid=$(find_pid_widget4 "$cls")
        [ -n "$pid" ] && kill "$pid"
    done
    for _ in $(seq 1 20); do
        alive=0
        for cls in "${KITTY_CLASSES[@]}"; do
            [ -n "$(find_pid_widget4 "$cls")" ] && alive=1
        done
        qs_running && alive=1
        [ "$alive" -eq 0 ] && break
        sleep 0.1
    done
    # same lavat mop-up as "off" (scoped, see that branch for why)
    [ -n "$lavat_pid" ] && pkill -9 -P "$lavat_pid" -x "lavat" 2>/dev/null || true

    local mon
    mon=$(workspace_monitor "$ws")
    spawn_visual "$mon"
    for cls in "${KITTY_CLASSES[@]}"; do
        spawn_widget4_kitty "$cls" "$ws"
    done
    # Real BUG: "restart" never reloaded the watcher
    # -- start_visibility_watcher() no-ops if one is already running (its
    # "don't duplicate" guard), so a restart after editing
    # widget4_visibility.py left the OLD process running indefinitely
    # (the new code was never loaded until a manual "off" + "play").
    stop_visibility_watcher
    start_visibility_watcher
    echo "widgets4 reiniciado -> workspace $ws (monitor $mon)"
}

do_status() {
    local ws mon opti_val fps state="OFF"
    ws=$(cat "$WORKSPACE_FILE" 2>/dev/null)
    [ -n "$ws" ] && mon=$(workspace_monitor "$ws")
    if qs_running; then
        state="ON"
    else
        for cls in "${KITTY_CLASSES[@]}"; do
            [ -n "$(find_pid_widget4 "$cls")" ] && state="ON"
        done
    fi
    opti_val=$(opti_state "$OPTI_STATE_FILE")
    fps=$(opti_fps "$OPTI_STATE_FILE")
    echo "widgets4:    $state"
    echo "workspace:   ${ws:-(not set)}"
    echo "monitor:     ${mon:-?}"
    echo "opti:        $opti_val"
    echo "target FPS:  $fps (mini cava)"
    if [ "$state" = "ON" ]; then
        if pgrep -f "widget4_visibility.py" > /dev/null 2>&1; then
            echo "watcher:     active"
        else
            echo "watcher:     DOWN -- 'widgets4 restart' brings it back (without it, term/btop never hide by themselves)"
        fi
    fi
    for cls in "${KITTY_CLASSES[@]}"; do
        if [ -n "$(find_pid_widget4 "$cls")" ]; then
            echo "  $cls: active"
        else
            echo "  $cls: off"
        fi
    done
}

do_help() {
    cat <<'EOF'
usage: widgets4 <command>
  play                -- enable, uses the CURRENT workspace
  play workspace N    -- enable anchored specifically to workspace N
  off                 -- close everything, stays off until 'play'
  restart             -- relaunch if it was already active
  any-running         -- yes/no
  p1 | p2             -- anchor to the active workspace of eDP-1 / HDMI-A-1
  p1 opti on|off      -- combined: anchor and set opti
  p2 opti on|off
  opti on             -- ~30 FPS on the mini cava (performance mode)
  opti off            -- ~60 FPS on the mini cava (full quality, default)
  status              -- current state
  help                -- this help

Once active it does NOT follow focus or change workspace/monitor by itself -- it stays
tied to the target workspace until the next 'play workspace N' / p1 / p2.
It hides instantly (without closing the terminal) when you leave
that workspace, or when a real app opens there (mini terminal + btop). The
Now Playing/mini cava panel isn't hidden by an app -- it goes behind.
Note: "opti" here is PER SET (mini cava fps). Different from the global "opti"
(bare 'opti' command), which tunes blur/taskbar for all of Hyprland.
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
    any-running)
        found="no"
        qs_running && found="yes"
        for cls in "${KITTY_CLASSES[@]}"; do
            [ -n "$(find_pid_widget4 "$cls")" ] && found="yes"
        done
        echo "$found"
        ;;
    p1|p2)
        case "$action" in
            p1) mon="eDP-1" ;;
            p2) mon="HDMI-A-1" ;;
        esac
        target_ws=$(monitor_active_workspace_id "$mon")
        if ! [[ "$target_ws" =~ ^-?[0-9]+$ ]]; then
            echo "couldn't resolve the active workspace of $mon" >&2
            exit 1
        fi
        do_play "$target_ws"
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
