#!/usr/bin/env bash
# astrax-safe: safe mode. Turns off the things most likely to misbehave, in one command,
# and puts everything back with `off`.
#
#   astrax-safe on [-y]    patched cursor plugin off at the next login, cursor-style normal,
#                          opti on (fewer blur passes, taskbar watcher stopped)
#   astrax-safe off [-y]   undo exactly what `on` changed
#   astrax-safe status     is it on, and what it changed
#
# Works from a TTY (Ctrl+Alt+F3) when Hyprland or Quickshell are broken: it never needs the
# compositor, it only writes files; live changes (hyprctl) are tried and allowed to fail.
# It asks first; -y skips the question (required when stdin is not a terminal).
# Override for tests: ASTRAX_STATE_DIR, HOME.
set -u

STATE="${ASTRAX_STATE_DIR:-$HOME/.local/state/astrax}"
FLAG="$STATE/safe"
TRAIL_DISABLED="$HOME/.cache/hypr-trail/disabled"
OPTI_STATE="$HOME/.local/state/opti"

confirm() {
    [ "${YES:-}" = 1 ] && return 0
    [ -t 0 ] || { echo "not a terminal: pass -y to confirm" >&2; return 1; }
    read -rp "$1 [y/N] " r; [[ "$r" =~ ^[yYsS]$ ]]
}
getv() { sed -n "s/^$1=//p" "$FLAG" 2>/dev/null | head -n1; }
run() { [ -x "$HOME/scripts/$1" ] && "$HOME/scripts/$1" "${@:2}" >/dev/null 2>&1; }

cmd="${1:-status}"; shift || true
[ "${1:-}" = "-y" ] && YES=1

case "$cmd" in
    status)
        if [ -f "$FLAG" ]; then
            echo "safe mode: ON"
            sed 's/^/  /' "$FLAG"
        else
            echo "safe mode: off"
        fi ;;
    on)
        [ -f "$FLAG" ] && { echo "already on (astrax-safe off to undo)"; exit 0; }
        echo "Safe mode will:"
        echo "  - stop loading the patched cursor plugin at the next login (stock plugin instead)"
        echo "  - switch the cursor to the classic 'normal' style"
        echo "  - turn opti on (fewer blur passes)"
        confirm "Continue?" || { echo "cancelled, nothing changed"; exit 1; }
        mkdir -p "$STATE" "$(dirname "$TRAIL_DISABLED")"
        prev_style="$("$HOME/scripts/cursor-style.sh" get 2>/dev/null || echo astrax)"
        prev_opti="$(cat "$OPTI_STATE" 2>/dev/null || echo off)"
        had_disabled=0; [ -e "$TRAIL_DISABLED" ] && had_disabled=1
        printf 'cursor_style=%s\nopti=%s\ntrail_disabled_before=%s\nsince=%s\n' \
            "$prev_style" "$prev_opti" "$had_disabled" "$(date +%s)" > "$FLAG"
        touch "$TRAIL_DISABLED"
        run cursor-style.sh normal
        run opti-ctl.sh on
        echo "safe mode ON. Log out and back in to finish; undo with: astrax-safe off" ;;
    off)
        [ -f "$FLAG" ] || { echo "safe mode is not on"; exit 0; }
        confirm "Undo safe mode (restore cursor style $(getv cursor_style), opti $(getv opti))?" || { echo "cancelled"; exit 1; }
        [ "$(getv trail_disabled_before)" = 0 ] && rm -f "$TRAIL_DISABLED"
        run cursor-style.sh "$(getv cursor_style)"
        [ "$(getv opti)" = on ] || run opti-ctl.sh off
        rm -f "$FLAG"
        echo "safe mode OFF. Log out and back in to load the patched cursor plugin again." ;;
    *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
