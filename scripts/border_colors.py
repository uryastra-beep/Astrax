#!/usr/bin/env python3
"""Changes the color of the active Hyprland window border based on the
album art of the song playing in Spotify (via MPRIS). It doesn't touch
caelestia's scheme, the wallpaper, or anything else. When nothing is
playing, it goes back to the original border (violet gradient)."""
import builtins as _b, time as _t
_p = _b.print
def print(*a, **k):
    # every log line starts with HH:MM:SS (to time how fast a song change lands)
    _p(_t.strftime("%H:%M:%S"), *a, **k)

import json
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

POLL_SECONDS = 2        # fallback; track changes are detected instantly (see main)
CONFIRM_SECONDS = 0.12  # re-read the metadata this long afterwards to discard flickers
ART_CACHE = "/tmp/caelestia-track-art.jpg"
WIDGET_COLORS_FILE = "/tmp/widget-colors.json"
CAVA_MODE_FILE = "/tmp/widget-cava-mode"
SPTLRX_MODE_FILE = "/tmp/widget-sptlrx-mode"
LRCLIB_API = "https://lrclib.net/api/get"
WIDGET_CTL = os.path.expanduser("~/scripts/widget-ctl.sh")
CAVA_CONFIG = os.path.expanduser("~/.config/cava/config")
CAVA_CONFIG_BAK = os.path.expanduser("~/.config/cava/config.bak")
WALLPAPER_PATH_FILE = os.path.expanduser("~/.local/state/caelestia/wallpaper/path.txt")
SERPANTINUM_WALLPAPER = os.path.expanduser("~/.cache/serpantinum/wallpaper/current_wallpaper.png")
# Written by WallpaperEngine.qml on every CTRL+SUPER+S toggle (and on
# startup) -- "0" = wallpaper sound on, "1"/missing = muted
# (default). Before there was no way to query this state from outside the
# QML process (the IpcHandler only had toggle(), no getter).
WALLPAPER_AUDIO_STATE_FILE = os.path.expanduser("~/.local/state/serpantinum/wallpaper_audio_muted")
# CTRL+SUPER+C / ALT+SUPER+C (see ThemeBackend.qml, which writes this same
# file): "music" | "wallpaper" | "off". Same state the native
# Serpantinum widgets (sprw) use so both color systems stay
# in sync.
WIDGET_COLOR_MODE_FILE = os.path.expanduser("~/.local/state/serpantinum/widget_color_mode")
# Special modes (TV Girl, Streetcat, La Jangada...): registry in
# MODES_FILE. Each mode is detected by artist/title/album (regex) and enables
# a Serpantinum theme + border/widget colors. The flag (mode name,
# or "0") is read by ThemeBackend.qml; the theme lives in THEMES_DIR/<mode>.json.
MODES_FILE = os.path.expanduser("~/scripts/special_modes.json")
MODE_FLAG_FILE = os.path.expanduser("~/.local/state/serpantinum/tvgirl_mode")
THEMES_DIR = os.path.expanduser("~/.local/state/serpantinum/themes")
DEFAULT_PURPLE_A = "a855f7"
DEFAULT_PURPLE_B = "7552b3"

ORIGINAL_BORDER_LUA = (
    'hl.config({ general = { col = { active_border = '
    '{ colors = { "rgba(a855f7ff)", "rgba(7552b3ff)" }, angle = 45 } } } })'
)


def active_shell():
    """serpantinum | caelestia -- same rule as ~/scripts/active-shell.sh (`vm` can
    switch shells live, so HYPR_SHELL alone can be stale)."""
    try:
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "astrax-shell")
        with open(path) as f:
            fsig, shell = f.readline().split()
        if sig and fsig == sig and shell in ("serpantinum", "caelestia"):
            return shell
    except (OSError, ValueError):
        pass
    return "serpantinum" if os.environ.get("HYPR_SHELL") == "serpantinum" else "caelestia"


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb_to_hex(rgb):
    return "".join(f"{max(0, min(255, c)):02x}" for c in rgb)


def lerp_gradient(hex_a, hex_b, steps):
    a = hex_to_rgb(hex_a)
    b = hex_to_rgb(hex_b)
    colors = []
    for i in range(steps):
        t = i / (steps - 1)
        rgb = tuple(round(a[c] + (b[c] - a[c]) * t) for c in range(3))
        colors.append(rgb_to_hex(rgb))
    return colors


def update_cava_gradient(hex_a, hex_b):
    # CAVA_CONFIG2/CAVA_CONFIG3 (widgets2/widgets3) no longer have a
    # [color] section: since they became a Quickshell surface they
    # read primary/tertiary straight from WIDGET_COLORS_FILE live.
    # Only the
    # original set (kitty + ncurses cava) still needs the gradient patched
    # into its config.
    for config_path in (CAVA_CONFIG,):
        try:
            with open(config_path) as f:
                content = f.read()
        except FileNotFoundError:
            continue
        for i, color in enumerate(lerp_gradient(hex_a, hex_b, 8), start=1):
            content = re.sub(
                rf"(gradient_color_{i}\s*=\s*)'#?[0-9a-fA-F]{{6}}'",
                rf"\1'#{color}'",
                content,
            )
        with open(config_path, "w") as f:
            f.write(content)


def revert_cava_gradient():
    for config_path, bak_path in ((CAVA_CONFIG, CAVA_CONFIG_BAK),):
        try:
            with open(bak_path) as f:
                content = f.read()
            with open(config_path, "w") as f:
                f.write(content)
        except Exception as e:
            print(f"cava revert error ({config_path}): {e}", flush=True)


def any_widget_running():
    r = subprocess.run([WIDGET_CTL, "any-running"], capture_output=True, text=True, timeout=8)
    return r.stdout.strip() == "yes"


def write_widget_colors_file(hex_a, hex_b):
    """ATOMIC write (temp file + os.replace) instead of truncating the
    file in place. Quickshell's watcher (FileView watchChanges,
    used by widgets2/widgets3 to read the color live) was confirmed to
    NOT reliably detect a truncate-in-place -- only an atomic
    replacement of the file (same mechanism as an editor's "safe save").
    Without this widgets2/3 only picked up the right color on startup and
    stayed stuck on that song forever."""
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(WIDGET_COLORS_FILE), prefix=".widget-colors-")
    try:
        with os.fdopen(tmp_fd, "w") as f:
            json.dump({"primary": hex_a, "tertiary": hex_b}, f)
        os.replace(tmp_path, WIDGET_COLORS_FILE)
    except Exception:
        try:
            os.remove(tmp_path)
        except FileNotFoundError:
            pass
        raise


def update_widgets(hex_a, hex_b):
    write_widget_colors_file(hex_a, hex_b)
    update_cava_gradient(hex_a, hex_b)
    # widgets2/widgets3 read WIDGET_COLORS_FILE live (Quickshell FileView
    # with watchChanges) -- writing it is enough, no need to restart them.
    # Only the original set (kitty + ncurses cava) needs the restart, because
    # cava's gradient is baked into a file cava only reads at
    # startup.
    if any_widget_running():
        subprocess.run([WIDGET_CTL, "restart"], capture_output=True, timeout=15)


_modes_cache = (None, [])


def load_modes():
    global _modes_cache
    try:
        mt = os.path.getmtime(MODES_FILE)
        if _modes_cache[0] != mt:
            with open(MODES_FILE) as f:
                _modes_cache = (mt, json.load(f).get("modes", []))
    except Exception as e:
        print(f"special_modes.json: {e}", flush=True)
    return _modes_cache[1]


def match_mode(artist, title, album):
    vals = {"artist": artist or "", "title": title or "", "album": album or ""}
    for m in load_modes():
        rules = m.get("match") or {}
        if rules and all(re.search(pat, vals.get(k, ""), re.I) for k, pat in rules.items()):
            return m
    return None


def _mix(a, b, t):
    ra, rb = hex_to_rgb(a), hex_to_rgb(b)
    return rgb_to_hex(tuple(round(ra[i] + (rb[i] - ra[i]) * t) for i in range(3)))


def build_palette(a, b):
    """Black theme with 2 accents (a = primary, b = secondary)."""
    h = lambda x: "#" + x
    return {
        "base": "#000000", "mantle": h(_mix("000000", a, 0.04)), "crust": "#000000",
        "surface0": h(_mix("000000", a, 0.08)), "surface1": h(_mix("000000", b, 0.16)),
        "surface2": h(_mix("000000", a, 0.26)),
        "overlay0": h(_mix(a, "000000", 0.45)), "overlay1": h(_mix(a, "000000", 0.25)),
        "overlay2": h(_mix(a, "ffffff", 0.15)),
        "text": h(_mix("ffffff", a, 0.08)), "subtext0": h(_mix("ffffff", a, 0.35)),
        "subtext1": h(_mix("ffffff", a, 0.6)),
        "mauve": h(a), "pink": h(b), "blue": h(a), "sapphire": h(_mix(a, "000000", 0.2)),
        "peach": h(_mix(b, "ffffff", 0.2)), "green": h(b), "teal": h(_mix(a, b, 0.5)),
        "yellow": h(_mix(b, "ffffff", 0.45)), "red": h(_mix(b, "ff4f6a", 0.5)),
        "maroon": h(_mix(a, "000000", 0.5)),
    }


def build_palette_multi(acc):
    """Black theme with 4 accents (modes with "accents": orange/purple/red/green).
    Orange is the main accent (mauve, the most used in the shell); the
    rest is spread over the other roles so all 4 show at once."""
    h = lambda x: "#" + x
    o, pu, r, g = acc["orange"], acc["purple"], acc["red"], acc["green"]
    return {
        "base": "#000000", "mantle": h(_mix("000000", pu, 0.06)), "crust": "#000000",
        "surface0": h(_mix("000000", pu, 0.12)), "surface1": h(_mix("000000", pu, 0.22)),
        "surface2": h(_mix("000000", pu, 0.34)),
        "overlay0": h(_mix(pu, "000000", 0.2)), "overlay1": h(_mix(pu, "ffffff", 0.2)),
        "overlay2": h(_mix(pu, "ffffff", 0.4)),
        "text": h(_mix("ffffff", o, 0.07)), "subtext0": h(_mix("ffffff", pu, 0.35)),
        "subtext1": h(_mix("ffffff", pu, 0.55)),
        "mauve": h(o), "pink": h(r), "blue": h(pu), "sapphire": h(_mix(pu, "ffffff", 0.15)),
        "peach": h(_mix(o, "ffffff", 0.2)), "green": h(g), "teal": h(_mix(g, "ffffff", 0.2)),
        "yellow": h(_mix(o, "ffffff", 0.4)), "red": h(r), "maroon": h(_mix(r, "000000", 0.5)),
    }


def extract_palette(image_path, n=4):
    """The 4 MOST ABUNDANT colors of the album art (by area), in order of
    abundance: 1 = the most common ... 4. Similar shades of the same color
    (two blues) count separately as long as they can be told apart. They're lightened just
    enough to read on a black background.
    Returns (list [(shade, hex)] by abundance, main color, order used in cavas/lyrics)."""
    import colorsys
    from PIL import Image
    im = Image.open(image_path).convert("RGB").resize((120, 120))
    q = im.quantize(28, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()
    ranked = [tuple(pal[idx * 3: idx * 3 + 3]) for cnt, idx in sorted(q.getcolors(), reverse=True)]

    def dist(c1, c2):
        return sum((c1[i] - c2[i]) ** 2 for i in range(3)) ** 0.5

    chosen = []
    # most abundant first; if one looks too much like one already picked it's skipped and
    # the next most abundant is used. The requirement is only relaxed if there aren't 4.
    for min_dist in (75, 60, 48, 36, 24, 0):
        for c in ranked:
            if len(chosen) >= n:
                break
            if c not in chosen and all(dist(c, o) >= min_dist for o in chosen):
                chosen.append(c)
    # final order: light to dark (left -> right in cavas, in order in lyrics)
    chosen.sort(key=lambda c: 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2], reverse=True)

    def lum(c):
        return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255

    out = []
    for r, g, b in chosen:
        for _ in range(8):                           # so it reads on a black background
            if (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 >= 0.36:
                break
            r, g, b = (round(x + (255 - x) * 0.12) for x in (r, g, b))
        out.append((colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[0], rgb_to_hex((r, g, b))))
    return out, out[0][1], [hx for _, hx in out]   # out already comes light to dark


def auto_mode(image_path):
    """'Cover' mode: same look as Streetcat but with the album art colors."""
    out, main, ordered = extract_palette(image_path)
    cols = [hx for _, hx in out]                       # by dominance
    return {"name": "Cover",
            "accents": {"orange": cols[0], "purple": cols[1], "red": cols[2], "green": cols[3]},
            "spectrum": ordered, "lyric_cycle": ordered}, cols[0], cols[1]


def write_json_atomic(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".mode-")
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f, indent=2)
    os.replace(tmp, path)


def write_flag(text):
    """ATOMIC: ThemeBackend.qml's FileView doesn't detect truncate-in-place."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(MODE_FLAG_FILE), prefix=".mode-")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, MODE_FLAG_FILE)


TVGIRL_SHADER = os.path.expanduser("~/.config/hypr/shaders/tvgirl.frag")
SHADER_DIR = os.path.expanduser("~/.config/hypr/shaders")


def _vec3(hexc):
    r, g, b = hex_to_rgb(hexc)
    return f"vec3({r / 255:.4f}, {g / 255:.4f}, {b / 255:.4f})"


def build_gradient_shader(name, src_hex, stops, axis="x"):
    """Multi-color screen shader: recolors ONLY the pixels that are the
    theme's main accent (src_hex and its lightened version), based on their
    X position on each monitor: stops[0] on the left ... stops[-1] on the
    right, with soft fades. Doesn't touch the wallpaper or anything of another color."""
    n = len(stops)
    # v_texcoord.y = 0 is the BOTTOM in Hyprland: inverted so stops[0] ends up on top.
    expr = "v_texcoord.x" if axis == "x" else "1.0 - v_texcoord.y"
    lines = []
    for i in range(1, n):
        center = i / n
        lines.append(f"    g = mix(g, STOP{i}, smoothstep({center - 0.10:.3f}, {center + 0.10:.3f}, x));")
    consts = "\n".join(f"const vec3 STOP{i} = {_vec3(c)};" for i, c in enumerate(stops))
    light = _mix(src_hex, "ffffff", 0.2)
    code = f"""#version 300 es
// Generated by border_colors.py for the "{name}" mode -- don't edit by hand.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;
const vec3 SRC1 = {_vec3(src_hex)};
const vec3 SRC2 = {_vec3(light)};
{consts}
void main() {{
    vec4 c = texture(tex, v_texcoord);
    float x = {expr};
    vec3 g = STOP0;
{chr(10).join(lines)}
    float m1 = 1.0 - smoothstep(0.05, 0.20, distance(c.rgb, SRC1));
    float m2 = 1.0 - smoothstep(0.05, 0.18, distance(c.rgb, SRC2));
    vec3 shift1 = (g - SRC1) * m1;
    vec3 shift2 = (mix(g, vec3(1.0), 0.2) - SRC2) * m2;
    fragColor = vec4(clamp(c.rgb + shift1 + shift2, 0.0, 1.0), c.a);
}}
"""
    path = os.path.join(SHADER_DIR, f"mode-{re.sub(r'[^a-z0-9]', '', name.lower())}.frag")
    os.makedirs(SHADER_DIR, exist_ok=True)
    with open(path, "w") as f:
        f.write(code)
    return path


def set_gradient_shader(shader_path):
    """Sets (or removes with None) the Hyprland screen shader. `touch
    ~/.local/state/serpantinum/tvgirl_gradient_off` turns it off (in case of
    stuttering) without losing the theme."""
    off_flag = os.path.expanduser("~/.local/state/serpantinum/tvgirl_gradient_off")
    path = shader_path if (shader_path and not os.path.exists(off_flag)) else ""
    subprocess.run(["hyprctl", "repl", f'hl.config({{ decoration = {{ screen_shader = "{path}" }} }})'],
                   capture_output=True, timeout=5)


_active_mode = "?"  # "?" = unknown (forces writing the flag on startup); "" = none


def activate_mode(mode, a, b):
    global _active_mode
    name = mode["name"]
    if not mode.get("fixed_theme"):
        write_json_atomic(os.path.join(THEMES_DIR, f"{name}.json"),
                          {"name": name, "isColorFocused": True, "isCustom": True,
                           "category": "user",
                           **({"cycle": mode["cycle"]} if mode.get("cycle") else {}),
                           **({"lyric_cycle": mode["lyric_cycle"]} if mode.get("lyric_cycle") else {}),
                           **({"spectrum": mode["spectrum"]} if mode.get("spectrum") else {}),
                           **({"spectrum_bands": True} if mode.get("spectrum_bands") else {}),
                           **({"spectrum_wipe": True} if mode.get("spectrum_wipe") else {}),
                           "colors": (build_palette_multi(mode["accents"]) if mode.get("accents")
                                      else build_palette(a, b))})
    write_flag(name)
    g = mode.get("gradient")
    if isinstance(g, dict):  # {"stops": [...], "axis": "x"|"y", "src": hex}
        st = g["stops"]
        set_gradient_shader(build_gradient_shader(name, g.get("src", mode["accents"]["orange"] if mode.get("accents") else st[0]),
                                                  st, g.get("axis", "x")))
    elif isinstance(g, list):
        set_gradient_shader(build_gradient_shader(name, g[0], g))
    else:
        set_gradient_shader(TVGIRL_SHADER if g else None)
    if _active_mode != name:
        print(f"special mode ON: {name}", flush=True)
    _active_mode = name


def clear_special_mode():
    global _active_mode
    if _active_mode == "":
        return
    prev = _active_mode
    _active_mode = ""
    write_flag("0")
    set_gradient_shader(None)
    print(f"special mode off (was: {prev})", flush=True)


def widget_color_mode():
    try:
        with open(WIDGET_COLOR_MODE_FILE) as f:
            m = f.read().strip()
        return m if m in ("music", "wallpaper") else "off"
    except FileNotFoundError:
        return "off"


def wallpaper_audio_active():
    """True only if the wallpaper sound mode (CTRL+SUPER+S) is
    on right now. Widgets reacting to the
    wallpaper (the purple fallback of revert_widgets(), below) should only
    "detect" it while this mode is on -- it used to trigger with
    ANY video wallpaper, whether it was muted or not."""
    try:
        with open(WALLPAPER_AUDIO_STATE_FILE) as f:
            return f.read().strip() == "0"
    except FileNotFoundError:
        return False  # WallpaperEngine.qml defaults to muted (audioMuted: true)



def revert_widgets():
    """No active player: instead of deleting WIDGET_COLORS_FILE (they ended up
    with a fixed color hardcoded in each QML), widgets 1-4 switch to
    taking the color of the current WALLPAPER (same mechanism as get_gradient_colors,
    which already uses "caelestia wallpaper -p" to get 2 colors out of any
    image -- get_wallpaper_path() already returns Serpantinum's cached
    snapshot, which exists for both static and VIDEO wallpapers, so
    this works for both alike).

    Real BUG found live: there was an exception that
    used a FIXED purple (NO_MUSIC_VIDEO_PRIMARY/TERTIARY) for video wallpapers
    with sound, instead of taking the real color from the snapshot -- when
    switching video wallpapers, EVERYTHING stayed stuck on that same
    purple regardless of the new wallpaper's real colors. Removed:
    it now always takes the real color, whatever the wallpaper type."""
    wallpaper = get_wallpaper_path()
    if wallpaper:
        try:
            color_a, color_b = get_gradient_colors(wallpaper)
            write_widget_colors_file(color_a, color_b)
            update_cava_gradient(color_a, color_b)
            if any_widget_running():
                subprocess.run([WIDGET_CTL, "restart"], capture_output=True, timeout=15)
            return
        except Exception as e:
            print(f"revert_widgets: couldn't get a color from the wallpaper ({e}), using default", flush=True)
    try:
        os.remove(WIDGET_COLORS_FILE)
    except FileNotFoundError:
        pass
    revert_cava_gradient()
    if any_widget_running():
        subprocess.run([WIDGET_CTL, "restart"], capture_output=True, timeout=15)

_last_applied_art_url = None
_candidate_art_url = None  # art_url seen on the previous tick, pending confirmation
_last_wallpaper_fp = None  # (path, mtime) of the last wallpaper applied to the widgets
_reverted_since_stop = False  # Real BUG: it started as True to "avoid reverting
# needlessly at boot", but that made sense when revert_widgets() only
# deleted a file (a harmless no-op to skip). Now revert_widgets()
# computes the wallpaper color -- skipping it at boot left widget-colors.json
# never created (lavat started with the default color instead of the real one)
# until the first playing->silence transition.
_cava_mode = None  # None = unknown yet; later "cava" or "cmatrix"


def set_cava_mode(mode):
    """mode: 'cava' (music playing) or 'cmatrix' (no player). If it changes,
    restarts widget-cava (and its ghost) so it picks up the new app; widget-ctl.sh
    reads this file on every spawn of the widget-cava class."""
    global _cava_mode
    if mode == _cava_mode:
        return
    _cava_mode = mode
    with open(CAVA_MODE_FILE, "w") as f:
        f.write(mode)
    if any_widget_running():
        subprocess.run([WIDGET_CTL, "restart"], capture_output=True, timeout=15)
    print(f"widget-cava switched to mode: {mode}", flush=True)


_sptlrx_mode = None


def has_lyrics(title, artist, album, duration):
    """Queries lrclib.net (the same API sptlrx uses under the hood) to
    know whether the current track has lyrics, without running sptlrx."""
    if not title or not artist:
        return True  # not enough data: don't touch sptlrx, assume there are lyrics
    try:
        params = urllib.parse.urlencode({
            "track_name": title,
            "artist_name": artist,
            "album_name": album or "",
            "duration": int(round(duration)) if duration else 0,
        })
        req = urllib.request.Request(f"{LRCLIB_API}?{params}",
                                      headers={"User-Agent": "astrax-widgets"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
        if data.get("instrumental"):
            return False
        return bool(data.get("plainLyrics") or data.get("syncedLyrics"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return False
        return True  # server error: don't touch sptlrx, assume there are lyrics
    except Exception:
        return True


def set_sptlrx_mode(mode):
    """mode: 'lyrics' (sptlrx) or 'pipes' (pipes-rs, when the track has no
    lyrics). widgets2 reads this file live (Quickshell FileView) and
    recomputes its layout by itself, no restart. The original set (kitty) does
    need to restart sptlrx -- widget-ctl.sh reads this file on every spawn."""
    global _sptlrx_mode
    if mode == _sptlrx_mode:
        return
    _sptlrx_mode = mode
    with open(SPTLRX_MODE_FILE, "w") as f:
        f.write(mode)
    if any_widget_running():
        subprocess.run([WIDGET_CTL, "restart"], capture_output=True, timeout=15)
    print(f"widget-sptlrx switched to mode: {mode}", flush=True)


def active_player_name():
    """Real BUG found live: "playerctl status"/"metadata" WITHOUT -p
    pick any player from the list (e.g. "spotify" even if it's
    "Stopped"), ignoring that another one (e.g. "chromium.instance..." with a
    YouTube video) is actually "Playing" -- the color ended up
    computed from the wrong player (or none). We always prefer
    the first player that is "Playing"; if none is, the first one in
    the list (so "Paused" can be detected and nothing touched)."""
    r = subprocess.run(["playerctl", "-a", "status"], capture_output=True, text=True, timeout=3)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    lines = [ln for ln in r.stdout.splitlines() if ln.strip()]
    names = subprocess.run(["playerctl", "-l"], capture_output=True, text=True, timeout=3)
    player_names = [n for n in names.stdout.splitlines() if n.strip()]
    if len(player_names) != len(lines):
        # misaligned (players changed between the two calls) -- simple retry
        return player_names[0] if player_names else None
    for name, status in zip(player_names, lines):
        if status.strip() == "Playing":
            return name
    return player_names[0] if player_names else None


def playerctl_status():
    """Replaces "caelestia shell mpris" -- that needed the Caelestia
    shell running, so under Serpantinum (or with Caelestia
    off) has_active_player() was always False and this stayed
    permanently in "no player" mode. playerctl talks mpris
    straight to the bus, it works no matter which shell is running."""
    player = active_player_name()
    if not player:
        return None
    r = subprocess.run(["playerctl", "-p", player, "status"], capture_output=True, text=True, timeout=3)
    out = r.stdout.strip()
    return out if r.returncode == 0 and out else None


def mpris_get(prop):
    key_map = {
        "trackTitle": "xesam:title",
        "trackArtist": "xesam:artist",
        "trackAlbum": "xesam:album",
        "trackArtUrl": "mpris:artUrl",
    }
    key = key_map.get(prop, prop)
    player = active_player_name()
    if not player:
        return None
    r = subprocess.run(["playerctl", "-p", player, "metadata", key], capture_output=True, text=True, timeout=3)
    out = r.stdout.strip()
    if r.returncode != 0 or not out:
        return None
    return out


def mpris_length_seconds():
    player = active_player_name()
    if not player:
        return None
    r = subprocess.run(["playerctl", "-p", player, "metadata", "mpris:length"], capture_output=True, text=True, timeout=3)
    out = r.stdout.strip()
    if r.returncode != 0 or not out:
        return None
    try:
        return float(out) / 1_000_000  # mpris:length comes in microseconds
    except ValueError:
        return None


def current_meta():
    """(artist, title, album) in ONE single playerctl call."""
    player = active_player_name()
    if not player:
        return ("", "", "")
    r = subprocess.run(["playerctl", "-p", player, "metadata", "--format",
                        "{{artist}}\x1f{{title}}\x1f{{album}}"],
                       capture_output=True, text=True, timeout=3)
    parts = r.stdout.rstrip("\n").split("\x1f") if r.returncode == 0 else []
    parts += [""] * (3 - len(parts))
    return tuple(parts[:3])


def has_active_player():
    return playerctl_status() is not None


def wallpaper_fingerprint(path):
    """path + mtime -- to detect both a wallpaper change (another
    path) and the SAME file being overwritten with a new image (same
    name, e.g. Serpantinum's current_wallpaper.png always has the same
    name)."""
    try:
        return (path, os.path.getmtime(path))
    except OSError:
        return None


def get_wallpaper_path():
    # The REAL visible wallpaper depends on the session: under Serpantinum
    # Caelestia's wallpaper (WALLPAPER_PATH_FILE) may not be the one shown
    # on screen -- Serpantinum caches its own here. Real bug
    # found live: purple wallpaper set by Serpantinum, but
    # lavat came out white because it read Caelestia's old path.txt.
    if active_shell() == "serpantinum" and os.path.isfile(SERPANTINUM_WALLPAPER):
        return SERPANTINUM_WALLPAPER
    try:
        with open(WALLPAPER_PATH_FILE) as f:
            path = f.read().strip()
        return path if path and os.path.isfile(path) else None
    except FileNotFoundError:
        return None


def get_gradient_colors(image_path):
    r = subprocess.run(["caelestia", "wallpaper", "-p", image_path],
                        capture_output=True, text=True, timeout=10)
    colours = json.loads(r.stdout)["colours"]
    return colours["primary"], colours["tertiary"]


def set_border_colors(hex_a, hex_b):
    lua = (
        f'hl.config({{ general = {{ col = {{ active_border = '
        f'{{ colors = {{ "rgb({hex_a})", "rgb({hex_b})" }}, angle = 45 }} }} }} }})'
    )
    subprocess.run(["hyprctl", "repl", lua], capture_output=True, timeout=5)


def revert_border():
    subprocess.run(["hyprctl", "repl", ORIGINAL_BORDER_LUA], capture_output=True, timeout=5)


def tick():
    global _last_applied_art_url, _candidate_art_url, _reverted_since_stop, _last_wallpaper_fp

    mode = widget_color_mode()

    if mode == "wallpaper":
        clear_special_mode()
        # ALT+SUPER+C: ALWAYS forces the real color of the current wallpaper,
        # with or without music playing. Ignores MPRIS
        # completely (unlike the "off" mode below, which only falls back
        # to the wallpaper when there's no active player).
        set_cava_mode("cava" if wallpaper_audio_active() else "cmatrix")
        wp = get_wallpaper_path()
        fp = wallpaper_fingerprint(wp) if wp else None
        if fp and fp != _last_wallpaper_fp:
            revert_widgets()
            _last_wallpaper_fp = fp
            print(f"widgets recolored (forced wallpaper mode): {wp}", flush=True)
        return

    if not has_active_player():
        clear_special_mode()
        # cava (real bars) if the wallpaper has its sound on,
        # even without an MPRIS player -- this used to ONLY check whether
        # there was an active player, so cava never kicked in with the
        # wallpaper sound alone (the widgets must
        # react to the wallpaper audio, not only Spotify/etc).
        set_cava_mode("cava" if wallpaper_audio_active() else "cmatrix")
        if not _reverted_since_stop:
            revert_border()
            _reverted_since_stop = True
            _last_applied_art_url = None
            _candidate_art_url = None
            print("border reverted to the original (no active player)", flush=True)

        if mode == "music":
            # CTRL+SUPER+C on but no music playing: does NOT fall back to
            # the wallpaper -- stays on the default purple until something
            # plays again.
            write_widget_colors_file(DEFAULT_PURPLE_A, DEFAULT_PURPLE_B)
            return

        # mode == "off": wallpaper check on every tick (POLL_SECONDS, not
        # only on the music->silence transition): if the image changed --
        # or the same file was overwritten with a new one, like
        # Serpantinum's current_wallpaper.png -- the widgets get
        # recolored by themselves, without waiting for music to start/stop.
        wp = get_wallpaper_path()
        fp = wallpaper_fingerprint(wp) if wp else None
        if fp and fp != _last_wallpaper_fp:
            revert_widgets()
            _last_wallpaper_fp = fp
            print(f"widgets recolored: wallpaper changed ({wp})", flush=True)
        return

    set_cava_mode("cava")

    if playerctl_status() != "Playing":
        return  # paused: leave the border as it is

    _reverted_since_stop = False

    art_url = mpris_get("trackArtUrl")
    artist, title, album = current_meta()
    # Key = album art + metadata: modes can depend on the song or
    # the album even if the art (art_url) doesn't change between tracks.
    key = (art_url, artist, title, album)
    if not art_url or key == _last_applied_art_url:
        _candidate_art_url = None
        return

    # Spotify/MPRIS often sends several unstable metadata updates
    # right when the song changes (the art_url "flickers" a couple of times before
    # settling) -- without this check, each flicker was processed as a
    # different song and restarted the widgets once per flicker (the
    # "widgets2 restarts 3-5 times" bug). The SAME key must be seen on
    # 2 ticks in a row before acting.
    if key != _candidate_art_url:
        # Fast confirmation: instead of waiting for the next tick (2 s), the
        # metadata is read again after CONFIRM_SECONDS; if it's the same, act now.
        time.sleep(CONFIRM_SECONDS)
        art_url2 = mpris_get("trackArtUrl")
        key2 = (art_url2,) + current_meta()
        if key2 != key:
            _candidate_art_url = key2
            return
        _candidate_art_url = key
        art_url = art_url2
        artist, title, album = key2[1:]

    try:
        # curl -4: urllib tried IPv6 first and took ~5.5s on networks without IPv6
        # connectivity; curl -4 takes ~0.3s. urllib stays as the fallback.
        data = subprocess.run(["curl", "-4", "-sfL", "--max-time", "5", art_url],
                              capture_output=True, timeout=7).stdout
        if not data:
            with urllib.request.urlopen(art_url, timeout=5) as resp:
                data = resp.read()
        with open(ART_CACHE, "wb") as f:
            f.write(data)
        mode = match_mode(artist, title, album)
        if mode:
            cols = mode.get("colors")
            color_a, color_b = (cols if cols else get_gradient_colors(ART_CACHE))
            activate_mode(mode, color_a, color_b)
        else:
            try:
                mode, color_a, color_b = auto_mode(ART_CACHE)
                activate_mode(mode, color_a, color_b)
            except Exception as e:
                print(f"Cover mode failed ({e}), classic color", flush=True)
                clear_special_mode()
                color_a, color_b = get_gradient_colors(ART_CACHE)
        set_border_colors(color_a, color_b)
        update_widgets(color_a, color_b)
        _last_applied_art_url = key
        print(f"border and widgets updated to {color_a} / {color_b}", flush=True)
        # the lyrics lookup (a network request) runs AFTER the colors are applied,
        # so it never delays them
        duration = mpris_length_seconds()
        set_sptlrx_mode("lyrics" if has_lyrics(title, artist, album, duration) else "pipes")
    except Exception as e:
        print(f"error: {e}", flush=True)


def start_follower():
    """playerctl --follow: one line per metadata/status change of
    any player -> the tick runs instantly, without waiting for the poll."""
    return subprocess.Popen(
        ["playerctl", "-a", "--follow", "metadata", "--format",
         "{{playerName}}|{{status}}|{{mpris:artUrl}}|{{xesam:title}}"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)


def main():
    import select
    follower = None
    while True:
        try:
            tick()
        except Exception as e:
            print(f"tick error: {e}", flush=True)
        if follower is None or follower.poll() is not None:
            try:
                follower = start_follower()
            except Exception:
                follower = None
        if follower is None:
            time.sleep(POLL_SECONDS)
            continue
        ready, _, _ = select.select([follower.stdout], [], [], POLL_SECONDS)
        if ready:
            follower.stdout.readline()
            time.sleep(0.05)  # gathers the burst of events from a single track change
            while select.select([follower.stdout], [], [], 0)[0]:
                if not follower.stdout.readline():
                    break


if __name__ == "__main__":
    main()
