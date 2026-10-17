#!/usr/bin/env bash
# Level 2: astrax-update (version + update check) against a fake state dir and a
# fake GitHub answer (a file:// URL). Nothing outside a temp dir is touched.
# Run: bash tests/test-update.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/scripts/astrax-update.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
check() { local what="$1"; shift; if "$@"; then pass "$what"; else bad "$what"; fi; }

export ASTRAX_STATE_DIR="$T/state" ASTRAX_RELEASE_URL="file://$T/release.json" HOME="$T/home"
mkdir -p "$ASTRAX_STATE_DIR" "$HOME"
run() { bash "$SCRIPT" "$@"; }
release() { echo "{\"tag_name\":\"$1\"}" > "$T/release.json"; }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$ASTRAX_STATE_DIR/update.json" "$1"; }

echo "== version"
check "unknown before install" [ "$(run version)" = unknown ]
echo 1.7.0 > "$ASTRAX_STATE_DIR/version"
check "reads the installed version" [ "$(run version)" = 1.7.0 ]

echo "== check"
release v1.8.0; run check >/dev/null
check "newer release is available" [ "$(field available)" = True ]
check "remote version without the v" [ "$(field remote)" = 1.8.0 ]
release v1.7.0; run check >/dev/null
check "same version is not an update" [ "$(field available)" = False ]
release v1.6.0; run check >/dev/null
check "older release is not an update" [ "$(field available)" = False ]
release v1.10.0; run check >/dev/null
check "1.10.0 is newer than 1.7.0 (not a string compare)" [ "$(field available)" = True ]

echo "== notification only once per version"
# a fake notify-send that counts calls
mkdir -p "$T/bin"; printf '#!/bin/sh\necho x >> "%s/notified.count"\n' "$T" > "$T/bin/notify-send"; chmod +x "$T/bin/notify-send"
release v1.9.0
PATH="$T/bin:$PATH" run check -n >/dev/null; sleep 0.5
PATH="$T/bin:$PATH" run check -n >/dev/null; sleep 0.5
check "notified exactly once" [ "$(wc -l < "$T/notified.count" 2>/dev/null || echo 0)" = 1 ]
release v1.9.1
PATH="$T/bin:$PATH" run check -n >/dev/null; sleep 0.5
check "a newer release notifies again" [ "$(wc -l < "$T/notified.count")" = 2 ]

echo "== offline"
rm "$T/release.json"
before="$(cat "$ASTRAX_STATE_DIR/update.json")"
run check >/dev/null 2>&1; rc=$?
check "fails quietly" [ "$rc" != 0 ]
check "keeps the last status" [ "$(cat "$ASTRAX_STATE_DIR/update.json")" = "$before" ]

echo
if [ "$fail" = 0 ]; then echo "update tests: all passed"; else echo "update tests: FAILED"; fi
exit "$fail"
