#!/usr/bin/env bash
# workspace status -- lists the workspaces with open apps, which app is there
# and the keyboard shortcut to get there (per the binds.lua/variables.lua scheme).
set -euo pipefail

CONF="$HOME/.config/hypr/config/variables.lua"
NUM_WPM=$(grep -oP '^NUM_WPM\s*=\s*\K[0-9]+' "$CONF" 2>/dev/null || echo 10)
MON1=$(grep -oP '^MONITOR1\s*=\s*"\K[^"]*' "$CONF" 2>/dev/null || echo "?")
MON2=$(grep -oP '^MONITOR2\s*=\s*"\K[^"]*' "$CONF" 2>/dev/null || echo "?")

# Translates a local index (1..NUM_WPM within ONE monitor) to the real shortcut.
# Two different schemes depending on the active shell (HYPR_SHELL):
#   Caelestia (binds.lua): split per monitor, 1-10 -> SUPER+ALT+digit,
#     11-20 -> SUPER+CTRL+digit (digit = 0 for 10/20).
#   Serpantinum (binds-serpantinum.lua): flat numbering 1-10 shared
#     across monitors, no split -- SUPER+digit to go, SUPER+SHIFT+digit to
#     move a window (see the "for i = 1, 10" in that file).
bind_for() {
    local local_i=$1
    if [ "${HYPR_SHELL:-}" = "serpantinum" ]; then
        if [ "$local_i" -ge 1 ] && [ "$local_i" -le 10 ]; then
            echo "SUPER+$((local_i % 10))"
        else
            echo "no bind (outside 1-10)"
        fi
    elif [ "$local_i" -le 10 ]; then
        echo "SUPER+ALT+$((local_i % 10))"
    else
        echo "SUPER+CTRL+$(((local_i - 10) % 10))"
    fi
}

apps_in_ws() {
    local wid=$1
    echo "$CLIENTS" | jq -r --argjson wid "$wid" \
        '[.[] | select(.workspace.id == $wid) | (.class // .initialClass // .title // "?")] | unique | join("/")'
}

print_section() {
    local label=$1 mon_name=$2 offset=$3
    echo "${label} (${mon_name}):"
    local any=0
    for id in "${IDS[@]}"; do
        local local_i=$((id - offset))
        if [ "$local_i" -ge 1 ] && [ "$local_i" -le "$NUM_WPM" ]; then
            any=1
            echo "ws${local_i} = $(apps_in_ws "$id") [$(bind_for "$local_i")]"
        fi
    done
    if [ "$any" -eq 0 ]; then echo "(vacio)"; fi
}

cmd_status() {
    CLIENTS=$(hyprctl clients -j)
    mapfile -t IDS < <(echo "$CLIENTS" | jq -r '[.[].workspace.id] | unique | .[] | select(. > 0)' | sort -n)

    if [ "${#IDS[@]}" -eq 0 ]; then
        echo "No apps open on any workspace."
        return
    fi

    if [ "${HYPR_SHELL:-}" = "serpantinum" ]; then
        # Serpantinum uses "m~N" (relative to the CURRENT monitor, via the
        # infinite-desktop-v2 plugin), not a fixed global ID like Caelestia. The
        # real Hyprland IDs are absolute and start at a different block
        # per monitor (e.g. eDP-1 = 1-20, HDMI-A-1 = 21-40) -- to show
        # the right "N" of "m~N" you have to subtract EACH monitor's own
        # offset, not a fixed one (NUM_WPM), and that offset is computed from
        # the workspaces Hyprland reports for that monitor.
        local ALL_WS
        ALL_WS=$(hyprctl workspaces -j)
        for mon in $(echo "$ALL_WS" | jq -r '[.[].monitor] | unique | .[]'); do
            local min_id
            min_id=$(echo "$ALL_WS" | jq -r --arg m "$mon" '[.[] | select(.monitor == $m) | .id] | min')
            echo "${mon}:"
            local any=0
            for id in "${IDS[@]}"; do
                local ws_mon
                ws_mon=$(echo "$ALL_WS" | jq -r --argjson id "$id" '.[] | select(.id == $id) | .monitor')
                if [ "$ws_mon" = "$mon" ]; then
                    any=1
                    local local_i=$((id - min_id + 1))
                    echo "ws${local_i} = $(apps_in_ws "$id") [$(bind_for "$local_i")]"
                fi
            done
            if [ "$any" -eq 0 ]; then echo "(vacio)"; fi
            echo
        done
        return
    fi

    print_section "p1" "$MON1" 0
    echo
    print_section "p2" "$MON2" "$NUM_WPM"
}

usage() {
    cat <<EOF
Usage: workspace <command>

Commands:
  status   Shows the workspaces with open apps, which app is there and the
           keyboard shortcut to get to each one.
EOF
}

case "${1:-}" in
    status) cmd_status ;;
    *)      usage ;;
esac
