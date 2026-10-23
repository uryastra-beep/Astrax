#!/bin/sh
# Describe the current clipboard as one JSON line for the Dynamic Island.
#   clip-event.sh copied|pasted
# Passwords from managers that flag their copies as secret are never announced.
state="${1:-copied}"
types=$(wl-paste --list-types 2>/dev/null) || exit 0
[ -z "$types" ] && exit 0
case "$types" in *x-kde-passwordManagerHint*) exit 0 ;; esac
dir="${XDG_RUNTIME_DIR:-/tmp}/astrax-island"
mkdir -p "$dir"

if printf '%s\n' "$types" | grep -qxE 'text/uri-list|x-special/gnome-copied-files'; then
    # file managers offer text/uri-list; Nautilus also tells copy from cut in gnome-copied-files
    gnome=$(wl-paste -t x-special/gnome-copied-files 2>/dev/null | tr -d '\r')
    uris=$(wl-paste -t text/uri-list 2>/dev/null | tr -d '\r' | grep '^file://')
    [ -z "$uris" ] && uris=$(printf '%s\n' "$gnome" | grep '^file://')
    [ -z "$uris" ] && exit 0
    action=copy
    [ "$(printf '%s\n' "$gnome" | head -n1)" = cut ] && action=cut
    count=$(printf '%s\n' "$uris" | grep -c .)
    first=$(printf '%s\n' "$uris" | head -n1 | sed 's|^file://||; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')
    first=$(printf '%b' "$first")
    jq -nc --arg state "$state" --arg action "$action" --arg path "$first" --argjson count "$count" \
        '{kind:"files", state:$state, action:$action, path:$path, count:$count}'
elif printf '%s\n' "$types" | grep -q '^image/'; then
    mime=$(printf '%s\n' "$types" | grep -m1 '^image/')
    f="$dir/clip-$(date +%s%N).img"
    wl-paste -t "$mime" > "$f" 2>/dev/null
    [ -s "$f" ] || { rm -f "$f"; exit 0; }
    # keep only the last few thumbnails
    ls -t "$dir"/clip-*.img 2>/dev/null | tail -n +6 | xargs -r rm -f
    dims=$(identify -format '%w %h' "$f" 2>/dev/null | head -n1)
    w=${dims% *}; h=${dims#* }
    size=$(stat -c %s "$f")
    jq -nc --arg state "$state" --arg thumb "$f" --arg w "${w:-0}" --arg h "${h:-0}" --argjson size "$size" \
        '{kind:"image", state:$state, thumb:$thumb, w:($w|tonumber), h:($h|tonumber), size:$size}'
else
    txt=$(wl-paste -n -t text/plain 2>/dev/null | head -c 20000)
    [ -z "$txt" ] && exit 0
    chars=$(printf '%s' "$txt" | wc -m)
    lines=$(printf '%s\n' "$txt" | grep -c .)
    preview=$(printf '%s\n' "$txt" | grep -m1 '[^[:space:]]' | cut -c1-140)
    jq -nc --arg state "$state" --arg preview "$preview" --argjson chars "$chars" --argjson lines "$lines" \
        '{kind:"text", state:$state, preview:$preview, chars:$chars, lines:$lines}'
fi
