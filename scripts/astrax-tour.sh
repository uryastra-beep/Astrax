#!/usr/bin/env bash
# astrax-tour: shows the shortcuts and commands worth knowing, as desktop notifications.
#
#   astrax-tour           once per install (does nothing if it was already shown)
#   astrax-tour --force   show it again
# Run at login by autostart.lua. Override for tests: ASTRAX_STATE_DIR.
set -u

STATE="${ASTRAX_STATE_DIR:-$HOME/.local/state/astrax}"
DONE="$STATE/tour-done"

if [ "${1:-}" != "--force" ] && [ -f "$DONE" ]; then exit 0; fi
mkdir -p "$STATE"

n() { command -v notify-send >/dev/null 2>&1 && notify-send -a Astrax -i help-about "$1" "$2" >/dev/null 2>&1; sleep 1; }
n "Welcome to Astrax" "Five things worth knowing"
n "SUPER (tap)" "Opens the launcher. CTRL+SUPER opens Caelestia's."
n "SUPER + I" "Search every keybind."
n "SUPER + C" "Serpantinum's menu: settings, About, Astrax updates."
n "astrax-help" "In a terminal: lists every Astrax command."
n "astrax-doctor" "Checks the install and says how to fix what is off."
date +%s > "$DONE"
