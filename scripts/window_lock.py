#!/usr/bin/env python3
"""SUPER+R: pins the focused window (size, position, monitor and workspace).

  window_lock.py toggle   -> pins/unpins the active window (makes it float)
  window_lock.py daemon   -> every 0.3s puts pinned windows back in place

State in ~/.local/state/window-locks.json, by address. If the window's monitor
disappears (HDMI unplugged) wherever Hyprland sends it is accepted and it's
re-pinned there; it's the only allowed way to change screens."""

import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.expanduser("~/scripts"))
from hypr_ipc import hyprctl_json, dispatch  # noqa: E402

STATE = os.path.expanduser("~/.local/state/window-locks.json")
INTERVAL_S = 0.3


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save(locks):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(locks, f)
    os.replace(tmp, STATE)


def notify(msg):
    subprocess.Popen(["notify-send", "-a", "Window lock", "-t", "1500", msg],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def snapshot(win):
    return {
        "at": win["at"], "size": win["size"],
        "workspace": win["workspace"]["id"], "monitor": win["monitor"],
        "title": win.get("title", ""),
    }


def toggle():
    win = hyprctl_json(["activewindow"])
    if not win or not win.get("address"):
        return
    addr = win["address"]
    locks = load()
    if addr in locks:
        was_tiled = locks.pop(addr).get("was_tiled")
        save(locks)
        if was_tiled and win.get("floating"):
            dispatch(f'hl.dsp.window.float({{ action = "toggle", window = "address:{addr}" }})')
        notify("Window unpinned")
        return
    if not win.get("floating"):
        # float without changing size/place: we re-apply the tiled geometry
        dispatch(f'hl.dsp.window.float({{ action = "toggle", window = "address:{addr}" }})')
        sel = f'"address:{addr}"'
        dispatch(f"hl.dsp.window.resize({{ window = {sel}, x = {win['size'][0]}, y = {win['size'][1]}, relative = false }})")
        dispatch(f"hl.dsp.window.move({{ window = {sel}, x = {win['at'][0]}, y = {win['at'][1]}, relative = false }})")
    locks[addr] = snapshot(win)
    locks[addr]["was_tiled"] = not win.get("floating")
    save(locks)
    notify("Window pinned")


def enforce():
    locks = load()
    if not locks:
        return
    clients = {c["address"]: c for c in (hyprctl_json(["clients"]) or [])}
    monitors = {m["id"] for m in (hyprctl_json(["monitors"]) or [])}
    changed = False
    for addr in list(locks):
        lock, win = locks[addr], clients.get(addr)
        if not win:
            del locks[addr]  # window closed
            changed = True
            continue
        sel = f'"address:{addr}"'
        if lock["monitor"] not in monitors:
            # the HDMI went away: accept the new place and re-pin it there
            locks[addr] = {**snapshot(win), "was_tiled": lock.get("was_tiled")}
            changed = True
            continue
        if not win.get("floating"):
            dispatch(f'hl.dsp.window.float({{ action = "toggle", window = {sel} }})')
        if win["workspace"]["id"] != lock["workspace"]:
            dispatch(f"hl.dsp.window.move({{ window = {sel}, workspace = '{lock['workspace']}' }})")
        if win["size"] != lock["size"]:
            dispatch(f"hl.dsp.window.resize({{ window = {sel}, x = {lock['size'][0]}, y = {lock['size'][1]}, relative = false }})")
        if win["at"] != lock["at"] or win["size"] != lock["size"] or win["workspace"]["id"] != lock["workspace"]:
            dispatch(f"hl.dsp.window.move({{ window = {sel}, x = {lock['at'][0]}, y = {lock['at'][1]}, relative = false }})")
    if changed:
        save(locks)


def daemon():
    save({})  # addresses don't survive a Hyprland restart
    while True:
        try:
            enforce()
        except Exception as e:
            print(f"enforce error: {e}", flush=True)
        time.sleep(INTERVAL_S)


if __name__ == "__main__":
    {"toggle": toggle, "daemon": daemon}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
