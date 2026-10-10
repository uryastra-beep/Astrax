#!/usr/bin/env bash
# Reads cava's raw output (levels 0-7 separated by ';') and turns them
# into a string of unicode blocks shown as text in the taskbar.
# eww runs it directly via deflisten, no need to launch it separately.

BLOCKS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

cava -p "$HOME/.config/cava/taskbar-config" 2>/dev/null | while IFS=';' read -ra levels; do
    out=""
    for v in "${levels[@]}"; do
        [ -z "$v" ] && continue
        out+="${BLOCKS[$v]}"
    done
    echo "$out"
done
