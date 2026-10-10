#!/usr/bin/env bash
# SUPER+SHIFT+W: on/off toggle of the widget set (clock+lavat) + the
# native Serpantinum preset on the screen FOCUSED right now. One press
# turns it off (widget-ctl.sh off -> closes the set and applies the "Default" preset),
# the next one turns it back on (widget-ctl.sh p1/p2 -> reopens the set and
# applies the "Music" preset) on that same screen.
set -u

source "$HOME/scripts/widget-opti-common.sh"

target_mon=$(resolve_off_target_monitor "")
if [ -z "$target_mon" ]; then
    echo "ERROR: couldn't resolve the focused screen (hyprctl/jq failed)." >&2
    exit 1
fi

if any_widgets1_running_on "$target_mon"; then
    exec "$HOME/scripts/widget-ctl.sh" off
fi

case "$target_mon" in
    eDP-1)     exec "$HOME/scripts/widget-ctl.sh" p1 ;;
    HDMI-A-1)  exec "$HOME/scripts/widget-ctl.sh" p2 ;;
    *)         echo "ERROR: unknown monitor: $target_mon" >&2; exit 1 ;;
esac
