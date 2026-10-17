#!/usr/bin/env bash
# astrax-monitors: sets p1/p2 (MONITOR1 / MONITOR2 in variables.lua) from your real outputs.
#
#   astrax-monitors            list the connected outputs and pick p1 and p2 (asks first)
#   astrax-monitors --list     only list them
#   astrax-monitors P1 [P2]    set them directly, e.g. astrax-monitors eDP-1 HDMI-A-1
#
# Only the two MONITOR1 / MONITOR2 lines of ~/.config/hypr/config/variables.lua change;
# a copy of the file is kept next to it as variables.lua.bak. Modes, positions and scales
# stay in monitors.lua (empty by default: Hyprland picks them by itself).
# Override for tests: ASTRAX_VARS.
set -u

VARS="${ASTRAX_VARS:-$HOME/.config/hypr/config/variables.lua}"

outputs() {
    hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    print("%s\t%dx%d@%.0f\t%s" % (m["name"], m["width"], m["height"], m["refreshRate"], m.get("description", "")))' 2>/dev/null
}

current() { sed -n "s/^$1 = \"\(.*\)\"/\1/p" "$VARS" | head -n1; }

set_var() { # name value
    sed -i "s|^$1 = \".*\"|$1 = \"$2\"|" "$VARS"
}

[ -f "$VARS" ] || { echo "not found: $VARS (is Astrax installed?)" >&2; exit 1; }

case "${1:-}" in
    --list|-l|"")
        mapfile -t outs < <(outputs)
        [ "${#outs[@]}" -gt 0 ] || { echo "no outputs: is Hyprland running?" >&2; exit 1; }
        echo "Connected outputs:"
        i=0
        for o in "${outs[@]}"; do i=$((i + 1)); IFS=$'\t' read -r n mode desc <<< "$o"; printf '  %d) %-10s %-14s %s\n' "$i" "$n" "$mode" "$desc"; done
        echo
        echo "Now: p1 = $(current MONITOR1), p2 = $(current MONITOR2)"
        [ "${1:-}" ] && exit 0
        read -rp "Number for p1 (main screen) [enter keeps $(current MONITOR1)]: " a
        read -rp "Number for p2 (second screen, 0 = none) [enter keeps $(current MONITOR2)]: " b
        p1="$(current MONITOR1)"; p2="$(current MONITOR2)"
        [ -n "$a" ] && p1="$(printf '%s' "${outs[$((a - 1))]:-}" | cut -f1)"
        [ -n "$b" ] && { [ "$b" = 0 ] && p2="" || p2="$(printf '%s' "${outs[$((b - 1))]:-}" | cut -f1)"; }
        [ -n "$p1" ] || { echo "invalid choice for p1" >&2; exit 1; }
        ;;
    *) p1="$1"; p2="${2:-$(current MONITOR2)}" ;;
esac

known="$(outputs | cut -f1)"
if [ -n "$known" ]; then
    for n in "$p1" "$p2"; do
        [ -n "$n" ] && ! grep -qx "$n" <<< "$known" && echo "Warning: $n is not connected right now (fine if it is a monitor you plug in later)."
    done
fi
echo "Will set p1 = $p1, p2 = ${p2:-<none>} in $VARS"
if [ -t 0 ] && [ -z "${ASTRAX_YES:-}" ]; then read -rp "Apply? [y/N] " r; [ "$r" = y ] || [ "$r" = Y ] || { echo "cancelled"; exit 1; }; fi
cp "$VARS" "$VARS.bak"
set_var MONITOR1 "$p1"; set_var MONITOR2 "$p2"
sed -i "s|^PRIMARY_MONITOR = .*|PRIMARY_MONITOR = MONITOR1|" "$VARS"
echo "Done (backup: $VARS.bak). Log out and back in so every widget and script picks it up."
