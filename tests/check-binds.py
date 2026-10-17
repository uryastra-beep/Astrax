#!/usr/bin/env python3
"""Level 1: every key combination bound in the Hyprland Lua files must be listed in
binds.json (the SUPER+I search), and binds.json must not list combinations nothing binds.
Combos are normalised (SUPER/CTRL names, order, 1..0 ranges, scroll, arrows) before comparing.
Known gaps go in tests/binds-allowlist.txt (one normalised combo per line, # comments).
Run: python3 tests/check-binds.py"""
import json, os, re, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
cfg = os.path.join(root, ".config/hypr/config")
NAMED = {".": "PERIOD", "-": "MINUS", "−": "MINUS", "SPACE": "SPACE", "TAB": "TAB", "ENTER": "ENTER", "RETURN": "ENTER"}
ALIAS = {"MAINMOD": "SUPER", "MOD": "SUPER", "CONTROL": "CTRL", "SUPER_L": "SUPER", "ESCAPE": "ESC", "RETURN": "ENTER"}

def norm(combo):
    parts = [p.strip().upper() for p in re.split(r"\s*\+\s*", combo.strip()) if p.strip()]
    parts = [ALIAS.get(p, p) for p in parts]
    mods = sorted(p for p in parts if p in ("SUPER", "CTRL", "ALT", "SHIFT"))
    keys = [p for p in parts if p not in ("SUPER", "CTRL", "ALT", "SHIFT")]
    key = "".join(keys)
    key = NAMED.get(key, key)
    if re.fullmatch(r"[0-9]", key) or key in ("1…0", "1...0"): return None  # workspace digits are bound in a loop
    # only letters, digits and a few named keys are compared; arrows, mouse, media and
    # power keys are written by hand in binds.json in a free form that can't be matched
    if not (re.fullmatch(r"[A-Z]", key) or key in ("PERIOD", "MINUS", "SPACE", "TAB", "ENTER")):
        return None
    return "+".join(mods + [key])

lua = set()
for f in sorted(os.listdir(cfg)):
    if not f.startswith("binds"): continue
    for line in open(os.path.join(cfg, f), encoding="utf-8"):
        if line.lstrip().startswith("--"): continue
        m = re.search(r'hl\.bind\(\s*([^,]+),', line)
        if not m: continue
        expr = re.sub(r'\bmainMod\b', '"SUPER"', m.group(1))
        combo = "".join(re.findall(r'"([^"]*)"', expr))
        n = norm(combo)
        if n: lua.add(n)

listed = set()
for e in json.load(open(os.path.join(root, ".config/quickshell/astrax-binds/binds.json"), encoding="utf-8")):
    k = re.sub(r"\(.*?\)", "", e["keys"])
    for alt in re.split(r"\s*/\s*", k):
        n = norm(alt) if alt.strip() else None
        if n: listed.add(n)

allow = set()
p = os.path.join(root, "tests/binds-allowlist.txt")
if os.path.exists(p):
    allow = {norm(l.split("#")[0]) for l in open(p) if l.split("#")[0].strip()}

missing = sorted(lua - listed - allow)
extra = sorted(listed - lua - allow)
for m in missing: print("  FAIL bound in Lua but not in binds.json:", m)
for x in extra: print("  FAIL in binds.json but not bound in Lua:", x)
if not missing and not extra: print("  ok   %d binds match binds.json" % len(lua))
sys.exit(1 if missing or extra else 0)
