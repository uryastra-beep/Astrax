#!/usr/bin/env bash
# astrax-hypr-guard: notices when Hyprland was updated and says what that means for the
# patched cursor plugin. It changes NOTHING: plugins.lua already refuses to load the patched
# plugin when its header hash differs from the installed Hyprland, so the stock plugin is used
# and the compositor is not put at risk. This only tells you, once per Hyprland version.
#
#   astrax-hypr-guard check [-n]   compare with the last seen version (-n: desktop notification)
#   astrax-hypr-guard status       print: ok | changed | unknown
#
# Run at login by autostart.lua. Override for tests: ASTRAX_STATE_DIR, ASTRAX_HYPR_VERSION.
set -u

STATE="${ASTRAX_STATE_DIR:-$HOME/.local/state/astrax}"
SEEN="$STATE/hypr-seen"

version() {
    if [ -n "${ASTRAX_HYPR_VERSION:-}" ]; then echo "$ASTRAX_HYPR_VERSION"; return; fi
    pacman -Q hyprland 2>/dev/null | awk '{print $2}' && return
    hyprctl version -j 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])' 2>/dev/null
}

now="$(version | head -n1)"
last="$(cat "$SEEN" 2>/dev/null)"

case "${1:-status}" in
    status)
        if [ -z "$now" ]; then echo unknown
        elif [ -z "$last" ] || [ "$now" = "$last" ]; then echo ok
        else echo changed; fi ;;
    check)
        mkdir -p "$STATE"
        [ -n "$now" ] || { echo "unknown"; exit 0; }
        if [ -z "$last" ]; then echo "$now" > "$SEEN"; echo "first run: Hyprland $now recorded"; exit 0; fi
        if [ "$now" = "$last" ]; then echo "Hyprland $now (unchanged)"; exit 0; fi
        echo "$now" > "$SEEN"
        msg="Hyprland changed $last -> $now."
        if cursor-plugin check >/dev/null 2>&1 || "$HOME/scripts/cursor-plugin.sh" check >/dev/null 2>&1; then
            msg="$msg The patched cursor still matches."
        else
            msg="$msg The patched cursor plugin no longer matches, so the stock one is used. Rebuild with: cursor-plugin build (then log out and in); run astrax-doctor to see everything."
        fi
        echo "$msg"
        if [ "${2:-}" = "-n" ] && command -v notify-send >/dev/null 2>&1; then
            notify-send -a Astrax -i dialog-information "Hyprland was updated" "$msg" >/dev/null 2>&1 || true
        fi ;;
    *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
