#!/usr/bin/env bash
# widget / widgets pause|play|off — controls the desktop widgets (clock, lavat)
# pause: freezes them (SIGSTOP, no animations, they stay visible as they were)
# play:  resumes them if paused, or relaunches them if not running
# off:   closes them completely
#
# cava and sptlrx (lyrics) were removed from this set
# -- they were redundant with Serpantinum's NATIVE visualizer/lyrics, which
# are now applied via preset in "p1"/"p2" (see apply_widget_preset in
# widget-opti-common.sh). clock now takes the whole left column
# (it used to share it with sptlrx) and lavat the whole right column (it used to
# share it with cava).

set -u

source "$HOME/scripts/widget-opti-common.sh"

# Serializes ANY invocation of this script (manual, border_colors.py
# reacting to a song change, gamemode_watcher.py, etc). Without this,
# two parallel calls overwrite the same shared state -- and the
# serious case: one may run on_exit (restoring follow_mouse/mouse_move_focuses_
# monitor) while the OTHER is still mid-spawn, bringing back the bug
# of "widgets open where the mouse/focus is". Blocking (not -n): the
# second call simply waits its turn instead of running in parallel.
exec 9>/tmp/widget-ctl.lock
flock 9

COLORS_FILE="/tmp/widget-colors.json"
GLOW_STATE_FILE="$HOME/.local/state/widget-glow"
# persistent on/off preference: if it says "off", neither this script nor
# widget_visibility.py reopen the widgets until a "widgets play"
POWER_STATE_FILE="$HOME/.local/state/widget-power"
# "widgets opti on|off" -- 30fps (on) vs 60fps (off) for THIS set's lavat.
# See widget-opti-common.sh. Persists (survives restart), independent from
# opti-ctl.sh's global "opti" (that one tunes blur/taskbar, not fps).
OPTI_STATE_FILE="$HOME/.local/state/widget-opti"
mkdir -p "$(dirname "$GLOW_STATE_FILE")"

BASE_CLASSES=(widget-clock widget-lavat)
# clock takes the whole left column, lavat the whole right column (see
# the note above -- they no longer share with sptlrx/cava). Each one's "move"
# still comes from windowrules.lua (fixed corner); only the size is
# re-registered live here.
CLOCK_SIZE=("(monitor_w - 5) / 2" "monitor_h")
LAVAT_SIZE=("(monitor_w - 5) / 2" "monitor_h")
hyprctl repl "hl.window_rule({ match = { class = \"^(widget-clock)\$\" }, size = { \"${CLOCK_SIZE[0]}\", \"${CLOCK_SIZE[1]}\" } })" > /dev/null 2>&1
hyprctl repl "hl.window_rule({ match = { class = \"^(widget-clock-ghost)\$\" }, size = { \"${CLOCK_SIZE[0]}\", \"${CLOCK_SIZE[1]}\" } })" > /dev/null 2>&1
hyprctl repl "hl.window_rule({ match = { class = \"^(widget-lavat)\$\" }, size = { \"${LAVAT_SIZE[0]}\", \"${LAVAT_SIZE[1]}\" } })" > /dev/null 2>&1

# Mop-up: cava/sptlrx (+ cava ghost) were RETIRED from this set -- if
# any was still running from before this change, kill it here. Without this
# no future action would touch them (they're no longer part of CLASSES).
for _retired in widget-sptlrx widget-cava widget-cava-ghost; do
    _stale_pid=$(pgrep -f "kitty --class ${_retired} -o" | head -1)
    [ -n "$_stale_pid" ] && kill "$_stale_pid" 2>/dev/null
done

GHOST_CLASSES=(widget-clock)  # lavat has no ghost (lighter)

glow_state() {
    if [ -f "$GLOW_STATE_FILE" ]; then
        cat "$GLOW_STATE_FILE"
    else
        echo "on"
    fi
}

gamemode_active() {
    [ "$(caelestia shell gameMode isEnabled 2>/dev/null)" = "true" ]
}

if [ "$(glow_state)" = "off" ] || gamemode_active; then
    # with gamemode on the ghosts stay suspended even if the
    # glow preference is still "on" (gamemode_watcher.py removes/restores them)
    GHOSTS_ENABLED=0
    CLASSES=("${BASE_CLASSES[@]}")
else
    GHOSTS_ENABLED=1
    CLASSES=("${BASE_CLASSES[@]}")
    for _b in "${GHOST_CLASSES[@]}"; do
        CLASSES+=("${_b}-ghost")
    done
fi

# Current song colors (if they exist), falling back to the originals.
primary="cfbfeb"
tertiary="ffdcf0"
if [ -f "$COLORS_FILE" ]; then
    p=$(jq -r '.primary // empty' "$COLORS_FILE" 2>/dev/null)
    t=$(jq -r '.tertiary // empty' "$COLORS_FILE" 2>/dev/null)
    [ -n "$p" ] && primary="$p"
    [ -n "$t" ] && tertiary="$t"
fi

# app_for: the real app command for the BASE class (without -ghost)
app_for() {
    case "$1" in
        widget-clock)  echo "clock-rs -c '#${primary}' -s -t" ;;
        widget-lavat)  echo "lavat -g -c ${primary} -k ${tertiary} -b 6 -s 3" ;;
    esac
}

# kitty_opts_for: extra kitty options ONLY for lavat (continuous
# animation) -- caps kitty's repaint_delay to the right fps per
# "widgets opti on|off" (clock isn't a continuous animation, untouched).
kitty_opts_for() {
    case "$1" in
        widget-lavat) echo "-o repaint_delay=$(opti_kitty_repaint_delay "$OPTI_STATE_FILE")" ;;
        *) echo "" ;;
    esac
}

# cmd_for: full kitty command for a class, base or "-ghost"
cmd_for() {
    local cls="$1"
    local base="${cls%-ghost}"
    echo "kitty --class ${cls} -o background_opacity=0 -o window_padding_width=0 -o confirm_os_window_close=0 $(kitty_opts_for "$base") $(app_for "$base")"
}

find_pid() {
    # the " -o" at the end keeps "widget-clock" from also matching "widget-clock-ghost"
    pgrep -f "kitty --class $1 -o" | head -1
}

# cleanup: if a base class shouldn't have a ghost anymore but one is still
# running from before, kill it. Normal actions (restart/play/...)
# only look at the classes EXPECTED right now, so an "orphan" ghost
# would never be touched otherwise.
for _b in "${BASE_CLASSES[@]}"; do
    if [[ ! " ${GHOST_CLASSES[*]} " == *" ${_b} "* ]]; then
        stale_pid=$(find_pid "${_b}-ghost")
        [ -n "$stale_pid" ] && kill "$stale_pid" 2>/dev/null
    fi
done

HOME_MONITOR_FILE="/tmp/widget-home-monitor"

# Temporarily turns off 2 Hyprland options while we relocate widgets, WITHOUT
# moving the physical cursor a single pixel (key to not affecting gaming):
#   - input:follow_mouse            -> window focus follows the mouse
#   - misc:mouse_move_focuses_monitor -> just CROSSING the mouse to another
#     monitor makes that monitor the active one (no click)
# Without this, if the mouse sits on the other screen, any
# micro-event during the spawn gives the active monitor back to that screen
# and the widget ends up opening there. Always restored in on_exit.
disable_follow_mouse() {
    hyprctl repl 'hl.config({ input = { follow_mouse = 0 }, misc = { mouse_move_focuses_monitor = false } })' > /dev/null 2>&1
}
restore_follow_mouse() {
    hyprctl repl 'hl.config({ input = { follow_mouse = 1 }, misc = { mouse_move_focuses_monitor = true } })' > /dev/null 2>&1
}

# focuses the monitor where the widgets lived before killing them, so that
# when relaunching them (restart/play) they don't end up opening on the screen you
# happen to have focused at that moment for something else

focus_home_monitor() {
    if [ -f "$HOME_MONITOR_FILE" ]; then
        local home
        home=$(cat "$HOME_MONITOR_FILE")
        if [ -n "$home" ]; then
            disable_follow_mouse
            hyprctl dispatch "hl.dsp.focus({ monitor = \"${home}\" })" > /dev/null 2>&1
            sleep 0.15
        fi
    fi
}

# Pins the class to a specific monitor by registering a "live" window_rule
# (hyprctl repl) with a "monitor" field -- Hyprland already uses this same field in
# STATIC rules in windowrules.lua (e.g. .exe files go to PRIMARY_MONITOR regardless
# of where focus is). This makes the window open on the right
# monitor WITHOUT DEPENDING on the current focus at all: not on nobody moving the
# mouse, nor on you clicking on the other screen right at that moment
# (normal when working with several windows). The focus_home_monitor
# below stays only as a fallback, it's no longer what does the real work.
pin_to_home_monitor() {
    local cls="$1"
    if [ -f "$HOME_MONITOR_FILE" ]; then
        local home
        home=$(cat "$HOME_MONITOR_FILE")
        if [ -n "$home" ]; then
            hyprctl repl "hl.window_rule({ match = { class = \"^(${cls})\$\" }, monitor = \"${home}\" })" > /dev/null 2>&1
        fi
    fi
}

# Launches a widget and WAITS for the window to actually appear before returning.
spawn_widget() {
    local cls="$1"
    pin_to_home_monitor "$cls"
    focus_home_monitor
    # 9>&- : close the lock fd BEFORE kitty inherits it. kitty keeps
    # running forever, so if it inherits the open fd, the lock stays
    # "held" by that kitty forever and no future invocation of
    # this script (not even itself) ever gets it again -- total deadlock.
    setsid bash -c "$(cmd_for "$cls")" 9>&- < /dev/null > /dev/null 2>&1 &
    for _ in $(seq 1 30); do
        if hyprctl clients -j 2>/dev/null | jq -e --arg c "$cls" 'any(.[]; .class == $c)' > /dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
}

# launches the "-ghost" of each base that's running and doesn't have a ghost yet.
# Uses the same fixed home as everything else (focus_home_monitor), not "where
# the base is now" -- that added a second source of truth for the monitor
# and was another way of ending up opening in the wrong place.
spawn_missing_ghosts() {
    for base in "${GHOST_CLASSES[@]}"; do
        base_pid=$(find_pid "$base")
        ghost_pid=$(find_pid "${base}-ghost")
        if [ -n "$base_pid" ] && [ -z "$ghost_pid" ]; then
            spawn_widget "${base}-ghost"
        fi
    done
}

kill_all_ghosts() {
    for base in "${GHOST_CLASSES[@]}"; do
        ghost_pid=$(find_pid "${base}-ghost")
        [ -n "$ghost_pid" ] && kill "$ghost_pid"
    done
}

COOLDOWN_FILE="/tmp/widget-ctl-cooldown"
mark_cooldown() { touch "$COOLDOWN_FILE"; }

on_exit() {
    local status=$?
    restore_follow_mouse
    mark_cooldown
    # if it was run by hand in an interactive terminal and succeeded, close
    # THAT terminal (killing the shell that contains it). Doesn't apply when
    # invoked by the background watchers (stdout isn't a tty there).
    if [ "$status" -eq 0 ] && [ -t 1 ]; then
        kill -TERM "$PPID" 2>/dev/null
    fi
}
trap on_exit EXIT
mark_cooldown  # mark right at the start, so the watcher doesn't compete during the wait

# Mutual exclusion PER SCREEN: when starting THIS set on a given monitor,
# closes any other set on THAT SAME monitor (not on the other one --
# so "widgets p1" + "widgets2 p2" can coexist). Directly by process (NOT
# invoking the other ctl scripts) so we don't fight over the same flock --
# deadlock otherwise (shared functions in widget-opti-common.sh).
close_other_sets_here() {
    local mon="$1"
    [ -n "$mon" ] && close_other_sets_on "$mon" 1
}

# widgets opti on|off -- see widget-opti-common.sh. Restarts ONLY lavat --
# the only continuous animation of this set (clock isn't an animation, it's not
# touched). Doesn't restart the whole set.
apply_opti() {
    local val="$1"
    case "$val" in
        on|off) ;;
        *) echo "usage: widgets opti on|off" >&2; return 1 ;;
    esac
    echo "$val" > "$OPTI_STATE_FILE"
    local fps
    fps=$(opti_fps "$OPTI_STATE_FILE")

    local fps_classes=(widget-lavat)
    local was_running=()
    for cls in "${fps_classes[@]}"; do
        pid=$(find_pid "$cls")
        if [ -n "$pid" ]; then
            was_running+=("$cls")
            kill "$pid"
        fi
    done
    for _ in $(seq 1 20); do
        alive=0
        for cls in "${was_running[@]}"; do
            [ -n "$(find_pid "$cls")" ] && alive=1
        done
        [ "$alive" -eq 0 ] && break
        mark_cooldown
        sleep 0.1
    done
    # Respawn based on the state EXPECTED right now (power on + present
    # in $CLASSES), not on the "was_running" snapshot taken before killing: if
    # another concurrent trigger (song change, gamemode flapping) already
    # revived or killed something again while we waited, was_running could
    # be stale and leave the set silently off (real bug seen
    # in testing: fast gamemode ON/OFF racing with this restart).
    if [ "$(cat "$POWER_STATE_FILE" 2>/dev/null)" = "on" ]; then
        for cls in "${fps_classes[@]}"; do
            [[ " ${CLASSES[*]} " == *" ${cls} "* ]] || continue
            [ -n "$(find_pid "$cls")" ] && continue
            spawn_widget "$cls"
        done
    fi
    echo "widgets opti: $val (lavat a ${fps}fps)"
}

action="${1:-}"

case "$action" in
    pause)
        for cls in "${CLASSES[@]}"; do
            pid=$(find_pid "$cls")
            [ -n "$pid" ] && kill -STOP "$pid"
        done
        echo "widgets pausados"
        ;;
    play)
        _play_target_mon=$(cat "$HOME_MONITOR_FILE" 2>/dev/null)
        [ -n "$_play_target_mon" ] || _play_target_mon=$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused==true) | .name')
        close_other_sets_here "$_play_target_mon"
        echo "on" > "$POWER_STATE_FILE"
        need_spawn=0
        for cls in "${CLASSES[@]}"; do
            [ -z "$(find_pid "$cls")" ] && need_spawn=1
        done
        for cls in "${CLASSES[@]}"; do
            pid=$(find_pid "$cls")
            if [ -n "$pid" ]; then
                kill -CONT "$pid"
            else
                spawn_widget "$cls"
            fi
        done
        echo "widgets activos"
        ;;
    hide)
        # like 'off' but WITHOUT touching the power preference: used by the
        # watchers to hide/show temporarily (app open, drift, etc.)
        for cls in "${CLASSES[@]}"; do
            pid=$(find_pid "$cls")
            [ -n "$pid" ] && kill "$pid"
        done
        echo "widgets ocultados"
        ;;
    off)
        # "widgets off" (no argument) turns off whatever is active on
        # the screen FOCUSED right now -- no matter whether it ended up being
        # widgets, widgets2, widgets3 or widgets4 (several run "behind
        # the apps" and it's easy to forget they're still on there).
        # "widgets off p1" / "widgets off p2" targets a specific screen
        # regardless of which one is focused. Replaces the old "off turns off this WHOLE
        # set on ALL screens" -- that model had no way
        # to turn off "what I see now" without risking killing an instance
        # of ANOTHER set on a screen you didn't even touch.
        target_mon=$(resolve_off_target_monitor "${2:-}") || exit 1
        if [ -z "$target_mon" ]; then
            echo "ERROR: couldn't resolve the focused screen (hyprctl/jq failed)." >&2
            exit 1
        fi
        if any_widgets1_running_on "$target_mon"; then
            echo "off" > "$POWER_STATE_FILE"
        fi
        # close_all_sets_on already covers the mop-up for this set (kill_widgets1
        # kills ALL classes by pattern, not just the tracked pid -- see
        # widget-opti-common.sh) and for the other 3 on that same screen.
        close_all_sets_on "$target_mon"
        # "widgets off" (and "off p1"/"off p2") also
        # restores the native "Default" preset on that screen -- same pattern
        # widgets5 already uses.
        apply_widget_preset "Default" "$target_mon"
        echo "closed whatever was on $target_mon"
        ;;
    restart)
        # closes and relaunches the ones that WERE running, with the current colors
        # (used when the song changes, so paused/off ones aren't reopened)
        was_running=()
        for cls in "${CLASSES[@]}"; do
            pid=$(find_pid "$cls")
            if [ -n "$pid" ]; then
                was_running+=("$cls")
                kill "$pid"
            fi
        done
        # wait for them to really die before relaunching
        for _ in $(seq 1 20); do
            alive=0
            for cls in "${was_running[@]}"; do
                [ -n "$(find_pid "$cls")" ] && alive=1
            done
            [ "$alive" -eq 0 ] && break
            mark_cooldown
            sleep 0.1
        done
        for cls in "${was_running[@]}"; do
            # if another watcher already relaunched it while we waited, don't duplicate
            [ -n "$(find_pid "$cls")" ] && continue
            spawn_widget "$cls"
        done
        # "was_running" only revives what WAS already running -- if the change
        # that triggered the restart was precisely cava coming back from cmatrix (now
        # it DOES get a ghost), its ghost was never running and wouldn't be relaunched
        # by itself. Restore any ghost that now applies.
        [ "$GHOSTS_ENABLED" -eq 1 ] && spawn_missing_ghosts
        echo "widgets reiniciados"
        ;;
    any-running)
        found=0
        for cls in "${CLASSES[@]}"; do
            [ -n "$(find_pid "$cls")" ] && found=1
        done
        [ "$found" -eq 1 ] && echo "yes" || echo "no"
        ;;
    p1|p2)
        # p1 = laptop (eDP-1), p2 = external HDMI (HDMI-A-1)
        case "$action" in
            p1) target_monitor="eDP-1" ;;
            p2) target_monitor="HDMI-A-1" ;;
        esac
        close_other_sets_here "$target_monitor"
        for cls in "${CLASSES[@]}"; do
            pid=$(find_pid "$cls")
            [ -n "$pid" ] && kill "$pid"
        done
        for _ in $(seq 1 20); do
            alive=0
            for cls in "${CLASSES[@]}"; do
                [ -n "$(find_pid "$cls")" ] && alive=1
            done
            [ "$alive" -eq 0 ] && break
            mark_cooldown
            sleep 0.1
        done
        echo -n "$target_monitor" > /tmp/widget-home-monitor
        for cls in "${CLASSES[@]}"; do
            # if another watcher already relaunched it while we waited, don't duplicate
            [ -n "$(find_pid "$cls")" ] && continue
            spawn_widget "$cls"
        done
        # "widgets p1"/"widgets p2" (and therefore also
        # SUPER+SHIFT+W when turning on, see widget-preset-toggle.sh) apply the
        # native Serpantinum editor preset on that screen
        # (native visualizer+lyrics, replacing the cava/sptlrx that were
        # removed from this kitty set). Uses the
        # "Music" presets: a different preset name per monitor because
        # the laptop (p1) and HDMI (p2) layouts aren't the same.
        case "$target_monitor" in
            eDP-1)     apply_widget_preset "Music laptop" "$target_monitor" ;;
            HDMI-A-1)  apply_widget_preset "Music HDMI" "$target_monitor" ;;
            *)         apply_widget_preset "widgets" "$target_monitor" ;;
        esac
        # combined form: "widgets p1 opti on" / "widgets p2 opti off"
        if [ "${2:-}" = "opti" ] && [ -n "${3:-}" ]; then
            apply_opti "$3" > /dev/null
            echo "widgets movidos a $target_monitor, opti $3"
        else
            echo "widgets movidos a $target_monitor"
        fi
        ;;
    glow)
        sub="${2:-}"
        case "$sub" in
            on)
                echo "on" > "$GLOW_STATE_FILE"
                spawn_missing_ghosts
                echo "glow on"
                ;;
            off)
                echo "off" > "$GLOW_STATE_FILE"
                kill_all_ghosts
                echo "glow off"
                ;;
            *)
                echo "usage: widget glow on|off" >&2
                exit 1
                ;;
        esac
        ;;
    ghosts-suspend)
        # hides the ghosts WITHOUT touching the saved glow preference
        # (for gamemode: when it ends things must go back to how they were)
        kill_all_ghosts
        echo "ghosts suspendidos"
        ;;
    ghosts-restore)
        # shows them again only if the glow preference is still "on"
        if [ "$(glow_state)" = "on" ]; then
            spawn_missing_ghosts
        fi
        echo "ghosts restaurados (si correspondia)"
        ;;
    opti)
        apply_opti "${2:-}"
        ;;
    status)
        running=0
        for cls in "${CLASSES[@]}"; do
            [ -n "$(find_pid "$cls")" ] && running=1
        done
        home=$(cat /tmp/widget-home-monitor 2>/dev/null)
        opti_val=$(opti_state "$OPTI_STATE_FILE")
        fps=$(opti_fps "$OPTI_STATE_FILE")
        echo "widgets:     $([ "$running" -eq 1 ] && echo ON || echo OFF)"
        echo "monitor:     ${home:-(not set, follows focus)}"
        echo "glow:        $(glow_state)"
        echo "opti:        $opti_val"
        echo "target FPS:  $fps (lavat)"
        ;;
    help)
        cat <<'EOF'
usage: widgets <command>
  play                -- enable (relaunch if needed)
  pause               -- freeze without closing
  off                 -- close whatever is active on the screen FOCUSED
                         right now -- whatever the set (widgets/2/3/4)
  off p1 | off p2     -- same, but targets that specific screen
  restart             -- relaunch the ones that were already running
  any-running         -- yes/no
  p1 | p2             -- move to eDP-1 / HDMI-A-1
  p1 opti on|off      -- combined: move monitor AND set opti
  p2 opti on|off
  glow on|off         -- turn the "ghosts" on/off
  opti on             -- ~30 FPS on lavat (performance mode)
  opti off            -- ~60 FPS on lavat (full quality, default)
  status              -- current state
  help                -- this help
Note: "opti" here is PER SET (lavat fps). Different from the global "opti"
(bare 'opti' command), which tunes blur/taskbar for all of Hyprland.
EOF
        ;;
    *)
        echo "usage: widget pause|play|off|restart|any-running|p1|p2|glow on|off|opti on|off|status|help" >&2
        exit 1
        ;;
esac
