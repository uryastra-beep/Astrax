#!/usr/bin/env python3
"""Shows/hides the eww taskbar depending on where the mouse is (like
Windows: it only shows when you touch the bottom edge of the screen). It can be
forced with 'taskbar on' (always visible) or 'taskbar off' (always hidden)
via ~/.local/state/taskbar-power; without that file, it's automatic by mouse.

One independent eww window per monitor (taskbar-<name>), so each
screen shows/hides its own based on where the cursor is."""

import json
import os
import subprocess
import time

POWER_STATE_FILE = os.path.expanduser("~/.local/state/taskbar-power")
BAR_HEIGHT_PX = 46          # must match the real height of the eww window
POLL_SECONDS = 0.1

_open_state = {}  # monitor name -> bool (whether it's open right now)


def power_state():
    try:
        with open(POWER_STATE_FILE) as f:
            v = f.read().strip()
            if v in ("on", "off"):
                return v
    except FileNotFoundError:
        pass
    return "auto"


def hyprctl_json(args):
    try:
        r = subprocess.run(["hyprctl"] + args + ["-j"], capture_output=True, text=True, timeout=2)
        return json.loads(r.stdout) if r.stdout.strip() else None
    except Exception:
        return None


def eww_window_name(monitor_name):
    return f"taskbar-{monitor_name}"


def set_window(monitor_name, visible):
    key = monitor_name
    if _open_state.get(key) == visible:
        return
    win = eww_window_name(monitor_name)
    try:
        subprocess.run(["eww", "open" if visible else "close", win],
                        capture_output=True, timeout=2)
        _open_state[key] = visible
    except Exception:
        pass


def sync():
    monitors = hyprctl_json(["monitors"]) or []
    state = power_state()

    if state == "off":
        for m in monitors:
            set_window(m["name"], False)
        return

    if state == "on":
        for m in monitors:
            set_window(m["name"], True)
        return

    # auto: show only on the monitor whose bottom edge the mouse is touching
    pos = hyprctl_json(["cursorpos"])
    if pos is None:
        return
    cx, cy = pos.get("x", -1), pos.get("y", -1)

    for m in monitors:
        mx, my = m.get("x", 0), m.get("y", 0)
        mw, mh = m.get("width", 0), m.get("height", 0)
        scale = m.get("scale", 1) or 1
        logical_w, logical_h = mw / scale, mh / scale
        inside_x = mx <= cx < mx + logical_w
        near_bottom = cy >= my + logical_h - BAR_HEIGHT_PX
        set_window(m["name"], inside_x and near_bottom)


def main():
    time.sleep(1)  # wait for the eww daemon to be up
    while True:
        try:
            sync()
        except Exception as e:
            print(f"sync error: {e}", flush=True)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
