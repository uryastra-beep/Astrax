#!/usr/bin/env python3
"""For the Settings genie: the monitor under the cursor + the centre of the Settings icon on its Dock.
Prints "MONITOR gx,gy" (global coords), or just "MONITOR" if the Dock has no such icon."""
import json, subprocess

def hj(*a):
    try:
        return json.loads(subprocess.run(["hyprctl", *a, "-j"], capture_output=True, text=True, timeout=2).stdout)
    except Exception:
        return None

mons = hj("monitors") or []
cur = hj("cursorpos") or {}
mon = None
for m in mons:
    sc = m.get("scale", 1) or 1
    w, h = m["width"] / sc, m["height"] / sc
    if m["x"] <= cur.get("x", -1e9) < m["x"] + w and m["y"] <= cur.get("y", -1e9) < m["y"] + h:
        mon = m
        break
mon = mon or next((m for m in mons if m.get("focused")), mons[0] if mons else None)
if not mon:
    raise SystemExit(0)
name = mon["name"]

def ipc(*a):
    try:
        return subprocess.run(["qs", "ipc", "-c", "astrax-mac-dock", "call", "dock", *a], capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return ""

ipc("reveal")
import time
out = ""
for _ in range(4):
    time.sleep(0.1)
    out = ipc("iconPos", "astrax-settings", name)
    if "," in out:
        break
print(name + (" " + out if "," in out else ""))
