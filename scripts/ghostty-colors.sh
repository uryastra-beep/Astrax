#!/usr/bin/env bash
# Converts the Serpantinum theme colors (kitty/colors.conf, which matugen
# regenerates on every theme) to Ghostty's format and reloads it.
# Called by Serpantinum's matugen_reload.sh after every theme change.
src="$HOME/.config/kitty/colors.conf"
out="$HOME/.config/ghostty/serpantinum-colors"
[ -r "$src" ] || exit 0
awk '
/^color[0-9]+[ \t]/ { n = substr($1, 6); printf "palette = %s=%s\n", n, $2; next }
$1 == "background"           { print "background = " $2 }
$1 == "foreground"           { print "foreground = " $2 }
$1 == "cursor"               { print "cursor-color = " $2 }
$1 == "cursor_text_color"    { print "cursor-text = " $2 }
$1 == "selection_background" { print "selection-background = " $2 }
$1 == "selection_foreground" { print "selection-foreground = " $2 }
' "$src" > "$out.tmp" && mv "$out.tmp" "$out"
pkill -USR2 -x ghostty 2>/dev/null
exit 0
