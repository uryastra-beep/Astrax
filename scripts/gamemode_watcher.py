#!/usr/bin/env python3
"""While caelestia shell's gameMode is active, hides the ghost
widgets (less GPU load while gaming), turns off the blur/transparency
of Caelestia's panels (appearance.transparency in shell.json) and makes
windows 100% opaque (no wallpaper leaking behind YouTube
and friends). When gameMode turns off, everything is reverted."""

import json
import os
import re
import subprocess
import time

WIDGET_CTL = os.path.expanduser("~/scripts/widget-ctl.sh")
SHELL_CONFIG = os.path.expanduser("~/.config/caelestia/shell.json")
DECORATIONS_LUA = os.path.expanduser("~/.config/hypr/config/decorations.lua")
OPACITY_FALLBACK = {"active_opacity": 0.95, "inactive_opacity": 0.85}
POLL_SECONDS = 2
# value of transparency.enabled before entering gameMode; stored in a file so
# the restore is correct even if the watcher restarts midway
PREV_TRANSPARENCY_FILE = os.path.expanduser("~/.local/state/gamemode-prev-transparency")


def caelestia_active():
    """Caelestia's gameMode only exists while Caelestia is the running shell
    (`vm` can switch shells live) -- same rule as ~/scripts/active-shell.sh."""
    try:
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "astrax-shell")
        with open(path) as f:
            fsig, shell = f.readline().split()
        if sig and fsig == sig and shell in ("serpantinum", "caelestia"):
            return shell == "caelestia"
    except (OSError, ValueError):
        pass
    return os.environ.get("HYPR_SHELL") != "serpantinum"


def gamemode_enabled():
    if not caelestia_active():
        return False
    r = subprocess.run(["caelestia", "shell", "gameMode", "isEnabled"],
                        capture_output=True, text=True, timeout=3)
    return r.stdout.strip() == "true"


def run_ctl(action):
    subprocess.run([WIDGET_CTL, action], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def set_shell_transparency(enabled):
    """Turns appearance.transparency.enabled on/off in shell.json without touching
    the rest of the config -- caelestia shell reloads it by itself when it detects the
    change (same mechanism as any manual edit of the file)."""
    try:
        with open(SHELL_CONFIG) as f:
            config = json.load(f)
        config.setdefault("appearance", {}).setdefault("transparency", {})["enabled"] = enabled
        with open(SHELL_CONFIG, "w") as f:
            json.dump(config, f, indent=4)
    except Exception as e:
        print(f"error editing shell.json: {e}", flush=True)


def get_shell_transparency():
    try:
        with open(SHELL_CONFIG) as f:
            return bool(json.load(f).get("appearance", {}).get("transparency", {}).get("enabled", True))
    except Exception:
        return True


def save_prev_transparency():
    try:
        os.makedirs(os.path.dirname(PREV_TRANSPARENCY_FILE), exist_ok=True)
        with open(PREV_TRANSPARENCY_FILE, "w") as f:
            f.write("true" if get_shell_transparency() else "false")
    except Exception as e:
        print(f"error saving previous transparency: {e}", flush=True)


def pop_prev_transparency():
    try:
        with open(PREV_TRANSPARENCY_FILE) as f:
            value = f.read().strip() != "false"
        os.remove(PREV_TRANSPARENCY_FILE)
        return value
    except FileNotFoundError:
        return True


def configured_opacity():
    """Reads the opacity values from decorations.lua instead of keeping them
    in memory: that way the restore is still correct even if the watcher
    restarts with gameMode already on (the live values would be 1.0)."""
    values = dict(OPACITY_FALLBACK)
    try:
        with open(DECORATIONS_LUA) as f:
            source = f.read()
        for key in values:
            m = re.search(rf"\b{key}\s*=\s*([0-9.]+)", source)
            if m:
                values[key] = float(m.group(1))
    except Exception as e:
        print(f"error reading decorations.lua: {e}", flush=True)
    return values


def set_window_opacity(transparent):
    """Opaque windows during gameMode. The window_rules with 'opacity 1.0
    override' aren't touched (they were already opaque); this only moves the global default.

    Goes through 'hyprctl eval' and not 'hyprctl keyword': with a Lua config the
    parser isn't legacy and keyword fails with "can't work with non-legacy
    parsers". hl.config merges, so passing only these two keys doesn't
    override rounding/blur/gaps or whatever gameMode itself changed."""
    values = configured_opacity() if transparent else {"active_opacity": 1.0, "inactive_opacity": 1.0}
    lua = "hl.config({{ decoration = {{ active_opacity = {active_opacity}, inactive_opacity = {inactive_opacity} }} }})".format(**values)
    r = subprocess.run(["hyprctl", "eval", lua], capture_output=True, text=True)
    if r.stdout.strip() != "ok":
        print(f"error applying opacity: {r.stdout.strip()}{r.stderr.strip()}", flush=True)


def main():
    was_enabled = False
    while True:
        try:
            enabled = gamemode_enabled()
            if enabled and not was_enabled:
                run_ctl("ghosts-suspend")
                # if the watcher started with gameMode already on, the live value
                # is ours (false): don't overwrite the saved one
                if not os.path.exists(PREV_TRANSPARENCY_FILE):
                    save_prev_transparency()
                set_shell_transparency(False)
                set_window_opacity(False)
                print("gamemode ON: ghosts suspended, caelestia blur off, opaque windows", flush=True)
            elif not enabled and was_enabled:
                run_ctl("ghosts-restore")
                set_shell_transparency(pop_prev_transparency())
                set_window_opacity(True)
                print("gamemode OFF: ghosts, blur and window transparency restored", flush=True)
            was_enabled = enabled
        except Exception as e:
            print(f"error: {e}", flush=True)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
