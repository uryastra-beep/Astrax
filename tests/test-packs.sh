#!/usr/bin/env bash
# Level 2: astrax-icons and astrax-iphone against fake packs served from a file:// URL, in a temp
# dir. Nothing outside it is touched (the services are never enabled). Run: bash tests/test-packs.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
check() { local what="$1"; shift; if "$@"; then pass "$what"; else bad "$what"; fi; }

export HOME="$T/home"; mkdir -p "$HOME"
export ASTRAX_PACKS_URL="file://$T/rel"
export ASTRAX_ICONS_DIR="$T/icons" ASTRAX_IPHONE_LIB="$T/lib" ASTRAX_IPHONE_UNITS="$T/units" ASTRAX_IPHONE_CONF="$T/conf/iphone.conf"
mkdir -p "$T/rel" "$T/pk/icons" "$T/pk/iphone/"{bin,lib,systemd,source}
sum() { sha256sum "$1" | cut -d' ' -f1; }

echo "== astrax-icons"
echo '{}' > "$T/pk/icons/SOURCES.json"; echo x > "$T/pk/icons/1.jpg"
tar -czf "$T/rel/astrax-icons-1.tar.gz" -C "$T/pk/icons" SOURCES.json 1.jpg
bash "$REPO/scripts/astrax-icons.sh" install >/dev/null 2>&1
check "refuses a pack whose checksum is not the pinned one" [ ! -e "$T/icons/1.jpg" ]
export ASTRAX_TEST_SHA256="$(sum "$T/rel/astrax-icons-1.tar.gz")"
bash "$REPO/scripts/astrax-icons.sh" install >/dev/null 2>&1
check "installs a pack with the right checksum" [ -f "$T/icons/1.jpg" ]
check "status says installed" grep -q '^installed' <(bash "$REPO/scripts/astrax-icons.sh" status)
bash "$REPO/scripts/astrax-icons.sh" remove >/dev/null
check "remove deletes it" [ ! -e "$T/icons" ]
mkdir "$T/evil" && echo x > "$T/evil/a" && tar -czf "$T/rel/astrax-icons-1.tar.gz" -C "$T/evil" --transform 's|a|sub/a|' a
export ASTRAX_TEST_SHA256="$(sum "$T/rel/astrax-icons-1.tar.gz")"
bash "$REPO/scripts/astrax-icons.sh" install >/dev/null 2>&1
check "refuses an archive with subdirectories" [ ! -e "$T/icons/sub" ]

echo "== astrax-iphone"
printf '#!/bin/sh\necho ancs\n' > "$T/pk/iphone/bin/ancs-linux"
echo 'print(1)' > "$T/pk/iphone/lib/island-lyrics.py"
echo '[Unit]' > "$T/pk/iphone/systemd/iphone-notifications.service"
echo MIT > "$T/pk/iphone/LICENSE"; echo src > "$T/pk/iphone/source/x.rs"
tar -czf "$T/rel/astrax-iphone-1.tar.gz" -C "$T/pk/iphone" .
export ASTRAX_TEST_SHA256="deadbeef"
bash "$REPO/scripts/astrax-iphone.sh" install --phone AA:BB:CC:DD:EE:FF >/dev/null 2>&1
check "refuses a wrong checksum" [ ! -e "$T/lib" ]
export ASTRAX_TEST_SHA256="$(sum "$T/rel/astrax-iphone-1.tar.gz")"
bash "$REPO/scripts/astrax-iphone.sh" install --phone not-a-mac >/dev/null 2>&1
check "rejects a bad Bluetooth address" [ ! -e "$T/lib" ]
bash "$REPO/scripts/astrax-iphone.sh" install --phone AA:BB:CC:DD:EE:FF --buds 11:22:33:44:55:66 >/dev/null 2>&1
check "installs the binary and helpers" [ -x "$T/lib/ancs-linux" ] && [ -f "$T/lib/island-lyrics.py" ]
check "library dir is private (0700)" [ "$(stat -c %a "$T/lib")" = 700 ]
check "config is private (0600)" [ "$(stat -c %a "$T/conf/iphone.conf")" = 600 ]
check "config has the addresses" grep -q 'ASTRAX_IPHONE_BUDS=11:22:33:44:55:66' "$T/conf/iphone.conf"
check "service installed" [ -f "$T/units/iphone-notifications.service" ]
check "service is not enabled" [ ! -e "$T/units/default.target.wants" ]
bash "$REPO/scripts/astrax-iphone.sh" remove >/dev/null 2>&1
check "remove deletes the bridge but keeps the addresses" [ ! -e "$T/lib" ] && [ -f "$T/conf/iphone.conf" ]
bash "$REPO/scripts/astrax-iphone.sh" remove --purge >/dev/null 2>&1
check "--purge deletes the addresses" [ ! -e "$T/conf/iphone.conf" ]

echo
[ "$fail" = 0 ] && echo "All good." || { echo "Some checks failed."; exit 1; }
