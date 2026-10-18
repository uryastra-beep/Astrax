#!/usr/bin/env bash
# Level 2: astrax-lyrics-rating (isolated HOME) and the Liner MPRIS mirror
# (private session bus + a fake Chromium in another process).
# Nothing outside a temp dir is touched. Run: bash tests/test-liner.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"; kill $(jobs -p) 2>/dev/null' EXIT
fail=0
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
check() { local what="$1"; shift; if "$@"; then pass "$what"; else bad "$what"; fi; }

echo "== astrax-lyrics-rating"
export HOME="$T/home" XDG_CACHE_HOME="$T/home/.cache"
mkdir -p "$HOME" "$XDG_CACHE_HOME/serpantinum/lyrics"
R="python3 $REPO/scripts/astrax-lyrics-rating"
# a lyrics cache entry, stored the way Serpantinum does: md5 of "Artist - Title"
cache() {
    python3 - "$1" "$2" <<'PY'
import hashlib, json, os, sys
key, tag = sys.argv[1], sys.argv[2]
d = os.path.join(os.environ["XDG_CACHE_HOME"], "serpantinum", "lyrics")
json.dump([{"time": 1, "text": tag, "words": [{"time": 1, "text": tag}]}],
          open(os.path.join(d, hashlib.md5(key.encode()).hexdigest() + ".json"), "w"))
PY
}
lk() { $R lookup "$@" 2>/dev/null; }

cache "Sara Unh0ly - Song" spotify
cache "Sara Unh0ly - Song2" liner
$R rate spotify 3 "Sara Unh0ly" "Song" 200 spotify "Sara Unh0ly - Song" >/dev/null
check "3 stars is not used yet" [ -z "$(lk "Sara Unh0ly" "Song" 200)" ]
$R rate spotify 5 "Sara Unh0ly" "Song" 200 spotify "Sara Unh0ly - Song" >/dev/null
check ">= 4 stars is used" grep -q '"origin": "spotify"' <<< "$(lk "Sara Unh0ly" "Song" 200)"
check "same song, artist spelled differently" [ -n "$(lk "unh0ly" "Song" 200)" ]
check "same song, duration within 3 s" [ -n "$(lk "Sara Unh0ly" "Song" 202)" ]
check "different duration is another song" [ -z "$(lk "Sara Unh0ly" "Song" 215)" ]
$R rate liner 3 "Sara Unh0ly" "Song" 200 "best:spotify" "x" >/dev/null
check "a 3-star from another player does not lower the best" grep -q '"stars": 5' <<< "$(lk "Sara Unh0ly" "Song" 200)"
cache "Sara Unh0ly - Song" liner
$R rate liner 4 "Sara Unh0ly" "Song" 200 liner "Sara Unh0ly - Song" >/dev/null
check "fewer stars does not replace the best" grep -q '"origin": "spotify"' <<< "$(lk "Sara Unh0ly" "Song" 200)"
$R rate liner 5 "Sara Unh0ly" "Song" 200 liner "Sara Unh0ly - Song" >/dev/null
check "equal stars do not replace the best" grep -q '"origin": "spotify"' <<< "$(lk "Sara Unh0ly" "Song" 200)"
cache "Other - Song" spotify
$R rate spotify 3 "Other" "Song" 200 spotify "Other - Song" >/dev/null
$R rate liner 4 "Other" "Song" 200 liner "Other - Song" >/dev/null
check "more stars replace the best" grep -q '"origin": "liner"' <<< "$(lk "Other" "Song" 200)"
check "rejects 0 stars" bash -c "! $R rate liner 0 A B 1 liner 'A - B' >/dev/null 2>&1"

echo "== liner-bridge / mirror (private session bus)"
if ! python3 -c "import dbus, gi" 2>/dev/null || ! command -v dbus-run-session >/dev/null; then
    echo "  skip python-dbus / python-gobject / dbus-run-session missing"
else
    export REPO T
    cat > "$T/run.sh" <<'RUN'
set -u
mkdir -p "$T/.mount_LinerTest"
# the fake must look like Liner's process (mirror.py finds Chromium by its binary path)
cp "$(readlink -f "$(command -v python3)")" "$T/.mount_LinerTest/liner"
PYTHONHOME=/usr "$T/.mount_LinerTest/liner" "$REPO/tests/fake_chromium.py" "$T/calls" &
for _ in $(seq 50); do [ -f "$T/calls.ready" ] && break; sleep 0.1; done
# the mirror runs in its own process too: a client calling a service in its own process blocks
python3 - <<'PY' &
import os, sys, time
sys.path.insert(0, os.path.join(os.environ["REPO"], "scripts", "liner"))
from gi.repository import GLib
import mirror
m = mirror.Mirror(log=lambda *a: None)
GLib.timeout_add(1500, lambda: m.update_state({"key": "A - T", "title": "T", "artist": "A", "album": "Al", "art": "", "dur": 120,
                               "pos": 5, "paused": False, "stamp": time.time()}) and False)
open(os.environ["T"] + "/mirror.ready", "w").write("1")
GLib.MainLoop().run()
PY
for _ in $(seq 50); do [ -f "$T/mirror.ready" ] && break; sleep 0.1; done
sleep 0.5
python3 - <<'PY'
import time, dbus
bus = dbus.SessionBus()
o = bus.get_object("org.mpris.MediaPlayer2.astrax_liner", "/org/mpris/MediaPlayer2", introspect=False)
p = dbus.Interface(o, "org.freedesktop.DBus.Properties")
allp = p.GetAll("org.mpris.MediaPlayer2.Player")
print("stopped-caps", all(bool(allp[k]) for k in ("CanGoNext", "CanGoPrevious", "CanPlay", "CanPause", "CanSeek", "CanControl")), allp["PlaybackStatus"])
time.sleep(2)
md = p.Get("org.mpris.MediaPlayer2.Player", "Metadata")
print("title", md["xesam:title"])
print("status", p.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus"))
print("identity", p.Get("org.mpris.MediaPlayer2", "Identity"))
pl = dbus.Interface(o, "org.mpris.MediaPlayer2.Player")
pl.PlayPause(); pl.Next(); pl.Seek(dbus.Int64(2000000))
time.sleep(0.5)
PY
kill $(jobs -p) 2>/dev/null
RUN
    timeout 60 dbus-run-session -- bash "$T/run.sh" > "$T/mirror.out" 2>&1
    check "buttons enabled while still Stopped" grep -q '^stopped-caps True Stopped' "$T/mirror.out"
    check "mirror publishes the title" grep -q '^title T' "$T/mirror.out"
    check "mirror says Playing" grep -q '^status Playing' "$T/mirror.out"
    check "identity is Liner" grep -q '^identity Liner' "$T/mirror.out"
    check "PlayPause reaches Chromium" grep -q '^PlayPause' "$T/calls"
    check "Next reaches Chromium" grep -q '^Next' "$T/calls"
    check "Seek reaches Chromium" grep -q '^Seek 2000000' "$T/calls"
fi

echo
[ "$fail" = 0 ] && echo "All good." || { echo "Some checks failed."; exit 1; }
