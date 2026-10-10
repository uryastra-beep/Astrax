#!/usr/bin/env bash
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
frozen=0

check() {
    ws=$(hyprctl -j activeworkspace | jq -r .id)
    # counts windows on the current workspace, ignoring the widgets
    n=$(hyprctl -j clients | jq "[.[] | select(.workspace.id==$ws) | select(.class | test(\"^widget-\") | not)] | length")
    if [ "$n" -gt 0 ] && [ "$frozen" -eq 0 ]; then
        pkill -STOP mpvpaper; frozen=1
    elif [ "$n" -eq 0 ] && [ "$frozen" -eq 1 ]; then
        pkill -CONT mpvpaper; frozen=0
    fi
}

check
socat -u "UNIX-CONNECT:$SOCK" - | while read -r line; do
    case "$line" in
        openwindow*|closewindow*|workspace*|movewindow*|focusedmon*) check ;;
    esac
done
