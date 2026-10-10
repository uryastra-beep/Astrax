#!/usr/bin/env python3
"""Closes the desktop widgets (widget-clock, widget-lavat) only when the
monitor they ARE on (either of the 2, laptop or external) has another
window open on its active workspace. If the app opens on the OTHER
monitor, or you switch workspace there, the widgets aren't touched. Uses
widget-ctl.sh (off/play) to close/relaunch them, and remembers which
monitor they live on in /tmp/widget-home-monitor so it can decide even while
they're closed.

cava and sptlrx were removed from widget-ctl.sh (see that script) --
Real BUG found live (external audit): this file STILL
expected "widget-cava" in expected_widget_classes(), which was never going to be
running again -- that made "issubset(running_classes)" return
False ALWAYS, and the watcher ended up asking for "widgets play" on every
relevant Hyprland event (a constant trigger, though it didn't break anything
visible because widget-ctl.sh no longer knows how to spawn widget-cava)."""

import json
import os
import socket
import subprocess
import time

WIDGET_CTL = os.path.expanduser("~/scripts/widget-ctl.sh")
STATE_FILE = "/tmp/widget-home-monitor"
GLOW_STATE_FILE = os.path.expanduser("~/.local/state/widget-glow")
POWER_STATE_FILE = os.path.expanduser("~/.local/state/widget-power")
BASE_CLASSES = ("widget-clock", "widget-lavat")
RELEVANT_EVENT_PREFIXES = ("openwindow", "closewindow", "movewindow", "workspace", "focusedmon", "monitoradded")


def widgets_powered_off():
    """True if you ran 'widgets off': they stay off and this watcher
    must not relaunch them until a 'widgets play' writes 'on' to the file."""
    try:
        with open(POWER_STATE_FILE) as f:
            return f.read().strip() == "off"
    except FileNotFoundError:
        return False


def glow_enabled():
    try:
        with open(GLOW_STATE_FILE) as f:
            return f.read().strip() != "off"
    except FileNotFoundError:
        return True


def gamemode_enabled():
    try:
        r = subprocess.run(["caelestia", "shell", "gameMode", "isEnabled"],
                            capture_output=True, text=True, timeout=2)
        return r.stdout.strip() == "true"
    except Exception:
        return False


def expected_widget_classes():
    # with gamemode on the ghosts are suspended on purpose
    # (gamemode_watcher.py handles it); don't count them as "missing" here.
    # lavat has no ghost (see widget-ctl.sh), only clock.
    if glow_enabled() and not gamemode_enabled():
        return set(BASE_CLASSES) | {"widget-clock-ghost"}
    return set(BASE_CLASSES)


def get_socket_path():
    sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return f"{runtime}/hypr/{sig}/.socket2.sock"


def hyprctl_json(args):
    r = subprocess.run(["hyprctl"] + args + ["-j"], capture_output=True, text=True, timeout=2)
    return json.loads(r.stdout) if r.stdout.strip() else None


def monitors():
    return hyprctl_json(["monitors"]) or []


def clients():
    return hyprctl_json(["clients"]) or []


def running_widgets():
    """List of clients of THIS widget set running right now (doesn't
    include other sets like widget2-ctl.sh, which are handled separately)."""
    return [w for w in clients() if w.get("class", "") in BASE_CLASSES]


def widget_monitor_ids(widgets=None):
    """Set of monitor ids with widgets running right now (empty if none is running)."""
    ws = widgets if widgets is not None else running_widgets()
    return {w.get("monitor") for w in ws}


def load_home_monitor_name():
    # READ only: this file is written by widget-ctl.sh (p1/p2), never by this
    # watcher. If it doesn't exist yet (first boot), falls back to the focused monitor.
    try:
        with open(STATE_FILE) as f:
            name = f.read().strip()
            if name:
                return name
    except Exception:
        pass
    ms = monitors()
    for m in ms:
        if m.get("focused"):
            return m.get("name")
    return ms[0]["name"] if ms else None


def monitor_active_workspace_id(name):
    for m in monitors():
        if m.get("name") == name:
            return m.get("activeWorkspace", {}).get("id")
    return None


IGNORED_CLASSES = ("kitty",)  # terminals: don't count as "busy screen"


def monitor_is_busy(name):
    ws_id = monitor_active_workspace_id(name)
    if ws_id is None:
        return False
    for w in clients():
        cls = w.get("class", "")
        if cls.startswith("widget-") or cls in IGNORED_CLASSES:
            continue
        if w.get("workspace", {}).get("id") == ws_id:
            return True
    return False


def focus_monitor(name):
    subprocess.run(["hyprctl", "dispatch", f'hl.dsp.focus({{ monitor = "{name}" }})'],
                   capture_output=True)
    time.sleep(0.15)


COOLDOWN_FILE = "/tmp/widget-ctl-cooldown"
COOLDOWN_SECONDS = 3.0


def in_cooldown():
    """True if widget-ctl.sh (this or another invocation, e.g. a manual p1/p2) is
    acting right now: keeps this watcher from competing and duplicating windows."""
    try:
        return (time.time() - os.path.getmtime(COOLDOWN_FILE)) < COOLDOWN_SECONDS
    except FileNotFoundError:
        return False


MANUAL_CLOSE_COOLDOWN_FILE = "/tmp/widget-manual-close-cooldown"
MANUAL_CLOSE_COOLDOWN_SECONDS = 5.0


def in_manual_close_cooldown():
    """True if a widget was closed by hand (e.g. Super+Q) less than 5s ago.
    Set by windowrules.lua -> widget-close-guard.sh, ONLY when the close didn't
    come from one of our restarts (song change, glow, etc); in that other
    case this file isn't touched and the respawn stays immediate."""
    try:
        return (time.time() - os.path.getmtime(MANUAL_CLOSE_COOLDOWN_FILE)) < MANUAL_CLOSE_COOLDOWN_SECONDS
    except FileNotFoundError:
        return False


def run_ctl(action):
    subprocess.run([WIDGET_CTL, action], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def sync():
    try:
        if widgets_powered_off():
            # turned off on purpose by 'widgets off': don't touch anything
            return

        # "home" is ALWAYS the last monitor set by hand (widgets p1/p2).
        # This watcher never redefines it by itself based on where the
        # widgets happen to be running at a given moment -- that's exactly what caused
        # switching workspace (focus crossing monitors) to end up "adopting"
        # that screen as the new correct one. It's only used to BRING THEM
        # back if they drifted, never to move the destination.
        home = load_home_monitor_name()
        if home is None:
            return

        widgets = running_widgets()
        mon_ids = widget_monitor_ids(widgets)
        running_classes = {w.get("class") for w in widgets}

        home_mon_id = None
        for m in monitors():
            if m.get("name") == home:
                home_mon_id = m.get("id")
                break

        # Drift: widgets running spread across more than one monitor, or all
        # together but on the wrong monitor (not the set "home").
        if mon_ids and (len(mon_ids) > 1 or (home_mon_id is not None and home_mon_id not in mon_ids)):
            run_ctl("hide")
            time.sleep(0.3)
            focus_monitor(home)
            run_ctl("play")
            return

        if monitor_is_busy(home):
            if running_classes:
                run_ctl("hide")
        else:
            # relaunch if ANY of the expected ones is missing, not only if nothing is there
            # (e.g. you closed the clock by hand but lavat is still alive)
            if not expected_widget_classes().issubset(running_classes):
                if in_manual_close_cooldown():
                    return
                focus_monitor(home)
                run_ctl("play")
    except Exception as e:
        print(f"sync error: {e}", flush=True)


def main():
    time.sleep(1)
    sync()

    sock_path = get_socket_path()
    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(sock_path)
                buf = b""
                while True:
                    data = s.recv(4096)
                    if not data:
                        break
                    buf += data
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        event = line.decode(errors="ignore")
                        if not event.startswith(RELEVANT_EVENT_PREFIXES):
                            continue
                        if "widget-" in event:
                            # opening/closing of our own widgets, not of a real app
                            continue
                        if in_cooldown():
                            # widget-ctl.sh is acting right now (ours or manual/p1/p2)
                            continue
                        time.sleep(0.08)
                        sync()
        except Exception as e:
            print(f"socket error: {e}, retrying in 2s", flush=True)
            time.sleep(2)


if __name__ == "__main__":
    main()
