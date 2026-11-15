#!/usr/bin/env python3
"""lg-apply: applies Settings > Liquid Glass (Old/New mode + refraction, chromatic aberration, blur, colour, lens, specular).
Builds the .qsb files from src/*.frag with the values in settings.json and reloads the Dock, the island and the clock.
Needs Qt's `qsb` tool (qsb6 on the PATH, or /usr/lib/qt6/bin/qsb); without it the current shaders are left untouched."""
import json, os, re, shutil, subprocess, sys, tempfile, time

HOME = os.path.expanduser("~")
LG = os.path.join(HOME, ".config/astrax-common/lg")
QS = os.path.join(HOME, ".config/quickshell")
SRP = os.path.join(HOME, ".local/share/serpantinum/src/quickshell/widgets/faces/clock")
SETTINGS = os.path.join(HOME, ".config/serpantinum/settings.json")
TOKEN = os.path.join(LG, ".pending")
STATE = os.path.join(LG, ".applied")

# name -> destination of the .qsb
TARGETS = {
    "dock":   os.path.join(QS, "astrax-mac-dock/glass-soft-blur.frag.qsb"),
    "island": os.path.join(QS, "astrax-island/glass-soft-blur.frag.qsb"),
    "notch3": os.path.join(QS, "astrax-island/glass-notch3.frag.qsb"),
    "glyph":  os.path.join(SRP, "glass-glyph-lg.frag.qsb"),
}
RELOAD = [os.path.join(QS, "astrax-mac-dock/shell.qml"), os.path.join(QS, "astrax-island/shell.qml"),
          os.path.join(SRP, "ClockFaceIOS.qml")]

DEF = {"mode": "new", "refraction": 100, "chromatic": 100, "blur": 30, "vivid": 122, "lens": 100, "specular": 100}

def settings():
    try:
        with open(SETTINGS, encoding="utf-8") as f:
            cfg = json.load(f).get("liquidGlass", {})
    except Exception:
        cfg = {}
    out = dict(DEF)
    for k, v in cfg.items():
        if k in out:
            out[k] = v
    return out

def find_qsb():
    for name in ("qsb6", "qsb"):
        p = shutil.which(name)
        if p:
            return p
    p = "/usr/lib/qt6/bin/qsb"
    return p if os.path.exists(p) else None

def main():
    # debounce: if another call arrives while we wait, that one does the work
    me = str(time.time_ns())
    with open(TOKEN, "w") as f:
        f.write(me)
    time.sleep(0.7)
    with open(TOKEN) as f:
        if f.read() != me:
            return
    c = settings()
    qsb = find_qsb()
    if c["mode"] != "old" and not qsb:
        print("lg-apply: the qsb tool (qt6-shadertools) was not found; install it to change Liquid Glass settings", file=sys.stderr)
        return
    key = json.dumps(c, sort_keys=True)
    try:
        if open(STATE).read() == key and "--force" not in sys.argv:
            return
    except Exception:
        pass
    for name, dst in TARGETS.items():
        if c["mode"] == "old":
            shutil.copyfile(os.path.join(LG, "old", name + ".qsb"), dst)
            continue
        src = open(os.path.join(LG, "src", name + ".frag")).read()
        vals = {"LG_REFR": c["refraction"] / 100, "LG_CHROMA": c["chromatic"] / 100, "LG_BLUR": c["blur"] / 10,
                "LG_SAT": c["vivid"] / 100, "LG_LENS": c["lens"] / 100, "LG_SPEC": c["specular"] / 100}
        for k, v in vals.items():
            src = re.sub(r"const float %s = [-0-9.]+;" % k, "const float %s = %.4f;" % (k, v), src)
        with tempfile.TemporaryDirectory() as td:
            fp = os.path.join(td, name + ".frag")
            open(fp, "w").write(src)
            out = os.path.join(td, name + ".qsb")
            r = subprocess.run([qsb, "--glsl", "300 es,330", "--hlsl", "50", "--msl", "12", "-o", out, fp],
                               capture_output=True, text=True)
            if r.returncode != 0:
                print("qsb failed:", name, r.stderr, file=sys.stderr)
                return
            shutil.copyfile(out, dst)
    open(STATE, "w").write(key)
    for p in RELOAD:   # Quickshell does not reload .qsb files by itself: touch the shell.qml / the clock face
        try:
            os.utime(p)
        except OSError:
            pass

main()
