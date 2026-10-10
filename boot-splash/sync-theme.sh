#!/usr/bin/env bash
# Paints Plymouth and SDDM with the active Serpantinum theme colors so they
# match the intro/outro (astrax-intro / astrax-power-wave):
#   Plymouth: base background + "off" (grey) logo where the intro puts it
#   SDDM (material-you): theme waves (WaveCurtain.qml) on login/logout
# Usage: bash boot-splash/sync-theme.sh          (asks for root via pkexec to install)
#        bash boot-splash/sync-theme.sh --build D  (only generates into D, no install;
#                                                   to test: sddm-greeter-qt6 --test-mode --theme D/material-you)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
colors="$HOME/.local/state/serpantinum/qs_colors.json"
sddm_src="$here/sddm/material-you"
ply_src="$here/plymouth/serpantinum"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

eval "$(python3 - "$colors" <<'EOF'
import json, sys, colorsys
try: c = json.load(open(sys.argv[1]))
except Exception: c = {}
d = {"mauve": "#e5b6f2", "peach": "#f5b7b4", "green": "#d4c0d7", "sapphire": "#5d386b", "base": "#110d12"}
g = lambda k: c.get(k) if isinstance(c.get(k), str) else d[k]
layers = [g(k) for k in ("mauve", "peach", "green", "sapphire", "base")]
def rgb(h): h = h.lstrip("#"); return [int(h[i:i+2], 16) for i in (0, 2, 4)]
def hexc(v): return "#%02x%02x%02x" % tuple(max(0, min(255, round(x))) for x in v)
# Qt.lighter(mauve, 1.08): valor HSV x1.08
h, s, v = colorsys.rgb_to_hsv(*[x / 255 for x in rgb(g("mauve"))])
on = hexc([x * 255 for x in colorsys.hsv_to_rgb(h, s, min(1, v * 1.08))])
# off logo = #3a3340 at 60% over base (how the intro paints it)
b = rgb(g("base")); off = hexc([0.6 * a + 0.4 * z for a, z in zip(rgb("#3a3340"), b)])
print(f'LAYERS="{",".join(layers)}"; BASE="{g("base")}"; ON="{on}"; OFF="{off}"')
print('BASE_RGB="%s"' % " ".join("%.4f" % (x / 255) for x in b))
EOF
)"
echo "waves: $LAYERS  base: $BASE  logo: $ON / $OFF"

# --- SDDM ---
cp -r "$sddm_src" "$work/material-you"
# padlock off: raw grey, the curtain draws it at 60% (same as the intro's
# off logo)
sed "s/fill:#000000/fill:#3a3340/" "$sddm_src/lock.svg" > "$work/material-you/lock-off.svg"
sed "s/fill:#000000/fill:$ON/" "$sddm_src/lock.svg" > "$work/material-you/lock-on.svg"
# theme colors in Main.qml/theme.conf (@mauve@, @surface0@, ...) and a
# solid base-color background
python3 - "$colors" "$work/material-you" <<'PYEOF'
import json, sys, os
try: c = json.load(open(sys.argv[1]))
except Exception: c = {}
d = {"base": "#110d12", "mauve": "#e5b6f2", "peach": "#f5b7b4", "green": "#d4c0d7", "sapphire": "#5d386b",
     "surface0": "#231e23", "surface1": "#2d282e", "surface2": "#383339", "text": "#e9e0e7",
     "subtext1": "#988e97", "red": "#ffb4ab"}
col = {k: (c.get(k) if isinstance(c.get(k), str) else v) for k, v in d.items()}
out = sys.argv[2]
for fn in ("Main.qml", "theme.conf"):
    p = os.path.join(out, fn); t = open(p).read()
    for k, v in col.items(): t = t.replace("@" + k + "@", v)
    open(p, "w").write(t)
W, H = 3840, 2160
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}"><rect width="100%" height="100%" fill="{col["base"]}"/>']
svg.append("</svg>")
open(os.path.join(out, "bg.svg"), "w").write("".join(svg))
PYEOF
rsvg-convert "$work/material-you/bg.svg" -o "$work/material-you/bg.png" && rm "$work/material-you/bg.svg"
grep -v '^waveColors=' "$work/material-you/theme.conf" > "$work/tc" && mv "$work/tc" "$work/material-you/theme.conf"
echo "waveColors=\"$LAYERS\"" >> "$work/material-you/theme.conf"

# --- Plymouth ---
cp -r "$ply_src" "$work/serpantinum"
sed "s/fill:#000000/fill:$OFF/" "$here/logo.svg" > "$work/logo-off-ply.svg"
rsvg-convert -w 512 -h 512 "$work/logo-off-ply.svg" -o "$work/serpantinum/logo-off.png"
sed -i "s/^BASE_R = .*/BASE_R = $(cut -d' ' -f1 <<<"$BASE_RGB"); BASE_G = $(cut -d' ' -f2 <<<"$BASE_RGB"); BASE_B = $(cut -d' ' -f3 <<<"$BASE_RGB");/" "$work/serpantinum/serpantinum.script"

if [ "${1:-}" = "--build" ]; then
    mkdir -p "$2"; cp -r "$work/material-you" "$work/serpantinum" "$2/"; echo "generated in $2"; exit 0
fi

# --- install (root) ---
pkexec bash -c "
set -e
rm -rf /usr/share/sddm/themes/material-you.new
cp -r '$work/material-you' /usr/share/sddm/themes/material-you.new
[ -d /usr/share/sddm/themes/material-you.orig ] || cp -r /usr/share/sddm/themes/material-you /usr/share/sddm/themes/material-you.orig
rm -rf /usr/share/sddm/themes/material-you
mv /usr/share/sddm/themes/material-you.new /usr/share/sddm/themes/material-you
chmod -R a+rX /usr/share/sddm/themes/material-you
cp '$work/serpantinum/'* /usr/share/plymouth/themes/serpantinum/
plymouth-set-default-theme -R serpantinum
"
echo "done: SDDM + Plymouth synced with the theme"
