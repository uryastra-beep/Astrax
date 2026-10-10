# shellcheck shell=bash
# Helpers shared by widget-ctl.sh / widget2-ctl.sh / widget3-ctl.sh /
# widget4-ctl.sh for:
#   1. EACH SET's "opti" mode (different from opti-ctl.sh's global
#      "opti", which tunes blur/taskbar). This opti controls the
#      framerate of each set's CONTINUOUS animations (cava, and kitty
#      repaint_delay of cava/lavat):
#        opti off (default) -> ~60 FPS / full quality
#        opti on             -> ~30 FPS / performance mode
#      Doesn't touch the monitor's physical Hz or Hyprland's global animations.
#   2. mutual exclusion PER SCREEN between the 4 sets: two DIFFERENT sets can't
#      coexist on the SAME monitor, but they can coexist on
#      different monitors (e.g. "widgets2 p1" + "widgets3 p2" at once).
#      widgets2/widgets3 also support MULTIPLE simultaneous instances of their own,
#      one per monitor (e.g. "widgets2 p1" + "widgets2 p2" at the
#      same time).
#
# Sourced, not run on its own. All functions are pure, they take the
# state / config path or the monitor name as an argument.

set -u

MONITORS=(eDP-1 HDMI-A-1)

# opti_state <state_file> -> "on" or "off" (default "off" = 60fps/full quality)
opti_state() {
    local f="$1"
    if [ -f "$f" ]; then cat "$f"; else echo "off"; fi
}

# opti_fps <state_file> -> 30 o 60
opti_fps() {
    [ "$(opti_state "$1")" = "on" ] && echo 30 || echo 60
}

# opti_kitty_repaint_delay <state_file> -> equivalent kitty repaint_delay
# in ms (60fps ~ 16ms, 30fps ~ 33ms)
opti_kitty_repaint_delay() {
    [ "$(opti_state "$1")" = "on" ] && echo 33 || echo 16
}

# set_cava_framerate <cava_config_path> <fps>
# Patches ONLY the "framerate = N" line in [general], without touching the rest of the
# file (color gradients, smoothing, eq, etc stay intact).
set_cava_framerate() {
    local config_path="$1" fps="$2"
    [ -f "$config_path" ] || return 0
    sed -i "s/^framerate[[:space:]]*=[[:space:]]*[0-9][0-9]*/framerate = ${fps}/" "$config_path"
}

# cava_framerate_of <cava_config_path> -> current value, or empty if it couldn't be read
cava_framerate_of() {
    sed -n 's/^framerate[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# Mutual exclusion PER SCREEN between widgets / widgets2 / widgets3 / widgets4.
# They share the same flock (/tmp/widget-ctl.lock) to serialize THEIR OWN
# operations, so no ctl script can invoke the OTHERS while
# holding that lock -- total deadlock (the other one would wait for the same lock).
# That's why everything here works directly by process/pid-file, without going through their scripts.
# ---------------------------------------------------------------------------

# cava/sptlrx were removed from widget-ctl.sh -- list cleaned up
# (related BUG already fixed in widget_visibility.py, see that file).
WIDGETS1_CLASSES=(widget-clock widget-lavat widget-clock-ghost)
WIDGETS4_CLASSES=(widget4-term widget4-btop widget4-unimatrix widget4-lavat)
WIDGETS5_CLASSES=(widget5-term widget5-unimatrix widget5-lavat)

# Session-scoped dir for the Quickshell widget pidfiles: cleared at logout,
# so a pidfile can never outlive the processes of this session.
WIDGET_RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/astrax-widgets"
mkdir -p "$WIDGET_RUN_DIR"

# pid_is_widget <pid> <config> -- true only if <pid> is OUR "qs -c <config>"
# (same user, matching command line). A reused PID belonging to another
# program never counts as a widget, and is never killed as one.
pid_is_widget() {
    local pid="$1" cfg="$2" cmd
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [ -O "/proc/$pid" ] || return 1
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || return 1
    [[ " $cmd " == *" -c $cfg "* ]]
}

# _pidfile_alive <pidfile> <config>
_pidfile_alive() {
    [ -f "$1" ] || return 1
    local pid
    pid=$(cat "$1" 2>/dev/null)
    pid_is_widget "$pid" "$2" || { rm -f "$1"; return 1; }
}

# _pidfile_kill <pidfile> <config>
_pidfile_kill() {
    [ -f "$1" ] || return 0
    local pid
    pid=$(cat "$1" 2>/dev/null)
    pid_is_widget "$pid" "$2" && kill "$pid" 2>/dev/null
    rm -f "$1"
}

# monitor id (0/1/...) -> name (eDP-1/HDMI-A-1), to read the
# "monitor" field (numeric) returned by "hyprctl clients -j".
_monitor_id_to_name() {
    hyprctl monitors -j 2>/dev/null | jq -r --argjson id "$1" '.[] | select(.id==$id) | .name' 2>/dev/null
}

# -------- widgets1 (kitty, single instance -- follows focus or the last p1/p2) --------

any_widgets1_running() {
    for cls in "${WIDGETS1_CLASSES[@]}"; do
        pgrep -f "kitty --class ${cls} -o" > /dev/null 2>&1 && return 0
    done
    return 1
}

# REAL monitor where widget-clock is right now (not the
# preference file -- that one may be empty if it was never set with p1/p2 and is
# "following focus"; this is the source of truth).
_widgets1_actual_monitor() {
    local mon_id
    mon_id=$(hyprctl clients -j 2>/dev/null | jq -r '[.[] | select(.class=="widget-clock")][0].monitor // empty')
    [ -n "$mon_id" ] && _monitor_id_to_name "$mon_id"
}

any_widgets1_running_on() {
    any_widgets1_running || return 1
    [ "$(_widgets1_actual_monitor)" = "$1" ]
}

kill_widgets1() {
    for cls in "${WIDGETS1_CLASSES[@]}"; do
        pgrep -f "kitty --class ${cls} -o" | xargs -r kill 2>/dev/null
    done
}

kill_widgets1_on() {
    any_widgets1_running_on "$1" && kill_widgets1
}

# -------- widgets2 / widgets3 (Quickshell, MULTI-instance: one per monitor) --------

widgets2_pidfile_for() { echo "$WIDGET_RUN_DIR/widgets2-$1.pid"; }
widgets3_pidfile_for() { echo "$WIDGET_RUN_DIR/widgets3-$1.pid"; }

any_widgets2_running_on() { _pidfile_alive "$(widgets2_pidfile_for "$1")" widgets2; }
any_widgets3_running_on() { _pidfile_alive "$(widgets3_pidfile_for "$1")" widgets3; }
kill_widgets2_on() { _pidfile_kill "$(widgets2_pidfile_for "$1")" widgets2; }
kill_widgets3_on() { _pidfile_kill "$(widgets3_pidfile_for "$1")" widgets3; }

# "running" (without saying where) = any instance on ANY monitor
any_widgets2_running() {
    for m in "${MONITORS[@]}"; do any_widgets2_running_on "$m" && return 0; done
    return 1
}
any_widgets3_running() {
    for m in "${MONITORS[@]}"; do any_widgets3_running_on "$m" && return 0; done
    return 1
}
kill_widgets2() { for m in "${MONITORS[@]}"; do kill_widgets2_on "$m"; done; }
kill_widgets3() { for m in "${MONITORS[@]}"; do kill_widgets3_on "$m"; done; }

# -------- widgets4 (Quickshell + kitty, single instance tied to a workspace) --------

WIDGETS4_PID_FILE="$WIDGET_RUN_DIR/widgets4.pid"

any_widgets4_running() {
    _pidfile_alive "$WIDGETS4_PID_FILE" widgets4 && return 0
    for cls in "${WIDGETS4_CLASSES[@]}"; do
        pgrep -f "kitty --class ${cls} -o" > /dev/null 2>&1 && return 0
    done
    return 1
}

_widgets4_actual_monitor() {
    local ws
    ws=$(cat "$HOME/.config/widgets4/workspace" 2>/dev/null)
    [[ "$ws" =~ ^-?[0-9]+$ ]] || return 1
    hyprctl workspaces -j 2>/dev/null | jq -r --argjson id "$ws" '.[] | select(.id==$id) | .monitor // empty'
}

any_widgets4_running_on() {
    any_widgets4_running || return 1
    [ "$(_widgets4_actual_monitor)" = "$1" ]
}

kill_widgets4() {
    _pidfile_kill "$WIDGETS4_PID_FILE" widgets4
    for cls in "${WIDGETS4_CLASSES[@]}"; do
        pgrep -f "kitty --class ${cls} -o" | xargs -r kill 2>/dev/null
    done
}

kill_widgets4_on() {
    any_widgets4_running_on "$1" && kill_widgets4
}

# -------- widgets5 (kitty, single instance tied to a workspace, p2 ONLY) --------
# Real BUG found in an external audit: widgets5 didn't take part in the
# mutual exclusion or in "<set> off" -- it could accidentally coexist with another
# set on HDMI-A-1, and survived a "widgets off p2".

any_widgets5_running() {
    for cls in "${WIDGETS5_CLASSES[@]}"; do
        pgrep -f "kitty --class ${cls} -o" > /dev/null 2>&1 && return 0
    done
    return 1
}

_widgets5_actual_monitor() {
    local ws
    ws=$(cat "$HOME/.config/widgets5/workspace" 2>/dev/null)
    [[ "$ws" =~ ^-?[0-9]+$ ]] || return 1
    hyprctl workspaces -j 2>/dev/null | jq -r --argjson id "$ws" '.[] | select(.id==$id) | .monitor // empty'
}

any_widgets5_running_on() {
    any_widgets5_running || return 1
    [ "$(_widgets5_actual_monitor)" = "$1" ]
}

kill_widgets5() {
    for cls in "${WIDGETS5_CLASSES[@]}"; do
        pgrep -f "kitty --class ${cls} -o" | xargs -r kill 2>/dev/null
    done
}

kill_widgets5_on() {
    any_widgets5_running_on "$1" && kill_widgets5
}

# ---------------------------------------------------------------------------
# close_other_sets_on <monitor> <own_set_number>
# Closes, ON THAT MONITOR ONLY, any instance of the OTHER sets.
# Doesn't touch instances of other sets on OTHER monitors -- that's exactly what
# lets them coexist spread across screens. own_set_number (1-5) is
# excluded.
# ---------------------------------------------------------------------------
close_other_sets_on() {
    local mon="$1" own="$2"
    [ "$own" = "1" ] || { any_widgets1_running_on "$mon" && kill_widgets1_on "$mon"; }
    [ "$own" = "2" ] || { any_widgets2_running_on "$mon" && kill_widgets2_on "$mon"; }
    [ "$own" = "3" ] || { any_widgets3_running_on "$mon" && kill_widgets3_on "$mon"; }
    [ "$own" = "4" ] || { any_widgets4_running_on "$mon" && kill_widgets4_on "$mon"; }
    [ "$own" = "5" ] || { any_widgets5_running_on "$mon" && kill_widgets5_on "$mon"; }
}

# ---------------------------------------------------------------------------
# close_all_sets_on <monitor>
# Closes, ON THAT MONITOR ONLY, ANY of the sets that are there
# (including the one calling the function). Used by "<set> off [p1|p2]" -- you
# want to turn off "whatever you're seeing on this screen", not
# necessarily the set you named in the terminal. Implemented as
# close_other_sets_on with a set number that never matches 1-5.
# ---------------------------------------------------------------------------
close_all_sets_on() {
    close_other_sets_on "$1" "0"
}

# ---------------------------------------------------------------------------
# resolve_off_target_monitor [p1|p2]
# For "<set> off [p1|p2]": explicit p1/p2 -> that screen. No argument
# -> the screen FOCUSED right now (not "all screens" -- that's
# exactly the old behaviour that was removed: a bare "off" only turns off where
# you are). Prints the monitor name to stdout, empty if it
# couldn't be resolved (hyprctl unavailable, etc).
# ---------------------------------------------------------------------------
resolve_off_target_monitor() {
    case "$1" in
        p1) echo "eDP-1"; return 0 ;;
        p2) echo "HDMI-A-1"; return 0 ;;
        "") hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' | head -1 ;;
        *) echo "usage: off [p1|p2]" >&2; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# apply_widget_preset <preset-name> <monitor>
# Applies a SAVED preset of Serpantinum's native widget editor
# (~/.local/state/serpantinum/widgets/presets/<name>.json) to the given
# monitor. There's no native IPC to "apply preset by name" (it only exists
# from the UI, via WidgetSync.applyPreset) -- "reload" IS exposed via
# IPC and re-reads layout.json from disk (confirmed by reading WidgetLoader.qml),
# so: the preset (format {type,x,y,width,height,...}) is transformed into the
# layout.json format (wType,wX,wY,...,unique wId) with jq, written
# directly, and "reload" is requested. No-ops (with a warning) if the preset doesn't exist.
# ---------------------------------------------------------------------------
apply_widget_preset() {
    local name="$1" mon="$2"
    local preset_file="$HOME/.local/state/serpantinum/widgets/presets/${name}.json"
    local layout_file="$HOME/.local/state/serpantinum/widgets/${mon}/layout.json"
    if [ ! -f "$preset_file" ]; then
        echo "warning: preset '$name' doesn't exist (${preset_file}) -- skipped" >&2
        return 0
    fi
    mkdir -p "$(dirname "$layout_file")"
    if ! jq --arg tag "$(echo "$name" | tr -c 'a-zA-Z0-9' '_')" '[.widgets | to_entries[] | .value + {idx: .key} | {
        type: .type,
        wType: .type,
        wVariant: .variant,
        wX: .x,
        wY: .y,
        wWidth: .width,
        wHeight: .height,
        wOpacity: .opacity,
        wRotation: .rotation,
        wImagePath: (.imagePath // ""),
        imagePath: (.imagePath // ""),
        wId: ("w_preset_" + $tag + "_" + (.idx|tostring)),
        stretchWidth: (.stretchWidth // false),
        stretchHeight: (.stretchHeight // false)
    }]' "$preset_file" > "${layout_file}.tmp" 2>/dev/null; then
        echo "warning: couldn't transform preset '$name'" >&2
        rm -f "${layout_file}.tmp"
        return 1
    fi
    mv "${layout_file}.tmp" "$layout_file"
    serpantinum ipc call "widgets-${mon}" reload > /dev/null 2>&1
}
