#!/usr/bin/env bash
# sharp-transparent on|off|toggle|status|reapply
#
# WHAT "on" DOES: sharp corners (rounding 0) and transparency WITHOUT blur behind
# (blur.enabled = false; the Dynamic Island keeps its Liquid Glass blur unless opti is on). The transparency itself (active/inactive_opacity)
# already comes from decorations.lua and isn't touched -- only the blur is turned off so
# you see "through" instead of a backdrop blur.
#
# WHAT IT DOESN'T TOUCH: gaps, shadows, animations, blur passes/size (reused by "opti"
# via caelestia's gameMode), opacity values.
#
# State in ~/.local/state/sharp-transparent. Re-applied on every
# "hyprctl reload"/startup via a hook in config/autostart.lua (same as opti),
# because a reload brings everything back to what decorations.lua says.

set -u

STATE_FILE="$HOME/.local/state/sharp-transparent"
DECOR="$HOME/.config/hypr/config/decorations.lua"

mkdir -p "$(dirname "$STATE_FILE")"

state() { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo off; }

rounding_default() {
    sed -n 's/.*rounding[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$DECOR" 2>/dev/null | head -1
}

apply_on() {
    hyprctl repl 'hl.config({ decoration = { rounding = 0 } }); if astraxIslandBlurMode then astraxIslandBlurMode(true) else hl.config({ decoration = { blur = { enabled = false } } }) end' >/dev/null 2>&1
}

apply_off() {
    local r
    r="$(rounding_default)"; [ -n "$r" ] || r=10
    hyprctl repl "hl.config({ decoration = { rounding = $r, blur = { enabled = true } } }); if astraxIslandBlurMode then astraxIslandBlurMode(false) end" >/dev/null 2>&1
}

case "${1:-status}" in
    on)
        apply_on
        echo on > "$STATE_FILE"
        echo "sharp-transparent ON  -- rounding 0, blur off (except the Dynamic Island glass)"
        ;;
    off)
        apply_off
        echo off > "$STATE_FILE"
        echo "sharp-transparent OFF -- rounding restored, blur on"
        ;;
    toggle)
        if [ "$(state)" = "on" ]; then exec "$0" off; else exec "$0" on; fi
        ;;
    reapply)
        [ "$(state)" = "on" ] && apply_on
        ;;
    status|'')
        echo "sharp-transparent: $(state)"
        ;;
    *)
        echo "usage: sharp-transparent-ctl.sh on|off|toggle|status" >&2
        exit 1
        ;;
esac
