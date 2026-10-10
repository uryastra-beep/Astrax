#!/usr/bin/env python3
"""Visibility watcher for widgets4 -- unlike widget_visibility.py
(which follows a MONITOR), this one follows a specific WORKSPACE (the one set by
'widgets4 play [workspace N]' / p1 / p2, in ~/.config/widgets4/workspace).
It doesn't follow focus or change workspace/monitor by itself -- it stays
tied to the target workspace until you change it
explicitly.

Two independent rules:
  A) the target workspace is the ACTIVE WORKSPACE right now on its monitor
     -> show everything (Now Playing/cava visual surface + term/btop/unimatrix).
     If it is NOT the active one (you're looking at another workspace) -> hide
     everything. This is what makes it "not follow workspaces": instead of moving
     the window, it hides when you leave its workspace.
  B) (only while A says "active") if there's a REAL app on that workspace
     -> hide ONLY term+btop (they're normal windows, they'd compete
     visually with the app). The visual surface (Now Playing/cava) and
     unimatrix (purely decorative, no_focus=true) are NOT hidden for
     this -- they don't compete with anything.

Hiding term/btop/unimatrix = moving them to a special workspace (scratchpad),
NEVER killing them -- so the terminal keeps its history/session.
Hiding the visual surface = an IPC call to Quickshell
(setVisible), also instant, also without killing the process.
"""

import json
import os
import socket
import subprocess
import time

SCRIPTS_DIR = os.path.expanduser("~/scripts")
WORKSPACE_FILE = os.path.expanduser("~/.config/widgets4/workspace")
POWER_STATE_FILE = os.path.expanduser("~/.local/state/widget4-power")

SPECIAL_WS = "special:widgets4"
HIDE_ON_APP_CLASSES = ("widget4-term", "widget4-btop")  # rule B
ALWAYS_WITH_A_CLASSES = ("widget4-unimatrix",)  # rule A only, like the old pipes
# widget4-lavat: rule C (new) -- only shown if the workspace is
# active (rule A) AND no mpris player is playing. It takes the
# same spot as the mini cava/Now Playing (see shell.qml), so it visually
# replaces the cava when there's no music.
LAVAT_CLASS = "widget4-lavat"
ALL_KITTY_CLASSES = HIDE_ON_APP_CLASSES + ALWAYS_WITH_A_CLASSES + (LAVAT_CLASS,)
IGNORED_CLASSES = ("kitty",) + ALL_KITTY_CLASSES  # a regular terminal doesn't count as "busy" either
PLAYER_CHECK_INTERVAL_S = 2

RELEVANT_EVENT_PREFIXES = ("openwindow", "closewindow", "movewindow", "workspace", "focusedmon", "monitoradded")

# Position/size "lock": being normal floating windows (not
# click-through, see the file header), Hyprland lets you drag/
# resize them with the mouse like any other -- if
# that happens (on purpose or by accident, e.g. while moving ANOTHER
# window and brushing them), they snap back by themselves instead of staying
# "misplaced". There's no Hyprland event for "finished dragging" a
# float (socket2 doesn't emit that), so instead of reacting to a specific
# event the geometry is RE-ASSERTED on every tick of the main loop
# (SNAP_INTERVAL_S) whatever caused the displacement.
# NOTE: these values must mirror the "move"/"size" in
# ~/.config/hypr/config/windowrules.lua for the same 3 classes -- if they
# change there, change them here too.
#
# Per MONITOR: the window_rule's "move"/"size" are relative to the monitor (not
# global), and term/btop/unimatrix currently use the SAME window_rule whatever
# the screen (p1 or p2) -- but a monitor without an entry here simply is NOT
# re-asserted (avoids the real bug that happened: when moving widgets4 to p1 with
# values meant only for p2, the snap yanked them back to a
# geometry that didn't belong to that screen).
LOCKED_GEOMETRY_BY_MONITOR = {
    "HDMI-A-1": {
        "widget4-term": (23, 458, 768, 603),
        "widget4-btop": (802, 23, 1097, 588),
        "widget4-unimatrix": (794, 625, 1095, 430),
        "widget4-lavat": (26, 21, 754, 417),  # same area as the Now Playing card on p2
    },
    "eDP-1": {
        "widget4-term": (21, 501, 659, 351),
        "widget4-btop": (682, 16, 835, 512),
        "widget4-unimatrix": (691, 533, 828, 322),
        "widget4-lavat": (8, 13, 660, 470),  # same area as the Now Playing card on p1
    },
}
SNAP_INTERVAL_S = 2


def widgets4_powered_off():
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


def snap_locked_geometry(ws_id, mon):
    # Compares the REAL position/size/workspace against the geometry set for
    # THIS monitor and only fixes what drifted -- cheap: if nobody touched
    # them, this is a no-op. If the current monitor has no entry in
    # LOCKED_GEOMETRY_BY_MONITOR (no values set yet for that
    # screen), it does nothing -- see the note above the constant.
    #
    # History of failed attempts before getting here (left as a
    # note so they aren't repeated):
    #   1) native "movewindowpixel"/"resizewindowpixel" via exec_raw with
    #      a class selector -- silently a NO-OP on a window that
    #      isn't focused (hyprctl returns "ok" anyway, but doesn't move
    #      anything). Focusing it first with exec_raw('focuswindow',
    #      'class:...') did NOT work EITHER -- that focuswindow with a selector
    #      didn't really focus anything either.
    #   2) Assigning "w.at = {x,y}" / "w.size = {w,h}" directly on the object
    #      from hl.get_windows(...) via "hyprctl repl" -- throws "attempt to
    #      modify read-only hl object" and most of the time does NOT apply
    #      the change (once it seemed to work due to a coincidence of
    #      values with a previous attempt, which produced a false
    #      confirmation).
    # What DOES work, confirmed live: the OBJECT dispatchers
    # hl.dsp.window.resize({window=..., x=W, y=H, relative=false}) and
    # hl.dsp.window.move({window=..., x=X, y=Y, relative=false}) -- these
    # DO accept the explicit window (they don't depend on focus), and the x/y of
    # BOTH are GLOBAL coordinates (not relative to the monitor -- that's why
    # the monitor origin is added here). Order matters: resize first, move
    # after -- resize can shift the "at" (anchors from the centre or something
    # like that), so if done the other way round the resize overrides the position
    # set by the move.
    geometry = LOCKED_GEOMETRY_BY_MONITOR.get(mon)
    if not geometry:
        return
    origin = monitor_origin(mon)
    if not origin:
        return
    origin_x, origin_y = origin
    by_class = {}
    for w in clients():
        cls = w.get("class", "")
        if cls in geometry:
            by_class[cls] = w
    for cls, (x, y, w_, h_) in geometry.items():
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


def workspace_has_real_app(ws_id):
    for w in clients():
        cls = w.get("class", "")
        if cls in IGNORED_CLASSES:
            continue
        if w.get("workspace", {}).get("id") == ws_id:
            return True
    return False


def qs_set_visible(visible):
    subprocess.run(
        ["qs", "ipc", "-c", "widgets4", "call", "widgets4", "setVisible", "true" if visible else "false"],
        capture_output=True, timeout=3,
    )


def class_pids(cls):
    r = subprocess.run(["pgrep", "-f", f"kitty --class {cls} -o"], capture_output=True, text=True)
    return [p for p in r.stdout.split() if p]


def move_window(cls, workspace):
    # Real BUG: "hl.dsp.window.move" turned out to be the
    # equivalent of "movetoworkspace" (NOT silent) -- besides moving the
    # window, it FOCUSES/SHOWS the target workspace. For a normal workspace
    # it's not noticeable, but for a SPECIAL one (special:widgets4, where this
    # watcher "hides" term/btop) the effect was the opposite of the goal: every
    # time it hid a window, it also REVEALED special:widgets4 on top
    # of everything (with the special workspace blur) -- exactly
    # what looked like "the widgets go on top of the apps".
    # Fix: go through "hl.dsp.exec_raw" to the native dispatcher
    # "movetoworkspacesilent" (verified it exists and doesn't need the object
    # from hl.get_windows -- the classic "class:^(...)$" selector is enough).
    lua = f"hl.dsp.exec_raw('movetoworkspacesilent', '{workspace},class:^({cls})$')"
    subprocess.run(["hyprctl", "dispatch", lua], capture_output=True, timeout=3)


def hide_class(cls):
    if class_pids(cls):
        move_window(cls, SPECIAL_WS)


def show_class(cls, ws_id):
    if class_pids(cls):
        move_window(cls, str(ws_id))


def has_player():
    try:
        r = subprocess.run(["playerctl", "status"], capture_output=True, text=True, timeout=2)
        return r.returncode == 0 and r.stdout.strip() != ""
    except Exception:
        return False


_last_state = None  # cache: (is_active_ws, has_real_app) to avoid extra dispatches
_last_lavat_shown = None  # separate cache: rule C is re-evaluated every PLAYER_CHECK_INTERVAL_S, not per event


def sync():
    global _last_state
    try:
        if widgets4_powered_off():
            return

        ws_id = target_workspace_id()
        if ws_id is None:
            return

        mon = workspace_monitor(ws_id)
        is_active = bool(mon) and monitor_active_workspace_id(mon) == ws_id

        if not is_active:
            state = (False, None)
            if state != _last_state:
                qs_set_visible(False)
                for cls in ALL_KITTY_CLASSES:
                    hide_class(cls)
                _last_state = state
                global _last_lavat_shown
                _last_lavat_shown = None  # re-evaluated from scratch the next time it becomes active
            return

        busy = workspace_has_real_app(ws_id)
        state = (True, busy)
        if state == _last_state:
            return

        qs_set_visible(True)  # the visual surface is always shown if the workspace is active
        for cls in ALWAYS_WITH_A_CLASSES:
            show_class(cls, ws_id)
        if busy:
            for cls in HIDE_ON_APP_CLASSES:
                hide_class(cls)
        else:
            for cls in HIDE_ON_APP_CLASSES:
                show_class(cls, ws_id)
        _last_state = state
    except Exception as e:
        print(f"sync error: {e}", flush=True)


def get_socket_path():
    sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return f"{runtime}/hypr/{sig}/.socket2.sock"


def maybe_snap():
    # Doesn't re-assert geometry if the set is off or if the target
    # workspace isn't the active one right now -- in that case the windows are
    # (correctly) hidden in SPECIAL_WS by sync()'s rule A, and
    # "fixing" their position there would bring them back to the real workspace,
    # undoing the hiding.
    if widgets4_powered_off():
        return
    if not (_last_state and _last_state[0]):
        return
    ws_id = target_workspace_id()
    if ws_id is None:
        return
    mon = workspace_monitor(ws_id)
    if mon:
        snap_locked_geometry(ws_id, mon)


def maybe_toggle_lavat():
    # Rule C: independent from Hyprland events (nothing signals when
    # music starts/stops), so it's re-checked on every tick of the main
    # loop (same interval as maybe_snap, PLAYER_CHECK_INTERVAL_S).
    global _last_lavat_shown
    if widgets4_powered_off():
        return
    if not (_last_state and _last_state[0]):
        return  # workspace not active -> lavat is already hidden by rule A
    ws_id = target_workspace_id()
    if ws_id is None:
        return
    want_lavat = not has_player()
    if want_lavat == _last_lavat_shown:
        return
    if want_lavat:
        show_class(LAVAT_CLASS, ws_id)
    else:
        hide_class(LAVAT_CLASS)
    _last_lavat_shown = want_lavat


def main():
    time.sleep(1)
    sync()
    maybe_snap()
    maybe_toggle_lavat()
    try:
        sock_path = get_socket_path()
    except Exception as e:
        print(f"fatal: couldn't resolve the Hyprland socket: {e}", flush=True)
        raise
    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(sock_path)
                # timeout != None -- so recv() returns periodically even if
                # no event arrives, and we can re-assert the
                # "locked" geometry without relying on a specific Hyprland
                # event for "finished dragging" (there's no such event
                # for floats -- see the comment in LOCKED_GEOMETRY).
                s.settimeout(SNAP_INTERVAL_S)
                buf = b""
                while True:
                    try:
                        data = s.recv(4096)
                    except socket.timeout:
                        maybe_snap()
                        maybe_toggle_lavat()
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
