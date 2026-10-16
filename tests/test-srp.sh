#!/usr/bin/env bash
# Level 2: srp-update / astrax-restore against a fake $HOME and a fake
# Serpantinum repo whose "installer" overwrites files the way the real one
# does. Nothing outside a temp dir is touched. Run: bash tests/test-srp.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE="$REPO/scripts/srp-update.sh"
RESTORE="$REPO/scripts/astrax-restore.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
check() { local what="$1"; shift; if "$@"; then pass "$what"; else bad "$what"; fi; }
gitc() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# fresh fake home: Astrax's override + a hypr file, and a Serpantinum "cache"
# repo one commit behind its fake upstream
setup() {
    rm -rf "$T/home" "$T/upstream"
    H="$T/home"
    mkdir -p "$H/.local/share/serpantinum/src" "$H/.config/hypr" "$H/.config/serpantinum" "$H/scripts" "$H/.local/bin"
    echo astrax-override > "$H/.local/share/serpantinum/src/widget.qml"
    echo astrax-hypr > "$H/.config/hypr/a.lua"
    U="$T/upstream"
    gitc init -q "$U"
    mkdir -p "$U/install"
    cat > "$U/install/install.sh" <<'EOS'
#!/bin/bash
# fake Serpantinum installer: wipes and re-copies its folder, touches hypr
rm -rf "$HOME/.local/share/serpantinum"
mkdir -p "$HOME/.local/share/serpantinum/src"
echo upstream > "$HOME/.local/share/serpantinum/src/widget.qml"
echo added-by-update > "$HOME/.local/share/serpantinum/src/new.qml"
echo overwritten > "$HOME/.config/hypr/a.lua"
EOS
    gitc -C "$U" add -A && gitc -C "$U" commit -qm v1
    gitc clone -q "$U" "$H/.cache/serpantinum-installer"
    OLD="$(git -C "$H/.cache/serpantinum-installer" rev-parse HEAD)"
    echo v2 > "$U/v2" && gitc -C "$U" add -A && gitc -C "$U" commit -qm v2
}
run() { local answer="$1"; shift; echo "$answer" | HOME="$H" XDG_CACHE_HOME="$H/.cache" bash "$@" >"$T/out" 2>&1; }

echo "== srp-update: cancelling changes nothing"
setup
run n "$UPDATE"; rc=$?
check "exits 0" [ "$rc" = 0 ]
check "no backup made" [ ! -d "$H/astrax-backups" ]
check "override untouched" grep -qx astrax-override "$H/.local/share/serpantinum/src/widget.qml"
check "repo still on the old commit" [ "$(git -C "$H/.cache/serpantinum-installer" rev-parse HEAD)" = "$OLD" ]

echo "== srp-update: backs up, then updates"
run y "$UPDATE"; rc=$?
check "exits 0" [ "$rc" = 0 ]
backup="$(ls "$H"/astrax-backups/srp-update-*.tar.gz 2>/dev/null | head -1)"
check "backup created" [ -n "$backup" ]
check "latest.tar.gz points at it" [ "$(readlink -f "$H/astrax-backups/latest.tar.gz")" = "$(readlink -f "$backup")" ]
check "backup holds the override" sh -c "tar -xOzf '$backup' .local/share/serpantinum/src/widget.qml | grep -qx astrax-override"
check "backup holds the manifest" sh -c "tar -tzf '$backup' | grep -qx .local/state/astrax-srp-backup.txt"
check "Serpantinum was updated" grep -qx upstream "$H/.local/share/serpantinum/src/widget.qml"
check "repo moved to the new commit" [ "$(git -C "$H/.cache/serpantinum-installer" rev-parse HEAD)" != "$OLD" ]

echo "== astrax-restore --list"
run "" "$RESTORE" --list
check "lists the backup" grep -q "srp-update-.*\.tar\.gz" "$T/out"

echo "== astrax-restore: cancelling changes nothing"
run n "$RESTORE"
check "still the updated files" grep -qx upstream "$H/.local/share/serpantinum/src/widget.qml"

echo "== astrax-restore: puts everything back"
run y "$RESTORE"; rc=$?
check "exits 0" [ "$rc" = 0 ]
check "override restored" grep -qx astrax-override "$H/.local/share/serpantinum/src/widget.qml"
check "hypr file restored" grep -qx astrax-hypr "$H/.config/hypr/a.lua"
check "file added by the update is gone" [ ! -e "$H/.local/share/serpantinum/src/new.qml" ]
check "updated copy kept aside" sh -c "ls -d '$H'/.local/share/serpantinum.before-restore-* >/dev/null 2>&1"
check "repo back on the old commit" [ "$(git -C "$H/.cache/serpantinum-installer" rev-parse HEAD)" = "$OLD" ]

echo "== srp-update: nothing to do when already up to date"
setup
gitc -C "$H/.cache/serpantinum-installer" pull -q
run y "$UPDATE"; rc=$?
check "exits 0" [ "$rc" = 0 ]
check "says it's up to date" grep -q "already at the latest commit" "$T/out"
check "Serpantinum files not touched" grep -qx astrax-override "$H/.local/share/serpantinum/src/widget.qml"

echo "== srp-update: refuses without Serpantinum's repo"
setup
rm -rf "$H/.cache/serpantinum-installer"
run y "$UPDATE"; rc=$?
check "exits non-zero" [ "$rc" != 0 ]
check "no backup made" [ ! -d "$H/astrax-backups" ]

echo "== astrax-restore: no backup"
setup
run y "$RESTORE"; rc=$?
check "exits non-zero" [ "$rc" != 0 ]
check "files untouched" grep -qx astrax-override "$H/.local/share/serpantinum/src/widget.qml"

echo "== astrax-restore: unreadable backup"
mkdir -p "$H/astrax-backups" && echo garbage > "$H/astrax-backups/srp-update-bad.tar.gz"
run y "$RESTORE" "$H/astrax-backups/srp-update-bad.tar.gz"; rc=$?
check "exits non-zero" [ "$rc" != 0 ]
check "files untouched" grep -qx astrax-override "$H/.local/share/serpantinum/src/widget.qml"

echo
if [ "$fail" = 0 ]; then echo "srp tests: all passed"; else echo "srp tests: FAILED"; fi
exit "$fail"
