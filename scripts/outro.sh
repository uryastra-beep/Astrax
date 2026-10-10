#!/usr/bin/env bash
# Tries the power-off animation (astrax-power-wave = the intro in reverse) WITHOUT powering off:
# the wave rises, the logo turns off and 2s later it disappears.
#   outro per  -> same, but stays COVERED until `intro go` (to restart
#                 Serpantinum without it being seen). Returns once everything is covered.
#                 Safety net: after 3 min without `intro go`, it uncovers by itself.
if [ "$1" = "per" ]; then
    token="${XDG_RUNTIME_DIR:-/tmp}/astrax-outro-per"
    id="$$-$(date +%s%N)"
    echo "$id" > "$token"
    # the hyprpolkitagent window would end up under the cover: meanwhile
    # the agent is astrax-power-wave's (dialog above the cover)
    qs list --all 2>/dev/null | grep -q "astrax-power-wave/shell.qml" || { qs -c astrax-power-wave -d >/dev/null 2>&1; sleep 0.4; }
    systemctl --user stop hyprpolkitagent 2>/dev/null
    qs -c astrax-power-wave ipc call agent on >/dev/null 2>&1
    bash "$HOME/scripts/outro-cover.sh"
    setsid sh -c "sleep 180; [ \"\$(cat '$token' 2>/dev/null)\" = '$id' ] && bash '$HOME/scripts/intro.sh' go" \
        < /dev/null > /dev/null 2>&1 &
    exit 0
fi
qs list --all 2>/dev/null | grep -q "astrax-power-wave/shell.qml" || { qs -c astrax-power-wave -d >/dev/null 2>&1; sleep 0.4; }
exec qs -c astrax-power-wave ipc call wave preview
