#!/bin/sh
# Prints the file paths on the clipboard, one per line (empty = plain text, let the normal paste happen).
# Files copied in a file manager (uri-list / gnome-copied-files) -> their paths; an image -> saved to a temp png.
types="$(wl-paste -l 2>/dev/null)"
uris="$(printf '%s\n' "$types" | grep -m1 -x 'text/uri-list')"
if [ -n "$uris" ]; then
  wl-paste -t text/uri-list 2>/dev/null | tr -d '\r' | python3 -I -c '
import sys, urllib.parse
for l in sys.stdin:
    l = l.strip()
    if l.startswith("file://"): print(urllib.parse.unquote(l[7:]))'
  exit 0
fi
if printf '%s\n' "$types" | grep -q -x 'x-special/gnome-copied-files'; then
  wl-paste -t x-special/gnome-copied-files 2>/dev/null | tr -d '\r' | python3 -I -c '
import sys, urllib.parse
for l in sys.stdin:
    l = l.strip()
    if l.startswith("file://"): print(urllib.parse.unquote(l[7:]))'
  exit 0
fi
img="$(printf '%s\n' "$types" | grep -m1 -E '^image/(png|jpeg|webp|gif)$')"
if [ -n "$img" ]; then
  ext="${img#image/}"; [ "$ext" = jpeg ] && ext=jpg
  d="${XDG_RUNTIME_DIR:-/tmp}/astrax-paste"; mkdir -p "$d"
  f="$d/pasted-$(date +%s).$ext"
  wl-paste -t "$img" > "$f" 2>/dev/null && [ -s "$f" ] && echo "$f"
fi
