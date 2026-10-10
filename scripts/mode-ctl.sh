#!/usr/bin/env bash
# mode <music|study|gaming|privacy|private|code|coding|sleep|help> -- quick
# profiles that open/close the usual apps for each context. Reuses
# widget-ctl.sh/widget2-ctl.sh, the shells' game modes, wpctl, and the same
# uwsm/kitty binds.lua uses. See 'mode help' for details.

set -u

SCRIPTS_DIR="$HOME/scripts"
LAUNCH_PREFIX=(uwsm app --) # same prefix as launchPrefix in binds.lua

ALREADY_OPEN=()
MISSING=()     # programs a mode wanted to open but that aren't installed

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Temporary kitty window (closes by itself after 10s) listing what was
# already open. A single notification even with several apps.
notify_already_open() {
    [ "${#ALREADY_OPEN[@]}" -eq 0 ] && return 0
    setsid kitty --class mode-notify -o font_size=28 -o confirm_os_window_close=0 \
        bash "$SCRIPTS_DIR/mode-notify.sh" "${ALREADY_OPEN[@]}" \
        < /dev/null > /dev/null 2>&1 &
}

# Reports what couldn't be opened because it isn't installed (stderr + notification).
notify_missing() {
    [ "${#MISSING[@]}" -eq 0 ] && return 0
    echo "mode: not installed, skipped: ${MISSING[*]}" >&2
    notify-send "mode" "Not installed, skipped: ${MISSING[*]}" 2>/dev/null || true
}

set_volume() {
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$1%" > /dev/null 2>&1
}

# Already running by process name (exact comm, regardless of a
# mapped window -- Spotify/Brave can stay in the tray without a window).
proc_running() {
    pgrep -x "$1" > /dev/null 2>&1
}

# Normal Brave and Brave Origin are DIFFERENT binaries but both are called
# literally "brave" (identical comm: /opt/brave-bin/brave vs
# /opt/brave.com/brave-origin-nightly/brave) -- "pgrep -x brave" can't
# tell them apart. That's why these match on the full executable path.
brave_normal_running() {
    pgrep -f "^/opt/brave-bin/brave " > /dev/null 2>&1
}
brave_origin_running() {
    pgrep -f "^/opt/brave\.com/brave-origin-nightly/brave " > /dev/null 2>&1
}

# Already running by Hyprland window class (for apps that don't leave a
# clear process comm, like flatpaks).
class_running() {
    hyprctl clients -j 2>/dev/null | jq -e --arg c "$1" '.[] | select(.class==$c)' > /dev/null 2>&1
}

launch() {
    setsid "${LAUNCH_PREFIX[@]}" "$@" < /dev/null > /dev/null 2>&1 &
}

# open_app <already-running:0|1> <name-for-the-notice> <command...>
open_app() {
    local running="$1" label="$2"
    shift 2
    if [ "$running" -eq 1 ]; then
        ALREADY_OPEN+=("$label")
    elif ! command -v "$1" > /dev/null 2>&1; then
        MISSING+=("$label")
    else
        launch "$@"
    fi
}

sober_installed() {
    command -v flatpak > /dev/null 2>&1 && flatpak info org.vinegarhq.Sober > /dev/null 2>&1
}

open_spotify() {
    if proc_running spotify; then open_app 1 "Spotify"; else open_app 0 "Spotify" spotify; fi
}
open_brave_normal() {
    if brave_normal_running; then open_app 1 "Brave"; else open_app 0 "Brave" brave; fi
}
open_brave_origin() {
    if brave_origin_running; then open_app 1 "Brave Origin"; else open_app 0 "Brave Origin" brave-origin-nightly; fi
}
open_chatgpt() {
    if class_running "Chatgpt"; then open_app 1 "ChatGPT"; else open_app 0 "ChatGPT" chatgpt; fi
}
open_claude() {
    if class_running "com.anthropic.Claude"; then open_app 1 "Claude"; else open_app 0 "Claude" claude-desktop; fi
}

open_roblox() {
    if proc_running sober || class_running "org.vinegarhq.Sober"; then
        ALREADY_OPEN+=("Roblox")
    elif ! sober_installed; then
        MISSING+=("Roblox (Sober flatpak)")
    else
        setsid flatpak run org.vinegarhq.Sober < /dev/null > /dev/null 2>&1 &
    fi
}

# widgets/widgets2 are already idempotent (widget-ctl.sh "play" doesn't duplicate),
# but widget-ctl.sh closes the terminal it's invoked from by hand
# (on_exit kills $PPID if stdout is a tty) -- that's why it's ALWAYS
# called with stdout redirected, never inheriting "mode"'s tty.
open_widgets() {
    if [ "$("$SCRIPTS_DIR/widget-ctl.sh" any-running < /dev/null 2>/dev/null)" = "yes" ]; then
        ALREADY_OPEN+=("Widgets")
    else
        "$SCRIPTS_DIR/widget-ctl.sh" play < /dev/null > /dev/null
    fi
}

open_widgets2() {
    if [ "$("$SCRIPTS_DIR/widget2-ctl.sh" any-running < /dev/null 2>/dev/null)" = "yes" ]; then
        ALREADY_OPEN+=("Widgets2")
    else
        "$SCRIPTS_DIR/widget2-ctl.sh" play < /dev/null > /dev/null
    fi
}

# Normal widgets, pinned to the HDMI monitor (HDMI-A-1, alias "p2" of
# widget-ctl.sh itself -- the monitor name is never hardcoded here).
open_widgets_hdmi() {
    local already=0
    if [ "$("$SCRIPTS_DIR/widget-ctl.sh" any-running < /dev/null 2>/dev/null)" = "yes" ]; then
        local home_monitor=""
        [ -f /tmp/widget-home-monitor ] && home_monitor=$(cat /tmp/widget-home-monitor)
        [ "$home_monitor" = "HDMI-A-1" ] && already=1
    fi
    if [ "$already" -eq 1 ]; then
        ALREADY_OPEN+=("Widgets (HDMI)")
    else
        "$SCRIPTS_DIR/widget-ctl.sh" p2 < /dev/null > /dev/null
    fi
}

# Closes normal app windows, protecting: any terminal
# (class "kitty" -- so it never risks closing the one running
# "mode" instead of another), the desktop widgets and Caelestia/quickshell.
# Uses this Hyprland fork's own dispatcher (hl.dsp.window.close),
# not the classic "hyprctl dispatch closewindow" -- that doesn't exist here (see
# binds.lua / focus_or_launch, which uses the same hl.dsp.*). IMPORTANT: the
# "window" selector does NOT accept a text address (tested: silent no-op
# in both focus and close) -- it needs the object returned by
# hl.get_windows({ class = ... }), like focus_or_launch does. So it
# closes by class, asking as many times as there are windows of that class
# (each close removes one from the array get_windows returns).
close_normal_apps() {
    while IFS=$'\t' read -r class count; do
        [ -z "$class" ] && continue
        case "$class" in
            widget-*|show-hz|mode-notify|kitty) continue ;;
        esac
        local i
        for ((i = 0; i < count; i++)); do
            hyprctl dispatch "hl.dsp.window.close({ window = hl.get_windows({ class = '${class}' })[1] })" > /dev/null 2>&1
        done
    done < <(hyprctl clients -j 2>/dev/null | jq -r 'group_by(.class) | .[] | "\(.[0].class)\t\(length)"')
}

# ---------------------------------------------------------------------------
# Modes -- each one is an "apply_*" function that only opens/enables things.
# Closing normal apps (study/gaming) and the volume are resolved once
# in the dispatch so modes can be combined in the
# same call (see below) without stepping on each other.
# ---------------------------------------------------------------------------

TARGET_VOLUME=""

apply_music() {
    local extra="$1"
    open_spotify
    TARGET_VOLUME=70
    case "$extra" in
        widgets)  open_widgets ;;
        widgets2) open_widgets2 ;;
    esac
}

apply_study() {
    open_brave_normal
    TARGET_VOLUME=0
}

apply_gaming() {
    open_roblox
    # each shell has its own "game mode"; use the one that is actually running
    if [ "$(bash "$SCRIPTS_DIR/active-shell.sh")" = "caelestia" ]; then
        caelestia shell gameMode enable > /dev/null 2>&1 ||
            echo "mode: couldn't enable Caelestia's gameMode" >&2
    else
        # Serpantinum: fewer blur passes + taskbar watcher off (see opti-ctl.sh)
        bash "$SCRIPTS_DIR/opti-ctl.sh" on > /dev/null 2>&1 ||
            echo "mode: couldn't enable opti" >&2
    fi
}

apply_privacy() {
    open_brave_origin
    TARGET_VOLUME=0
}

apply_code() {
    open_chatgpt
    open_claude
}

apply_sleep() {
    open_widgets_hdmi
}

mode_help() {
    cat <<'EOF'
usage: mode <mode> [mode2 mode3 ...] [option]

modes (can be combined in a single call, e.g. "mode gaming music"
or "mode code study"):
    music                 opens Spotify, volume 70%. Doesn't open widgets.
        music widgets     same as above + opens the normal widgets
        music widgets2    same as above + opens widgets2

    study                 closes the open normal apps (without touching
                          the "mode" terminal or the rice), opens Brave
                          with the normal profile, volume 0%

    gaming                closes the open normal apps, opens Roblox
                          (Sober) and enables the running shell's game
                          mode (Caelestia gameMode, or "opti on")

    privacy               opens Brave Origin, volume 0% (just a profile:
                          it adds no privacy protection by itself)
    private               alias of "privacy"

    code                  opens ChatGPT and Claude
    coding                alias of "code"

    sleep                 opens the normal widgets (never widgets2) on
                          the HDMI monitor (the real sleep mode is
                          CTRL+SUPER+N / sleep-ctl.sh)

    help                  this help (also shown without arguments;
                          if combined with other modes, this one wins)

when combining modes: closing normal apps (from "study"/"gaming") happens
only once, before opening anything -- so "mode code gaming" doesn't close
ChatGPT/Claude right after opening them. If more than one combined mode sets the volume,
the rightmost one wins (e.g. "mode study music" ends at 70%).

if something a mode wants to open is already running, no copy is opened:
an "ALREADY OPEN" notice shows up in a terminal
that closes by itself after 10 seconds (a single combined notification
even if several modes were requested).
EOF
}

usage_error() {
    echo "error: $1" >&2
    echo "valid modes: music, study, gaming, privacy (alias: private), code (alias: coding), sleep, help" >&2
    echo "'music' accepts an optional extra:" >&2
    echo "    mode music" >&2
    echo "    mode music widgets" >&2
    echo "    mode music widgets2" >&2
    echo "run 'mode help' for more details" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

requested=()
music_extra=""

for arg in "$@"; do
    case "$arg" in
        music|study|gaming|privacy|private|code|coding|sleep|help)
            requested+=("$arg")
            ;;
        widgets|widgets2)
            music_extra="$arg"
            ;;
        *)
            usage_error "unknown argument: '$arg'"
            ;;
    esac
done

if [ "${#requested[@]}" -eq 0 ]; then
    mode_help
    exit 0
fi

for m in "${requested[@]}"; do
    [ "$m" = "help" ] && { mode_help; exit 0; }
done

if [ -n "$music_extra" ]; then
    has_music=0
    for m in "${requested[@]}"; do
        [ "$m" = "music" ] && has_music=1
    done
    [ "$has_music" -eq 0 ] && usage_error "'$music_extra' only makes sense together with 'music'"
fi

# normalizes aliases and dedupes preserving the requested order
declare -A seen
modes=()
for m in "${requested[@]}"; do
    case "$m" in
        private) m="privacy" ;;
        coding)  m="code" ;;
    esac
    [ -n "${seen[$m]:-}" ] && continue
    seen[$m]=1
    modes+=("$m")
done

# Before closing anything: the modes that close your apps must be able to open
# their replacement, otherwise you'd just lose your windows.
for m in "${modes[@]}"; do
    case "$m" in
        study)  command -v brave > /dev/null 2>&1 || { echo "mode study: brave isn't installed -- nothing was closed" >&2; exit 1; } ;;
        gaming) sober_installed || { echo "mode gaming: the Sober flatpak (org.vinegarhq.Sober) isn't installed -- nothing was closed" >&2; exit 1; } ;;
    esac
done

for m in "${modes[@]}"; do
    case "$m" in
        study|gaming) close_normal_apps; break ;;
    esac
done

for m in "${modes[@]}"; do
    case "$m" in
        music)   apply_music "$music_extra" ;;
        study)   apply_study ;;
        gaming)  apply_gaming ;;
        privacy) apply_privacy ;;
        code)    apply_code ;;
        sleep)   apply_sleep ;;
    esac
done

[ -n "$TARGET_VOLUME" ] && set_volume "$TARGET_VOLUME"
notify_already_open
notify_missing
