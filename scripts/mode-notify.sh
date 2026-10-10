#!/usr/bin/env bash
# mode-notify.sh <app1> [app2 ...] -- temporary kitty window (closes by itself
# after 10s) saying that one or more apps were already open.
# Launched by mode-ctl.sh, never by hand.

set -u

apps=("$@")
[ "${#apps[@]}" -eq 0 ] && exit 0

if [ "${#apps[@]}" -eq 1 ]; then
    header="ALREADY OPEN"
else
    header="ALREADY OPEN"
fi

cols=$(tput cols 2>/dev/null || echo 80)
lines=$(tput lines 2>/dev/null || echo 24)

center() {
    local text="$1"
    local pad=$(( (cols - ${#text}) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%*s%s\n' "$pad" "" "$text"
}

pad_top=$(( (lines - (3 + ${#apps[@]})) / 2 ))
[ "$pad_top" -lt 0 ] && pad_top=0

clear
for _ in $(seq 1 "$pad_top"); do echo; done
tput bold
center "$header"
tput sgr0
echo
for app in "${apps[@]}"; do
    center "$app"
done

sleep 10
