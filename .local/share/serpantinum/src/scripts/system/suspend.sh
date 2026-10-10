#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/lock.sh"

if [ -f "$LOCK_SCRIPT" ]; then
    # no & : lock.sh plays the outro (~5s) and only then locks
    bash "$LOCK_SCRIPT"; lock_rc=$?
    sleep 0.5
fi

# never sleep with the session unlocked: if the lock didn't engage (quickshell
# crashed, ipc failed) abort. Lock.qml creates "secure" only once the
# compositor confirms all screens are covered ("locked" only
# means the lock was requested).
LOCK_FLAG="${XDG_RUNTIME_DIR:-/tmp}/serpantinum/lock/secure"
for _ in $(seq 1 50); do
    [ -e "$LOCK_FLAG" ] && break
    sleep 0.1
done
if [ "${lock_rc:-1}" -ne 0 ] || [ ! -e "$LOCK_FLAG" ]; then
    notify-send -u critical "Couldn't lock" "Cancelled: not suspending with the session unlocked" 2>/dev/null
    exit 1
fi

if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    systemctl suspend && exit 0
fi

if command -v loginctl &>/dev/null; then
    loginctl suspend && exit 0
fi

if command -v dbus-send &>/dev/null; then
    dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend boolean:true 2>/dev/null && exit 0
fi

if command -v zzz &>/dev/null; then
    zzz && exit 0
fi

if [ -w /sys/power/state ]; then
    echo mem > /sys/power/state
fi
