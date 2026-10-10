#!/usr/bin/env bash
# spotify-toggle.sh -- meant for SUPER+M.
# If Spotify isn't running: opens it small and floating on the screen/
# workspace you're on now.
# If it's running and VISIBLE on the current workspace: hides it (sends it
# to a special workspace -- Spotify has no real tray on Linux, this
# replaces it).
# If it's running but hidden (or on another workspace): brings it back
# small and focused to the current workspace.
#
# Real BUG ruled out live: "hl.dsp.exec_raw('movetoworkspacesilent', 'ws,address:...')"
# and "hl.dsp.window.move({window='address:...', workspace=...})" (STRING
# selector) don't move anything in this hyprland-lua -- "ok" but no-op, tested
# with several windows. What DOES work: "hl.dsp.window.move({window =
# hl.get_windows({class=...})[1], workspace = ...})" -- OBJECT selector via
# hl.get_windows(). Also, unlike what's documented in
# widget4_visibility.py (which said this "reveals" the target special
# workspace), tested live: it does NOT change the active workspace/visible focus.

set -u

CLASS="Spotify"
SPECIAL="special:spotifyhidden"
WIN_W=520
WIN_H=340
WIN_SEL="hl.get_windows({ class = '${CLASS}' })[1]"

active_ws() { hyprctl activeworkspace -j 2>/dev/null | jq -r '.id'; }

win_json() {
    hyprctl clients -j 2>/dev/null | jq -c --arg c "$CLASS" '[.[] | select(.class==$c)][0] // empty'
}

move_to_workspace() {
    hyprctl dispatch "hl.dsp.window.move({ window = ${WIN_SEL}, workspace = '$1' })" > /dev/null 2>&1
}

center_pos_on_current_monitor() {
    hyprctl monitors -j 2>/dev/null | jq -r --argjson w "$WIN_W" --argjson h "$WIN_H" \
        '[.[] | select(.focused==true)][0] | "\((.x + (.width - $w) / 2) | floor) \((.y + (.height - $h) / 2) | floor)"'
}

show_small_here() {
    local ws="$1" is_floating="$2"
    move_to_workspace "$ws"
    if [ "$is_floating" != "true" ]; then
        hyprctl dispatch "hl.dsp.window.float({ action = \"toggle\", window = ${WIN_SEL} })" > /dev/null 2>&1
    fi
    hyprctl dispatch "hl.dsp.window.resize({ window = ${WIN_SEL}, x = ${WIN_W}, y = ${WIN_H}, relative = false })" > /dev/null 2>&1
    read -r px py < <(center_pos_on_current_monitor)
    if [ -n "${px:-}" ] && [ -n "${py:-}" ]; then
        hyprctl dispatch "hl.dsp.window.move({ window = ${WIN_SEL}, x = ${px}, y = ${py}, relative = false })" > /dev/null 2>&1
    fi
    hyprctl dispatch "hl.dsp.focus({ window = ${WIN_SEL} })" > /dev/null 2>&1
}

win="$(win_json)"

if [ -z "$win" ]; then
    setsid spotify > /dev/null 2>&1 &
    for _ in $(seq 1 50); do
        win="$(win_json)"
        [ -n "$win" ] && break
        sleep 0.2
    done
    [ -n "$win" ] || exit 0
    is_floating=$(echo "$win" | jq -r '.floating')
    show_small_here "$(active_ws)" "$is_floating"
    exit 0
fi

is_floating=$(echo "$win" | jq -r '.floating')
cur_ws="$(active_ws)"
win_ws="$(echo "$win" | jq -r '.workspace.id')"

if [ "$win_ws" = "$cur_ws" ]; then
    move_to_workspace "$SPECIAL"
else
    show_small_here "$cur_ws" "$is_floating"
fi
