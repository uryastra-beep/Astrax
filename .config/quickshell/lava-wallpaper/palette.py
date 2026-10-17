#!/usr/bin/env python3
"""Picks up to 7 faithful colors for the lava wallpaper -> /tmp/lava-palette.json"""
import json, os, sys, time
from PIL import Image

ART = "/tmp/caelestia-track-art.jpg"
OUT = "/tmp/lava-palette.json"
N = 7

def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5

def extract(path):
    return extract_im(Image.open(path).convert("RGB"))

def extract_im(im):
    im = im.resize((140, 140))
    q = im.quantize(32, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()
    total = 140 * 140
    ranked = [(cnt / total, tuple(pal[i * 3:i * 3 + 3])) for cnt, i in sorted(q.getcolors(), reverse=True)]
    chosen = []
    for md in (34, 24, 16, 8):
        for w, c in ranked:
            if len(chosen) >= N:
                break
            if all(c != o[1] and dist(c, o[1]) >= md for o in chosen):
                chosen.append((w, c))
    while len(chosen) < N:            # fill up by repeating the most abundant ones
        chosen.append(chosen[len(chosen) % max(1, len(chosen))])
    return [{"hex": "%02x%02x%02x" % c, "w": round(w, 4)} for w, c in chosen]

import re, glob, subprocess, io, configparser

def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return ""

def music_playing():
    return "Playing" in run(["playerctl", "-a", "status"])

def focused_class():
    try:
        return (json.loads(run(["hyprctl", "activewindow", "-j"])).get("class") or "").strip()
    except Exception:
        return ""

def find_icon(cls):
    low = cls.lower()
    name = low
    for d in ("/usr/share/applications", os.path.expanduser("~/.local/share/applications")):
        for f in glob.glob(d + "/*.desktop"):
            base = os.path.basename(f)[:-8].lower()
            try:
                cp = configparser.ConfigParser(interpolation=None, strict=False)
                cp.read(f, encoding="utf-8")
                e = cp["Desktop Entry"]
            except Exception:
                continue
            if base == low or e.get("StartupWMClass", "").lower() == low:
                name = e.get("Icon", low)
                break
    if os.path.isabs(name) and os.path.exists(name):
        return name
    cands = []
    for root in ("/usr/share/icons", os.path.expanduser("~/.local/share/icons"), "/usr/share/pixmaps"):
        cands += glob.glob(f"{root}/**/{name}.png", recursive=True) + glob.glob(f"{root}/**/{name}.svg", recursive=True)
    if not cands:
        return None
    def size(p):
        for part in p.split("/"):
            if part.split("x")[0].isdigit():
                return int(part.split("x")[0])
        return 512 if p.endswith(".svg") else 0
    cands.sort(key=size, reverse=True)
    return cands[0]

def load_icon(path):
    if path.endswith(".svg"):
        out = subprocess.run(["magick", "-background", "none", "-density", "384", path, "-resize", "256x256", "png:-"],
                             capture_output=True, timeout=10).stdout
        return Image.open(io.BytesIO(out)).convert("RGBA")
    return Image.open(path).convert("RGBA")

def extract_app(cls):
    p = find_icon(cls)
    if not p:
        return None
    im = load_icon(p)
    # opaque pixels only, so the transparent background doesn't skew the colors
    px = [c[:3] for c in im.getdata() if c[3] > 128]
    if len(px) < 50:
        return None
    flat = Image.new("RGB", (len(px), 1))
    flat.putdata(px)
    return extract_im(flat.resize((140, 140)) if False else flat.resize((max(1, int(len(px) ** 0.5)),) * 2))

def cava_colors():
    """The same colors the cava uses: the active theme's spectrum, or primary/tertiary."""
    st = os.path.expanduser("~/.local/state/serpantinum")
    try:
        name = open(st + "/tvgirl_mode").read().strip()
        if name and name != "0":
            sp = json.load(open(f"{st}/themes/{name}.json")).get("spectrum")
            if sp:
                return [c.lstrip("#") for c in sp]
    except Exception:
        pass
    try:
        j = json.load(open("/tmp/widget-colors.json"))
        return [j["primary"].lstrip("#"), j["tertiary"].lstrip("#")]
    except Exception:
        return None

def vividness(data):
    """Average saturation*value of the palette (0..1)."""
    import colorsys
    v = []
    for e in data:
        r, g, b = (int(e["hex"][i:i + 2], 16) / 255 for i in (0, 2, 4))
        _, sat, val = colorsys.rgb_to_hsv(r, g, b)
        v.append(sat * val)
    return sum(v) / len(v)

_last_theme = None

def publish(data):
    # TV Girl mode only: black for 2 of the 7 bubbles
    try:
        tvgirl = open(os.path.expanduser("~/.local/state/serpantinum/tvgirl_mode")).read().strip() == "TV Girl"
    except Exception:
        tvgirl = False
    if tvgirl:
        data = [dict(e) for e in data]
        for i in (3, 6):
            data[i] = {"hex": "000000", "w": max(e["w"] for e in data)}
    tmp = OUT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, OUT)
    theme_from_palette(data, tvgirl)

def theme_from_palette(data, special_mode_active):
    """Serpantinum's theme (matugen) follows the lava colors.
    With a special song mode active, border_colors.py already sets the theme: leave it alone."""
    try:
        if special_mode_active or open(os.path.expanduser("~/.local/state/serpantinum/tvgirl_mode")).read().strip() not in ("", "0"):
            return
    except Exception:
        pass
    key = json.dumps(data, sort_keys=True)
    global _last_theme
    if key == _last_theme:
        return
    _last_theme = key
    W, H = 256, 256
    im = Image.new("RGB", (W, H))
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)
    if data == PURPLES:                       # idle: the theme takes exactly the main purple
        data = [{"hex": PURPLES[0]["hex"], "w": 1.0}]
    tot = sum(max(e["w"], 0.05) for e in data)
    x = 0
    for e in data:
        w = max(e["w"], 0.05) / tot * W
        d.rectangle((x, 0, x + w, H), fill=tuple(int(e["hex"][i:i + 2], 16) for i in (0, 2, 4)))
        x += w
    # matugen dedupes by PATH: one path per palette, otherwise it ignores the change
    import hashlib
    for old in glob.glob("/tmp/lava-theme-*.png"):
        try:
            os.remove(old)
        except OSError:
            pass
    path = "/tmp/lava-theme-%s.png" % hashlib.md5(key.encode()).hexdigest()[:10]
    im.save(path)
    subprocess.Popen(["serpantinum", "ipc", "call", "matugen", "generateImage", path],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# no music and no focused app (or no usable icon): purple palette
PURPLES = [{"hex": h, "w": w} for h, w in (("a855f7", 1.0), ("7552b3", 0.9), ("5b3a9e", 0.8), ("c084fc", 0.6),
                                            ("3b2470", 0.7), ("8b5cf6", 0.8), ("2a1a4e", 0.5))]

# terminals have no colorful icon of their own: treat them like no app at all (purple palette)
TERMINALS = {"kitty", "alacritty", "foot", "footclient", "ghostty", "com.mitchellh.ghostty", "wezterm",
             "org.wezfurlong.wezterm", "konsole", "xterm", "urxvt", "st", "org.gnome.terminal",
             "gnome-terminal-server", "xfce4-terminal", "tilix", "terminator", "cool-retro-term"}

WALL_DIR = os.path.expanduser("~/.cache/serpantinum/wallpaper")

def current_wallpapers():
    out = []
    for f in sorted(glob.glob(WALL_DIR + "/current_*")):
        if f.endswith(("_name", ".png")) or os.path.isdir(f):
            continue
        try:
            out.append(open(f).read().strip())
        except Exception:
            pass
    return tuple(out)

def watch_wallpaper(last):
    """If the wallpaper changes to something other than lava-live, turn the lava off."""
    cur = current_wallpapers()
    if last is not None and cur != last and not any("lava-live" in c for c in cur):
        subprocess.run(["serpantinum", "ipc", "call", "wallpaper", "setPlayback", "all", "play"], timeout=5)
        subprocess.Popen(["lava-wallpaper", "off"])
        time.sleep(5)
    return cur

def main():
    wall = watch_wallpaper(None)
    state = None
    ppid = os.getppid()
    while os.getppid() == ppid:
        try:
            wall = watch_wallpaper(wall)
            if music_playing() and os.path.exists(ART):
                sc = cava_colors()
                key = ("cava", tuple(sc)) if sc else ("music", os.stat(ART).st_mtime)
                if key != state:
                    state = key
                    time.sleep(0.03)
                    if sc:
                        publish([{"hex": sc[i % len(sc)], "w": 1.0} for i in range(7)])
                    else:
                        publish(extract(ART))
            else:
                cls = focused_class()
                key = ("app", cls)
                if key != state:
                    state = key
                    data = None if (not cls or cls.lower() in TERMINALS) else extract_app(cls)
                    publish(data or PURPLES)
        except Exception as e:
            print(e, file=sys.stderr, flush=True)
        time.sleep(0.25)

main()
