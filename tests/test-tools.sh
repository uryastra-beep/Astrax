#!/usr/bin/env bash
# Level 2: astrax-monitors, astrax-help and astrax-doctor against temp files.
# Nothing outside a temp dir is touched. Run: bash tests/test-tools.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
check() { local what="$1"; shift; if "$@"; then pass "$what"; else bad "$what"; fi; }

echo "== astrax-monitors"
cp "$REPO/.config/hypr/config/variables.lua" "$T/vars.lua"
export ASTRAX_VARS="$T/vars.lua" ASTRAX_YES=1
bash "$REPO/scripts/astrax-monitors.sh" DP-1 HDMI-A-2 </dev/null >/dev/null
check "sets MONITOR1" grep -q '^MONITOR1 = "DP-1"' "$T/vars.lua"
check "sets MONITOR2" grep -q '^MONITOR2 = "HDMI-A-2"' "$T/vars.lua"
check "keeps a .bak copy" [ -f "$T/vars.lua.bak" ]
check "other lines untouched" [ "$(diff "$T/vars.lua" "$T/vars.lua.bak" | grep -c '^>')" = 2 ]
bash "$REPO/scripts/astrax-monitors.sh" DP-1 </dev/null >/dev/null
check "one argument keeps p2" grep -q '^MONITOR2 = "HDMI-A-2"' "$T/vars.lua"

echo "== astrax-help"
out="$(bash "$REPO/scripts/astrax-help.sh")"
check "lists astrax-doctor" grep -q astrax-doctor <<< "$out"
check "filters by word" [ "$(bash "$REPO/scripts/astrax-help.sh" cursor | grep -c 'cursor-')" = 2 ]
# every command named in the help exists as a script or a CMD_TARGETS entry
missing=0
while read -r c; do
    grep -q "\[$c\]=" "$REPO/install.sh" || { bad "help lists $c but install.sh doesn't link it"; missing=1; }
done < <(awk -F'::' 'NF==3 && $2 !~ /,/ {print $2}' "$REPO/scripts/astrax-help.sh")
check "every listed command is installed" [ "$missing" = 0 ]

echo "== astrax-doctor"
HOME="$T/home" ASTRAX_REPO="$T/none" bash "$REPO/scripts/astrax-doctor.sh" >"$T/doc.txt" 2>&1; rc=$?
check "fails when Serpantinum is missing" [ "$rc" = 1 ]
check "says how to fix" grep -q 'fix:' "$T/doc.txt"

echo "== astrax-safe (fake HOME with stub scripts)"
H="$T/safehome"; mkdir -p "$H/scripts" "$H/.local/state" "$H/.cache/hypr-trail"
cat > "$H/scripts/cursor-style.sh" <<'STUB'
#!/usr/bin/env bash
S="$HOME/.config/cursor-style"; mkdir -p "$(dirname "$S")"
if [ "${1:-get}" = get ]; then cat "$S" 2>/dev/null || echo astrax; else echo "$1" > "$S"; fi
STUB
cat > "$H/scripts/opti-ctl.sh" <<'STUB'
#!/usr/bin/env bash
echo "$1" > "$HOME/.local/state/opti"
STUB
chmod +x "$H"/scripts/*.sh
echo highcontrast | HOME="$H" bash -c 'mkdir -p ~/.config; cat > ~/.config/cursor-style'
safe() { HOME="$H" ASTRAX_STATE_DIR="$H/.local/state/astrax" bash "$REPO/scripts/astrax-safe.sh" "$@"; }
safe on </dev/null >/dev/null 2>&1; check "refuses without -y when not a terminal" [ ! -f "$H/.local/state/astrax/safe" ]
safe on -y >/dev/null
check "flag written" [ -f "$H/.local/state/astrax/safe" ]
check "patched plugin disabled" [ -e "$H/.cache/hypr-trail/disabled" ]
check "cursor style normal" [ "$(cat "$H/.config/cursor-style")" = normal ]
check "opti on" [ "$(cat "$H/.local/state/opti")" = on ]
check "status says ON" grep -q ON <<< "$(safe status)"
safe off -y >/dev/null
check "flag removed" [ ! -f "$H/.local/state/astrax/safe" ]
check "plugin guard removed again" [ ! -e "$H/.cache/hypr-trail/disabled" ]
check "cursor style restored" [ "$(cat "$H/.config/cursor-style")" = highcontrast ]
check "opti restored" [ "$(cat "$H/.local/state/opti")" = off ]
touch "$H/.cache/hypr-trail/disabled"; safe on -y >/dev/null; safe off -y >/dev/null
check "a pre-existing disabled marker is kept" [ -e "$H/.cache/hypr-trail/disabled" ]

echo "== astrax-hypr-guard"
G="$T/guard"; export ASTRAX_STATE_DIR="$G"
g() { ASTRAX_HYPR_VERSION="$1" bash "$REPO/scripts/astrax-hypr-guard.sh" "${@:2}"; }
g 0.50.0 check >/dev/null; check "first run records the version" [ "$(cat "$G/hypr-seen")" = 0.50.0 ]
check "same version is ok" [ "$(g 0.50.0 status)" = ok ]
check "new version reads as changed" [ "$(g 0.51.0 status)" = changed ]
g 0.51.0 check >/dev/null; check "check records the new version" [ "$(cat "$G/hypr-seen")" = 0.51.0 ]
check "check changes nothing else" [ "$(ls "$G")" = hypr-seen ]

echo "== astrax-tour"
A="$T/tour"; mkdir -p "$T/bin"; printf '#!/bin/sh\necho "$@" >> "%s/notes"\n' "$T" > "$T/bin/notify-send"; chmod +x "$T/bin/notify-send"
PATH="$T/bin:$PATH" ASTRAX_STATE_DIR="$A" bash "$REPO/scripts/astrax-tour.sh"
check "tour shows and records itself" [ -f "$A/tour-done" ] && [ "$(wc -l < "$T/notes")" -ge 5 ]
n=$(wc -l < "$T/notes"); PATH="$T/bin:$PATH" ASTRAX_STATE_DIR="$A" bash "$REPO/scripts/astrax-tour.sh"
check "second run is silent" [ "$(wc -l < "$T/notes")" = "$n" ]

echo "== astrax-update changelog"
printf '# Changelog\n\n## 1.9.0\n\n- c\n\n## 1.8.0\n\n- b\n\n## 1.7.0\n\n- a\n' > "$T/CHANGELOG.md"
mkdir -p "$T/uh/.local/state/astrax"; echo 1.8.0 > "$T/uh/.local/state/astrax/version"
out="$(HOME="$T/uh" ASTRAX_STATE_DIR="$T/uh/.local/state/astrax" ASTRAX_CHANGELOG_URL="file://$T/CHANGELOG.md" bash "$REPO/scripts/astrax-update.sh" changelog)"
check "only newer sections" grep -q '1.9.0' <<< "$out"
check "older ones are left out" [ -z "$(grep -E '1\.8\.0|1\.7\.0' <<< "$out")" ]

exit "$fail"
