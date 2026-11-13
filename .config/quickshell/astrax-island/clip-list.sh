#!/bin/sh
# One JSON line per cliphist entry, newest first. Images are decoded once into a thumbnail cache.
#   clip-list.sh [max]
dir="${XDG_RUNTIME_DIR:-/tmp}/astrax-island/cliphist"
mkdir -p "$dir"
find "$dir" -type f -mmin +720 -delete 2>/dev/null
tab=$(printf '\t')
list=$(cliphist -preview-width 160 list | head -n "${1:-60}")
printf '%s\n' "$list" | while IFS="$tab" read -r id rest; do
    case "$rest" in
        "[[ binary data"*) [ -s "$dir/$id.img" ] || cliphist decode "$id" > "$dir/$id.img" 2>/dev/null ;;
    esac
done
printf '%s\n' "$list" | jq -Rc --arg dir "$dir" 'select(length > 0) | split("\t") as $p | ($p[1:] | join("\t")) as $r
    | if ($r | startswith("[[ binary data")) then
        {id: $p[0], kind: "image", thumb: ($dir + "/" + $p[0] + ".img"), info: ($r | sub("^\\[\\[ binary data "; "") | sub(" \\]\\]$"; ""))}
      else {id: $p[0], kind: "text", text: $r} end'
