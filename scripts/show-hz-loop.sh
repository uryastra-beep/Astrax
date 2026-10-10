#!/usr/bin/env bash
# Loop that draws each monitor's Hz, refreshing every second.
# Launched inside a kitty by show-ctl.sh ("show hz" command).

label_for() {
    case "$1" in
        *HDMI*) echo "HDMI" ;;
        *eDP*)  echo "LAPTOP" ;;
        *)      echo "$1" ;;
    esac
}

while true; do
    clear
    hyprctl monitors -j | jq -r 'sort_by(.name) | .[] | "\(.name)\t\(.refreshRate)"' |
    while IFS=$'\t' read -r name hz; do
        label=$(label_for "$name")
        hz_int=$(awk -v n="$hz" 'BEGIN { printf "%.0f", n }')
        echo "$label"
        echo "Hz: $hz_int"
        echo
    done
    sleep 1
done
