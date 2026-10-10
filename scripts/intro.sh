#!/usr/bin/env bash
# Splash screen: the logo lights up in neon and the theme waves drop.
# Usage: intro            -> plays it now (fixed 5.1s)
#        intro --boot     -> what autostart.lua uses: only once per Hyprland
#                            session (a reload doesn't trigger it again) and
#                            the logo stays off (grey) until
#                            Serpantinum finished loading; only then it
#                            lights up and the waves drop
#        intro go         -> removes the `outro per` cover: the usual
#                            intro (the logo lights up, the waves drop)
cfg="$HOME/.config/quickshell/astrax-intro/shell.qml"
boot=0
if [ "$1" = "go" ]; then
    # cancel the `outro per` safety net
    rm -f "${XDG_RUNTIME_DIR:-/tmp}/astrax-outro-per"
    # bring back the normal polkit agent (see outro.sh per)
    qs -c astrax-power-wave ipc call agent off >/dev/null 2>&1
    systemctl --user start hyprpolkitagent 2>/dev/null
    shift
fi
if [ "$1" = "--boot" ]; then
    flag="${XDG_RUNTIME_DIR:-/tmp}/astrax-intro-${HYPRLAND_INSTANCE_SIGNATURE:-x}"
    [ -e "$flag" ] && exit 0
    touch "$flag"; shift
    # only Serpantinum signals when it finished loading; in the Caelestia session
    # waiting for its layers left the screen covered ~30s -> normal intro
    [ "$HYPR_SHELL" = "serpantinum" ] && boot=1
fi
qs list --all 2>/dev/null | grep -q "astrax-intro/shell.qml" && exit 0
ASTRAX_INTRO_WAIT=$boot qs -p "$cfg" -d > /tmp/astrax-intro.log 2>&1
# if we come from lock/suspend, the outro is still covering: remove it once
# the intro is on screen (it covers with its own background)
sleep 0.6
qs list --all 2>/dev/null | grep -q "astrax-power-wave/shell.qml" && qs -c astrax-power-wave ipc call wave clear >/dev/null 2>&1
[ "$boot" = 1 ] || exit 0

# --- boot: wait for Serpantinum ---
# "loaded" = its background (wallpaper-bg layer) and its bar ("quickshell"
# layer on top/overlay level) are there and 1s passes without any new
# layer appearing (widgets). Cap 25s; the intro drops by itself at 30s anyway.
layers() {
    hyprctl layers -j 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
out = []
for mon, v in d.items():
    for lvl, ls in v["levels"].items():
        for l in ls:
            if l["namespace"] not in ("astrax-intro", "astrax-power-wave"):
                out.append(mon + ":" + lvl + ":" + l["namespace"])
print("\n".join(sorted(out)))'
}
prev=""; stable=0
for _ in $(seq 1 125); do
    cur="$(layers)"
    if grep -q ":wallpaper-bg$" <<<"$cur" && grep -qE ":[23]:quickshell$" <<<"$cur"; then
        if [ "$cur" = "$prev" ]; then stable=$((stable + 1)); else stable=0; fi
        [ "$stable" -ge 5 ] && break
    fi
    prev="$cur"
    sleep 0.2
done
# a breather so the (video) background paints its first frame
sleep 0.4
qs -p "$cfg" ipc call intro go >/dev/null 2>&1
exit 0
