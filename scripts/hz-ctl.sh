#!/usr/bin/env bash
# Hz p1|p2 <hz>       -- changes that screen's refresh rate (no cap)
# check Hz p1|p2|all  -- shows the current Hz
# hz p1|p2 set <hz>   -- like "Hz" but with a safety cap: won't go
#                        above what was tested and confirmed stable by hand
#                        (p1/laptop 70Hz, p2/HDMI 200Hz)
# (same script, behaves differently depending on the name you call it by)

set -u

mon_for() {
    case "$1" in
        p1) echo "eDP-1" ;;
        p2) echo "HDMI-A-1" ;;
        *) echo "" ;;
    esac
}

get_res() {
    hyprctl monitors -j | jq -r --arg name "$1" '.[] | select(.name==$name) | "\(.width)x\(.height)"'
}

get_hz() {
    hyprctl monitors -j | jq -r --arg name "$1" '.[] | select(.name==$name) | .refreshRate'
}

round_hz() {
    awk -v n="$1" 'BEGIN { printf "%.0f", n }'
}

set_hz() {
    local mon="$1" hz="$2"
    local res
    res=$(get_res "$mon")
    if [ -z "$res" ]; then
        echo "monitor $mon not found" >&2
        exit 1
    fi
    hyprctl repl "hl.monitor({ output = \"${mon}\", mode = \"${res}@${hz}\" })" > /dev/null 2>&1
    sleep 0.3
    local now
    now=$(get_hz "$mon")
    echo "${mon}: $(round_hz "$now")Hz"
}

max_hz_for() {
    case "$1" in
        eDP-1)    echo 70 ;;
        HDMI-A-1) echo 200 ;;
        *)        echo "" ;;
    esac
}

get_pos() {
    hyprctl monitors -j | jq -r --arg name "$1" '.[] | select(.name==$name) | "\(.x)x\(.y)"'
}

get_scale() {
    hyprctl monitors -j | jq -r --arg name "$1" '.[] | select(.name==$name) | .scale'
}

set_hz_capped() {
    local mon="$1" hz="$2" max
    max=$(max_hz_for "$mon")

    if ! [[ "$hz" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "hz invalido: $hz" >&2
        exit 1
    fi
    if awk -v h="$hz" -v m="$max" 'BEGIN { exit !(h > m) }'; then
        echo "not allowed: ${mon} is capped at ${max}Hz (overclock tested and confirmed stable by hand). You asked for ${hz}Hz." >&2
        exit 1
    fi

    local res pos scale
    res=$(get_res "$mon")
    pos=$(get_pos "$mon")
    scale=$(get_scale "$mon")
    hyprctl repl "hl.monitor({ output = \"${mon}\", mode = \"${res}@${hz}\", position = \"${pos}\", scale = \"${scale}\" })" > /dev/null 2>&1
    sleep 0.3
    local now
    now=$(get_hz "$mon")
    echo "${mon}: $(round_hz "$now")Hz"
}

check_hz() {
    local target="$1"
    if [ "$target" = "all" ]; then
        for m in eDP-1 HDMI-A-1; do
            hz=$(get_hz "$m")
            [ -n "$hz" ] && echo "${m}: $(round_hz "$hz")Hz"
        done
    else
        local mon
        mon=$(mon_for "$target")
        if [ -z "$mon" ]; then
            echo "usage: check Hz p1|p2|all" >&2
            exit 1
        fi
        hz=$(get_hz "$mon")
        echo "${mon}: $(round_hz "$hz")Hz"
    fi
}

prog="$(basename "$0")"

case "$prog" in
    Hz)
        target="${1:-}"
        rate="${2:-}"
        mon=$(mon_for "$target")
        if [ -z "$mon" ] || [ -z "$rate" ]; then
            echo "usage: Hz p1|p2 <hz>" >&2
            exit 1
        fi
        set_hz "$mon" "$rate"
        ;;
    check)
        sub="${1:-}"
        arg="${2:-}"
        if [ "$sub" != "Hz" ] || [ -z "$arg" ]; then
            echo "usage: check Hz p1|p2|all" >&2
            exit 1
        fi
        check_hz "$arg"
        ;;
    hz)
        target="${1:-}"
        sub="${2:-}"
        rate="${3:-}"
        mon=$(mon_for "$target")
        if [ -z "$mon" ] || [ "$sub" != "set" ] || [ -z "$rate" ]; then
            echo "usage: hz p1|p2 set <hz>" >&2
            exit 1
        fi
        set_hz_capped "$mon" "$rate"
        ;;
    *)
        echo "call it as 'Hz', 'check' or 'hz'" >&2
        exit 1
        ;;
esac
