#!/usr/bin/env bash
STATE=/tmp/shrink-state.json

if [ -f "$STATE" ]; then
    # restore
    jq -c ".[]" "$STATE" | while read -r w; do
        addr=$(echo "$w" | jq -r .address)
        x=$(echo "$w" | jq -r .x); y=$(echo "$w" | jq -r .y)
        ww=$(echo "$w" | jq -r .w); hh=$(echo "$w" | jq -r .h)
        hyprctl dispatch resizewindowpixel "exact $ww $hh,address:$addr"
        hyprctl dispatch movewindowpixel "exact $x $y,address:$addr"
    done
    rm -f "$STATE"
else
    # save and shrink
    hyprctl -j clients | jq "[.[] | select(.floating==true) | {address, x:.at[0], y:.at[1], w:.size[0], h:.size[1]}]" > "$STATE"
    jq -c ".[]" "$STATE" | while read -r w; do
        addr=$(echo "$w" | jq -r .address)
        x=$(echo "$w" | jq -r .x); y=$(echo "$w" | jq -r .y)
        ww=$(echo "$w" | jq -r .w); hh=$(echo "$w" | jq -r .h)
        nw=$((ww * 60 / 100)); nh=$((hh * 60 / 100))
        nx=$((x + (ww - nw) / 2)); ny=$((y + (hh - nh) / 2))
        hyprctl dispatch resizewindowpixel "exact $nw $nh,address:$addr"
        hyprctl dispatch movewindowpixel "exact $nx $ny,address:$addr"
    done
fi
