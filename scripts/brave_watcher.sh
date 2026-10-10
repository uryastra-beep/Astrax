#!/usr/bin/env bash
# brave_watcher.sh -- keeps Brave / Brave Origin from still eating CPU/RAM
# in the background after closing their last window. Brave's internal
# extension that handles Shields/Rewards (id mnojpmjdmbbfmejpflffifhffcmidifd,
# "persistent": true in its manifest) keeps the browser process alive
# even with no windows left -- neither --disable-background-mode nor closing
# the window is enough for it to shut down by itself. This watcher kills it
# once it has gone GRACE_CYCLES cycles in a row without a mapped window (so it isn't
# killed during its own startup, while the window hasn't appeared yet).
#
# Same pattern as gamemode_watcher.py: loop + flock -n in autostart.lua
# so it isn't duplicated on a reload.

set -u

POLL_SECONDS=3
GRACE_CYCLES=3  # ~9s without a window before killing it

streak_brave=0
streak_origin=0

has_window() {
    # Real BUG: it compared the EXACT class ("brave-browser"),
    # but a window opened in app mode ("brave --app-id=...", e.g. from
    # a shortcut/PWA) has a completely different class
    # ("brave-<extension-id>-Default") -- the watcher didn't recognize it,
    # thought Brave was left running without windows, and killed it after 9s
    # even though the window was open and in use. Now "$1" is a
    # REGEX (not a bare class) covering normal window + app mode.
    hyprctl clients -j 2>/dev/null | jq -e --arg re "$1" \
        '.[] | select(.class | test($re))' > /dev/null 2>&1
}

# Normal Brave and Brave Origin are DIFFERENT binaries but both run
# literally as "brave" (same comm: /opt/brave-bin/brave vs
# /opt/brave.com/brave-origin-nightly/brave) -- "pgrep/pkill -x brave" can't
# tell them apart and may kill the wrong one. That's why all of this matches on
# the full executable path, not the process name.

# check <pgrep -f pattern> <window class> <streak var name> <label>
check_one() {
    local pattern="$1" class="$2"
    local -n streak="$3"
    local label="$4"

    if ! pgrep -f "$pattern" > /dev/null 2>&1; then
        streak=0
        return
    fi
    if has_window "$class"; then
        streak=0
        return
    fi

    streak=$((streak + 1))
    if [ "$streak" -ge "$GRACE_CYCLES" ]; then
        pkill -f "$pattern" 2>/dev/null
        echo "$(date '+%H:%M:%S') $label without a window for $((streak * POLL_SECONDS))s -- killed" >&2
        streak=0
    fi
}

while true; do
    check_one "^/opt/brave-bin/brave " "^brave-browser$|^brave-[a-zA-Z0-9]+-[A-Za-z]+$" streak_brave "brave"
    check_one "^/opt/brave\.com/brave-origin-nightly/brave " "^brave-origin-nightly$|^brave-origin-[a-zA-Z0-9]+-[A-Za-z]+$" streak_origin "brave-origin"
    sleep "$POLL_SECONDS"
done
