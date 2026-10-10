#!/bin/sh
# Called by ThemeBackend.qml on every lyric line change of a mode with
# "cycle" (Streetcat): rotates the color of the widgets (widgets2-4 read
# /tmp/widget-colors.json live) and of the Hyprland window border.
# Usage: mode-cycle-apply.sh PRIMARY SECONDARY   (hex without #)
f=/tmp/widget-colors.json
t=$(mktemp /tmp/.widget-colors-XXXXXX) || exit 1
printf '{"primary": "%s", "tertiary": "%s"}' "$1" "$2" > "$t" && chmod 644 "$t" && mv "$t" "$f"
hyprctl repl "hl.config({ general = { col = { active_border = { colors = { \"rgb($1)\", \"rgb($2)\" }, angle = 45 } } } })" >/dev/null 2>&1
