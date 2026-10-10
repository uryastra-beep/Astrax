#!/usr/bin/env bash
# show hz — opens a window with the current Hz of each monitor (updates
# by itself every second). Closes like any normal window.

case "${1:-}" in
    hz)
        setsid kitty --class show-hz -o background_opacity=0.85 -o font_size=18 \
            bash "$HOME/scripts/show-hz-loop.sh" < /dev/null > /dev/null 2>&1 &
        ;;
    *)
        echo "usage: show hz" >&2
        exit 1
        ;;
esac
