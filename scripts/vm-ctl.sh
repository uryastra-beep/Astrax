#!/usr/bin/env bash
# vm-ctl.sh: temporary switch (runtime only, doesn't survive a reboot)
# between the Caelestia shell and Serpantinum inside the current Hyprland session.

SERPANTINUMD="$HOME/.local/bin/serpantinumd"
LOG="/tmp/serpantinumd-vm.log"

is_serpantium_running() {
    "$SERPANTINUMD" status >/dev/null 2>&1 || pgrep -f "quickshell.*serpantinum" >/dev/null 2>&1
}

is_caelestia_running() {
    pgrep -f "qs -c caelestia" >/dev/null 2>&1
}

# serpantinumd's own "stop" resolves the main QML with a `find` that doesn't
# always find the same file that was left running, so it
# sometimes leaves the process alive fighting Caelestia for shortcuts/focus. That's why
# we don't rely only on `serpantinumd stop` here: we finish off by pattern everything
# hanging from the Serpantinum folder.
force_kill_serpantium() {
    "$SERPANTINUMD" stop >/dev/null 2>&1
    pkill -TERM -f "quickshell.*serpantinum" 2>/dev/null
    pkill -TERM -f "serpantinum/src/quickshell" 2>/dev/null
    pkill -TERM -f "serpantinum/src/scripts/current_focus.sh" 2>/dev/null
    pkill -TERM -f "inotifywait.*serpantinum" 2>/dev/null
    pkill -TERM -f "focus_daemon.py" 2>/dev/null
    pkill -TERM -f "kb_wait.sh" 2>/dev/null
    sleep 0.4
    pkill -KILL -f "quickshell.*serpantinum" 2>/dev/null
    pkill -KILL -f "serpantinum/src/quickshell" 2>/dev/null
    pkill -KILL -f "serpantinum/src/scripts/current_focus.sh" 2>/dev/null
    pkill -KILL -f "inotifywait.*serpantinum" 2>/dev/null
    pkill -KILL -f "focus_daemon.py" 2>/dev/null
    pkill -KILL -f "kb_wait.sh" 2>/dev/null
    rm -f /tmp/serpantinumd.pid /tmp/serpantinumd.lock 2>/dev/null
}

current_vm() {
    if is_serpantium_running; then
        echo "serpantinum"
    elif is_caelestia_running; then
        echo "caelestia"
    else
        echo "none"
    fi
}

cmd_status() {
    local cur
    cur="$(current_vm)"
    case "$cur" in
        serpantinum) echo "Current VM: serpantium" ;;
        caelestia)   echo "Current VM: caelestia" ;;
        *)           echo "Current VM: none (no running shell detected)" ;;
    esac
}

cmd_caelestia() {
    if [ "$(current_vm)" = "caelestia" ]; then
        echo "Already on Caelestia."
        return 0
    fi

    echo "Stopping Serpantinum (if anything is running)..."
    force_kill_serpantium
    sleep 0.5

    local attempt
    for attempt in 1 2; do
        if is_caelestia_running; then
            break
        fi
        echo "Iniciando Caelestia..."
        caelestia shell -d >/dev/null 2>&1

        local count=0
        while [ "$count" -lt 20 ]; do
            if is_caelestia_running; then
                break
            fi
            sleep 0.2
            ((count++))
        done
    done

    # confirm it's still alive a moment later (avoids false positives
    # from an instance that starts and dies by itself due to a stale socket)
    sleep 1
    if is_caelestia_running; then
        echo "Current VM: caelestia"
    else
        echo "[!] Caelestia does not seem to have started, check manually."
        return 1
    fi
}

cmd_serpantium() {
    if [ "$(current_vm)" = "serpantinum" ]; then
        echo "Already on Serpantinum."
        return 0
    fi

    if is_caelestia_running; then
        echo "Deteniendo Caelestia..."
        caelestia shell -k >/dev/null 2>&1
        sleep 0.3
    fi

    echo "Iniciando Serpantinum..."
    setsid nohup "$SERPANTINUMD" start >"$LOG" 2>&1 < /dev/null &
    disown

    local count=0
    while [ "$count" -lt 20 ]; do
        if is_serpantium_running; then
            break
        fi
        sleep 0.2
        ((count++))
    done

    if is_serpantium_running; then
        echo "Current VM: serpantium"
    else
        echo "[!] Serpantinum does not seem to have started, check $LOG"
        return 1
    fi
}

case "$1" in
    caelestia)  cmd_caelestia ;;
    serpantium) cmd_serpantium ;;
    status)     cmd_status ;;
    *)
        echo "Usage: vm {caelestia|serpantium|status}"
        exit 1
        ;;
esac
