#!/usr/bin/env bash
# When waking from suspend/hibernate WITHOUT a lock screen (e.g. laptop
# lid), plays the intro. If it was locked, the intro plays on
# unlock (Lock.qml) -- nothing is done here.
# Listens to logind's PrepareForSleep(false). Autostarted with flock.
lockfile="${XDG_RUNTIME_DIR:-/tmp}/serpantinum/lock/locked"
gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 2>/dev/null |
while read -r line; do
    case "$line" in
        *PrepareForSleep*false*)
            sleep 1
            [ -e "$lockfile" ] || bash ~/scripts/intro.sh
            ;;
    esac
done
