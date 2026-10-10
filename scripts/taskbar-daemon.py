#!/usr/bin/env python3
"""Combined taskbar daemon: prints a JSON line to stdout every
time something changes (open apps, active window, song playing). eww
runs it directly via deflisten (no separate autostart needed).

Emitted JSON:
{
  "apps": [{"class": "firefox", "title": "...", "icon": "/path/to/icon.png"}, ...],
  "active_class": "firefox",
  "active_title": "...",
  "song": "Artist - Song"   (empty string if there's no active player)
}
"""

import json
import os
import subprocess
import sys
import time

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

APP_DIRS = [
    "/usr/share/applications",
    "/usr/local/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
]

_icon_theme = Gtk.IconTheme.get_default()
_icon_cache = {}


def _parse_desktop_file(path):
    """Extracts Name/Icon/StartupWMClass from the [Desktop Entry] section."""
    name = icon = wmclass = None
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            in_entry = False
            for line in f:
                line = line.strip()
                if line == "[Desktop Entry]":
                    in_entry = True
                    continue
                if line.startswith("[") and line != "[Desktop Entry]":
                    if in_entry:
                        break
                    continue
                if not in_entry or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                key = key.strip()
                if key == "Name" and name is None:
                    name = val.strip()
                elif key == "Icon":
                    icon = val.strip()
                elif key == "StartupWMClass":
                    wmclass = val.strip()
    except Exception:
        pass
    return name, icon, wmclass


def _build_desktop_index():
    """lowercase-class -> (name, icon-name). Indexes by StartupWMClass AND
    by the .desktop file name, which is what most often matches
    the window's real wm_class."""
    by_class = {}
    for d in APP_DIRS:
        if not os.path.isdir(d):
            continue
        for fname in os.listdir(d):
            if not fname.endswith(".desktop"):
                continue
            path = os.path.join(d, fname)
            name, icon, wmclass = _parse_desktop_file(path)
            if not icon:
                continue
            base = fname[: -len(".desktop")].lower()
            by_class.setdefault(base, (name, icon))
            if wmclass:
                by_class.setdefault(wmclass.lower(), (name, icon))
    return by_class


_desktop_index = _build_desktop_index()


def resolve_icon(wm_class):
    """wm_class -> (display_name, icon-file-path). Caches per
    class so the GTK lookup isn't repeated on every tick."""
    if wm_class in _icon_cache:
        return _icon_cache[wm_class]

    lower = wm_class.lower()
    name, icon_name = _desktop_index.get(lower, (None, None))

    if not icon_name:
        # fuzzy: look for an index key that contains or is contained
        # in the wm_class (e.g. "brave-browser" vs entry "brave")
        for key, val in _desktop_index.items():
            if key in lower or lower in key:
                name, icon_name = val
                break

    icon_path = None
    candidate = icon_name or wm_class
    if candidate:
        if os.path.isabs(candidate) and os.path.isfile(candidate):
            icon_path = candidate
        else:
            gtk_icon = _icon_theme.lookup_icon(candidate, 48, 0)
            if gtk_icon:
                icon_path = gtk_icon.get_filename()

    if not icon_path:
        gtk_icon = _icon_theme.lookup_icon("application-x-executable", 48, 0)
        icon_path = gtk_icon.get_filename() if gtk_icon else ""

    result = (name or wm_class, icon_path)
    _icon_cache[wm_class] = result
    return result


IGNORED_CLASSES = {"kitty"}  # the kitty widgets (widget-*) are also filtered separately


def hyprctl_json(args):
    try:
        r = subprocess.run(["hyprctl"] + args + ["-j"], capture_output=True, text=True, timeout=2)
        return json.loads(r.stdout) if r.stdout.strip() else None
    except Exception:
        return None


def get_apps():
    clients = hyprctl_json(["clients"]) or []
    seen = set()
    apps = []
    for c in clients:
        cls = c.get("class", "")
        if not cls or cls.startswith("widget-") or cls in IGNORED_CLASSES:
            continue
        if cls in seen:
            continue
        seen.add(cls)
        name, icon = resolve_icon(cls)
        apps.append({"class": cls, "title": name, "icon": icon or ""})
    return apps


def get_active_window():
    aw = hyprctl_json(["activewindow"])
    if not aw or not aw.get("class"):
        return None, None
    return aw.get("class"), aw.get("title", "")


def get_song():
    try:
        r = subprocess.run(["caelestia", "shell", "mpris", "list"], capture_output=True, text=True, timeout=2)
        if not r.stdout.strip():
            return ""
        title = subprocess.run(["caelestia", "shell", "mpris", "getActive", "trackTitle"],
                                capture_output=True, text=True, timeout=2).stdout.strip()
        artist = subprocess.run(["caelestia", "shell", "mpris", "getActive", "trackArtist"],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
        if title in ("", "Invalid property"):
            return ""
        if artist and artist != "Invalid property":
            return f"{artist} - {title}"
        return title
    except Exception:
        return ""


# Space rules: icons shrink as
# apps are added; if that's not enough, "Now on:" disappears first
# and then the song name. All precomputed here (not in eww) so
# it can be tested with a simple `python3 -c` without relying on eww working.
ICON_MAX_PX = 40
ICON_MIN_PX = 20
SHRINK_PER_APP_AFTER = 4     # from the 5th app on it starts shrinking
HIDE_NOWON_AFTER_APPS = 10   # with 10+ apps, "Now on:" is hidden
HIDE_SONG_AFTER_APPS = 14    # with 14+ apps, the song name is hidden


def compute_layout(n_apps):
    icon_px = max(ICON_MIN_PX, min(ICON_MAX_PX, ICON_MAX_PX - max(0, n_apps - SHRINK_PER_APP_AFTER) * 3))
    return {
        "icon_px": icon_px,
        "show_nowon": n_apps < HIDE_NOWON_AFTER_APPS,
        "show_song": n_apps < HIDE_SONG_AFTER_APPS,
    }


def main():
    last = None
    while True:
        try:
            active_class, active_title = get_active_window()
            apps = get_apps()
            data = {
                "apps": apps,
                "active_class": active_class or "",
                "active_title": active_title or "",
                "song": get_song(),
                "layout": compute_layout(len(apps)),
            }
            line = json.dumps(data)
            if line != last:
                print(line, flush=True)
                last = line
        except Exception as e:
            print(json.dumps({"apps": [], "active_class": "", "active_title": "", "song": "", "error": str(e)}), flush=True)
        time.sleep(1)


if __name__ == "__main__":
    main()
