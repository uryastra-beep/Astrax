#!/usr/bin/env bash

# outro + lock before hibernating (custom): on return, the intro plays on unlock
LOCK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lock.sh"
[ -f "$LOCK_SCRIPT" ] && { bash "$LOCK_SCRIPT"; lock_rc=$?; sleep 0.5; }

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
    notify-send -u critical "Couldn't lock" "Cancelled: not hibernating with the session unlocked" 2>/dev/null
    exit 1
fi

if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    systemctl hibernate && exit 0
fi

if command -v loginctl &>/dev/null; then
    loginctl hibernate && exit 0
fi

if command -v dbus-send &>/dev/null; then
    dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Hibernate boolean:true 2>/dev/null && exit 0
fi

if command -v ZZZ &>/dev/null; then
    ZZZ && exit 0
fi

if [ -w /sys/power/state ]; then
    echo disk > /sys/power/state
fi
