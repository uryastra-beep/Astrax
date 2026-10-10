#!/usr/bin/env bash
# taskbar on|off — forces the taskbar always visible / always hidden,
# until the other command runs. Without this, it's automatic (it shows
# only when the mouse touches the bottom edge of the screen).

# Optional extra: Astrax does not ship the eww taskbar itself. It only works if
# you have eww plus an eww config defining the taskbar-<monitor> windows.
if ! command -v eww > /dev/null 2>&1 || [ ! -f "$HOME/.config/eww/eww.yuck" ]; then
    echo "taskbar: not installed (needs eww and ~/.config/eww/eww.yuck with the taskbar windows)" >&2
    exit 1
fi

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
