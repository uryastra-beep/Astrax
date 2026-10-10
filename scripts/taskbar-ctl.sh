#!/usr/bin/env bash
# taskbar on|off — forces the taskbar always visible / always hidden,
# until the other command runs. Without this, it's automatic (it shows
# only when the mouse touches the bottom edge of the screen).

STATE_FILE="$HOME/.local/state/taskbar-power"
mkdir -p "$(dirname "$STATE_FILE")"

case "${1:-}" in
    on)
        echo "on" > "$STATE_FILE"
        echo "taskbar enabled (always visible until 'taskbar off')"
        ;;
    off)
        echo "off" > "$STATE_FILE"
        echo "taskbar disabled (hidden until 'taskbar on')"
        ;;
    *)
        echo "usage: taskbar on|off" >&2
        exit 1
        ;;
esac
