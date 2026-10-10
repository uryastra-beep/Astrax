#!/usr/bin/env bash
# Prints the shell running right now: serpantinum | caelestia.
# `vm` switches shells live and records the choice per Hyprland instance in
# $XDG_RUNTIME_DIR/astrax-shell ("<instance signature> <shell>"); without that
# record the SDDM session decides (HYPR_SHELL). hyprland.lua reads the same file
# to pick its binds, so every consumer agrees after a `vm` switch.
f="${XDG_RUNTIME_DIR:-/tmp}/astrax-shell"
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && read -r sig shell < "$f" 2>/dev/null &&
    [ "$sig" = "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    case "$shell" in serpantinum|caelestia) echo "$shell"; exit 0 ;; esac
fi
if [ "${HYPR_SHELL:-}" = "serpantinum" ]; then echo serpantinum; else echo caelestia; fi
