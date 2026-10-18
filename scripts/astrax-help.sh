#!/usr/bin/env bash
# astrax-help: lists every Astrax command and what it does.
#
#   astrax-help            all commands
#   astrax-help <word>     only the ones that match (name or description)
set -u

cat_all() { cat <<'LIST'
Maintenance::astrax-doctor::check that the install is healthy and say how to fix what isn't
Maintenance::astrax-safe::safe mode: patched cursor off, normal cursor, opti on (works from a TTY); on | off | status
Maintenance::astrax-hypr-guard::tells you when a Hyprland update left the patched cursor out of date (runs at login)
Maintenance::astrax-update::Astrax version and updates: version | check | status | run | changelog | rollback
Maintenance::srp-update::update Serpantinum safely (backs up first)
Maintenance::astrax-restore::undo a bad update: restores the latest backup (--list to see them)
Setup::astrax-tour::the welcome shortcuts, again (--force)
Setup::astrax-monitors::pick which outputs are p1 and p2 (no hand-editing variables.lua)
Music::liner-bridge::open Liner (unofficial) so its word/syllable lyrics reach the bar; see docs/liner.md
Music::astrax-lyrics-rating::star ratings for lyrics sync (click the lyrics module); 4-5 stars become the best lyrics
Look::mode::switch the special song modes
Look::cursor-style::reactive cursor style: normal | astrax | highcontrast
Look::cursor-plugin::check or rebuild the cursor plugin after a Hyprland update
Look::lava-wallpaper::the lava-lamp wallpaper
Look::sharp::sharp / transparent window toggle
Performance::opti::lighter mode for slower hardware
Performance::hz::refresh-rate tools (check, overclock test)
Performance::vm::VM mode
Desktop::workspace::workspace helper
Desktop::widget, widget2..widget6::show / hide each widget set
Desktop::show::show helper
Desktop::intro, outro::boot and power-off animations
LIST
}

q="${1:-}"
{
    echo "Astrax commands (keybinds: SUPER+I)"
    echo
    cat_all | { if [ -n "$q" ]; then grep -i -- "$q" || true; else cat; fi; } \
        | awk -F'::' '{ if ($1 != last) { printf "\n%s\n", $1; last = $1 } printf "  %-18s %s\n", $2, $3 }'
    echo
    echo "Each command has its own usage: run it with --help or no arguments."
}
