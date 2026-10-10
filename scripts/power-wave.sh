#!/usr/bin/env bash
# Power-off wave (intro in reverse) before reboot/poweroff from places without "hold" (e.g. lock).
# Called by the patches in serpantinum/src/scripts/system/{reboot,poweroff}.sh.
[ -n "$POWER_WAVE_DONE" ] && exit 0
qs list --all 2>/dev/null | grep -q "astrax-power-wave/shell.qml" || { qs -c astrax-power-wave -d >/dev/null 2>&1; sleep 0.4; }
qs -c astrax-power-wave ipc call wave play >/dev/null 2>&1
# 3.5s rise + ~1.6s logo turning off (astrax-power-wave offAnim)
sleep 5.2
