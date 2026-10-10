#!/usr/bin/env bash
# Outro before lock/suspend/hibernate: the wave rises, the logo turns off and
# it stays COVERED (doesn't power anything off). Blocks ~5.1s until the animation ends.
# Removed by: intro.sh (on unlock / wake) or `ipc call wave clear`.
# Called by the patches in serpantinum/src/scripts/{lock.sh,system/hibernate.sh}.
[ -n "$ASTRAX_NO_OUTRO" ] && exit 0
qs list --all 2>/dev/null | grep -q "astrax-power-wave/shell.qml" || { qs -c astrax-power-wave -d >/dev/null 2>&1; sleep 0.4; }
qs -c astrax-power-wave ipc call wave cover >/dev/null 2>&1
# 3.5s rise + 1.5s logo turning off
sleep 5.1
