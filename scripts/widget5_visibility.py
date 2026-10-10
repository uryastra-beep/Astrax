#!/usr/bin/env python3
"""Visibility watcher for widgets5 -- simplified clone of
widget4_visibility.py (see that file for the full detail of each
design decision), ONLY FOR p2 (HDMI-A-1):

  A) the target workspace is the ACTIVE WORKSPACE right now on HDMI-A-1
     -> show term+unimatrix+lavat. Otherwise -> hide the 3 (move to
     special:widgets5, never kill -- the terminal keeps its history).
  B) geometry snap every 2s -- same mechanism
     of "hl.dsp.window.resize/move" as widget4_visibility.py, but with
     a single set of coordinates (this is p2-only, no per-monitor
     variation).

Unlike widget4_visibility.py: there's NO rule B (hide term if
there's a real app -- that workspace is dedicated to widgets5, apps aren't
expected to live there) nor rule C (lavat is never hidden, only its
color changes -- handled by border_colors.py writing /tmp/widget-colors.json,
which widget5-ctl.sh already reads when launching lavat)."""

import json
import os
import socket
import subprocess
import time

WORKSPACE_FILE = os.path.expanduser("~/.config/widgets5/workspace")
POWER_STATE_FILE = os.path.expanduser("~/.local/state/widget5-power")

SPECIAL_WS = "special:widgets5"
ALL_KITTY_CLASSES = ("widget5-term", "widget5-unimatrix", "widget5-lavat")
MONITOR = "HDMI-A-1"

# Original geometry taken live --
# it must match windowrules.lua if changed. lavat fills
# 100% of ITS OWN window (window_padding_width=0 in widget5-ctl.sh), it doesn't
# grow to cover the terminal window.
LOCKED_GEOMETRY = {
    "widget5-term": (20, 582, 647, 495),
    "widget5-unimatrix": (1406, 15, 504, 627),
    "widget5-lavat": (22, 16, 649, 538),
}
SNAP_INTERVAL_S = 2

RELEVANT_EVENT_PREFIXES = ("openwindow", "closewindow", "movewindow", "workspace", "focusedmon", "monitoradded")


def widgets5_powered_off():
    try:
        with open(POWER_STATE_FILE) as f:
            return f.read().strip() == "off"
    except FileNotFoundError:
        return False


def target_workspace_id():
    try:
        with open(WORKSPACE_FILE) as f:
            v = f.read().strip()
        return int(v) if v else None
    except (FileNotFoundError, ValueError):
        return None


def hyprctl_json(args):
    r = subprocess.run(["hyprctl"] + args + ["-j"], capture_output=True, text=True, timeout=2)
    return json.loads(r.stdout) if r.stdout.strip() else None


def workspaces():
    return hyprctl_json(["workspaces"]) or []


def monitors():
    return hyprctl_json(["monitors"]) or []


def clients():
    return hyprctl_json(["clients"]) or []


def monitor_origin(mon):
    for m in monitors():
        if m.get("name") == mon:
            return (m.get("x", 0), m.get("y", 0))
    return None


def workspace_monitor(ws_id):
    for w in workspaces():
        if w.get("id") == ws_id:
            return w.get("monitor")
    return None


def monitor_active_workspace_id(mon):
    for m in monitors():
        if m.get("name") == mon:
            return m.get("activeWorkspace", {}).get("id")
    return None


def class_pids(cls):
    r = subprocess.run(["pgrep", "-f", f"kitty --class {cls} -o"], capture_output=True, text=True)
    return [p for p in r.stdout.split() if p]


def move_window(cls, workspace):
    # see the "movetoworkspacesilent" note in widget4_visibility.py -- the
    # hl.dsp.window.move equivalent FOCUSES the target workspace, which
    # is exactly the opposite of what we want when hiding in a special.
    lua = f"hl.dsp.exec_raw('movetoworkspacesilent', '{workspace},class:^({cls})$')"
    subprocess.run(["hyprctl", "dispatch", lua], capture_output=True, timeout=3)


def hide_class(cls):
    if class_pids(cls):
        move_window(cls, SPECIAL_WS)


def show_class(cls, ws_id):
    if class_pids(cls):
        move_window(cls, str(ws_id))


def snap_locked_geometry(ws_id):
    origin = monitor_origin(MONITOR)
    if not origin:
        return
    origin_x, origin_y = origin
    by_class = {}
    for w in clients():
        cls = w.get("class", "")
        if cls in LOCKED_GEOMETRY:
            by_class[cls] = w
    for cls, (x, y, w_, h_) in LOCKED_GEOMETRY.items():
        win = by_class.get(cls)
        if not win:
            continue
        gx, gy = origin_x + x, origin_y + y
        at = win.get("at") or [None, None]
        size = win.get("size") or [None, None]
        wrong_ws = win.get("workspace", {}).get("id") != ws_id
        if not wrong_ws and [at[0], at[1], size[0], size[1]] == [gx, gy, w_, h_]:
            continue
        if wrong_ws:
            move_window(cls, str(ws_id))
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


_last_active = None  # cache: avoid repeating extra hide/show


def sync():
    global _last_active
    try:
        if widgets5_powered_off():
            return

        ws_id = target_workspace_id()
        if ws_id is None:
            return

        mon = workspace_monitor(ws_id)
        is_active = bool(mon) and monitor_active_workspace_id(mon) == ws_id

        if is_active == _last_active:
            return

        if is_active:
            for cls in ALL_KITTY_CLASSES:
                show_class(cls, ws_id)
        else:
            for cls in ALL_KITTY_CLASSES:
                hide_class(cls)
        _last_active = is_active
    except Exception as e:
        print(f"sync error: {e}", flush=True)


def maybe_snap():
    if widgets5_powered_off():
        return
    if not _last_active:
        return
    ws_id = target_workspace_id()
    if ws_id is None:
        return
    snap_locked_geometry(ws_id)


def get_socket_path():
    sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return f"{runtime}/hypr/{sig}/.socket2.sock"


def main():
    time.sleep(1)
    sync()
    maybe_snap()
    try:
        sock_path = get_socket_path()
    except Exception as e:
        print(f"fatal: couldn't resolve the Hyprland socket: {e}", flush=True)
        raise
    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(sock_path)
                s.settimeout(SNAP_INTERVAL_S)
                buf = b""
                while True:
                    try:
                        data = s.recv(4096)
                    except socket.timeout:
                        maybe_snap()
                        continue
                    if not data:
                        break
                    buf += data
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        event = line.decode(errors="ignore")
                        if not event.startswith(RELEVANT_EVENT_PREFIXES):
                            continue
                        time.sleep(0.05)
                        sync()
        except Exception as e:
            print(f"socket error: {e}, retrying in 2s", flush=True)
            time.sleep(2)


if __name__ == "__main__":
    main()
