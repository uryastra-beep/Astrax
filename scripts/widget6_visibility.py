#!/usr/bin/env python3
"""widgets6 watcher -- simplified version of widget5_visibility.py
(see that file for the full detail of the pattern): every 2s it snaps
the widgets6 windows (p1 and/or p2, whatever is running) back to their
fixed geometry if they were dragged/resized by accident. Unlike
widgets4/5 there's NO hide/show per active workspace -- widgets6 doesn't use a
special workspace, it stays where you sent it with "widgets6 p1/p2"."""

import json
import os
import subprocess
import time

POWER_STATE_FILE = os.path.expanduser("~/.local/state/widget6-power")
SNAP_INTERVAL_S = 2

# Must match windowrules.lua (widgets6 p1/p2).
#
LOCKED_GEOMETRY = {
    "widget6-unimatrix":    ("eDP-1",    3,   4,   197,  856),
    "widget6-lavat":        ("eDP-1",    203, 3,   1331, 320),
    "widget6-btop":         ("eDP-1",    204, 326, 1329, 536),
    "widget6-p2-unimatrix": ("HDMI-A-1", 5,   1,   257,  1078),
    "widget6-p2-lavat":     ("HDMI-A-1", 266, 1,   1654, 340),
    "widget6-p2-btop":      ("HDMI-A-1", 265, 344, 1654, 738),
}


def widgets6_powered_off():
    try:
        with open(POWER_STATE_FILE) as f:
            return f.read().strip() == "off"
    except FileNotFoundError:
        return False


def hyprctl_json(args):
    r = subprocess.run(["hyprctl"] + args + ["-j"], capture_output=True, text=True, timeout=2)
    return json.loads(r.stdout) if r.stdout.strip() else None


def monitors():
    return hyprctl_json(["monitors"]) or []


def clients():
    return hyprctl_json(["clients"]) or []


def monitor_origin(mon):
    for m in monitors():
        if m.get("name") == mon:
            return (m.get("x", 0), m.get("y", 0))
    return None


def snap_locked_geometry():
    by_class = {w.get("class", ""): w for w in clients()}
    origins = {}

    for cls, (mon, x, y, w_, h_) in LOCKED_GEOMETRY.items():
        win = by_class.get(cls)
        if not win:
            continue

        if mon not in origins:
            origins[mon] = monitor_origin(mon)
        origin = origins[mon]
        if not origin:
            continue
        origin_x, origin_y = origin
        gx, gy = origin_x + x, origin_y + y

        at = win.get("at") or [None, None]
        size = win.get("size") or [None, None]
        if [at[0], at[1], size[0], size[1]] == [gx, gy, w_, h_]:
            continue

        win_sel = f"hl.get_windows({{ class = '{cls}' }})[1]"
        subprocess.run(
            ["hyprctl", "dispatch",
             f"hl.dsp.window.resize({{ window = {win_sel}, x = {w_}, y = {h_}, relative = false }})"],
            capture_output=True, timeout=3,
        )
        subprocess.run(
            ["hyprctl", "dispatch",
             f"hl.dsp.window.move({{ window = {win_sel}, x = {gx}, y = {gy}, relative = false }})"],
            capture_output=True, timeout=3,
        )


def main():
    while True:
        try:
            if not widgets6_powered_off():
                snap_locked_geometry()
        except Exception as e:
            print(f"snap error: {e}", flush=True)
        time.sleep(SNAP_INTERVAL_S)


if __name__ == "__main__":
    main()
