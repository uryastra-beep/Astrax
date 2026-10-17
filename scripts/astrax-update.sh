#!/usr/bin/env bash
# astrax-update: Astrax's own version and update check (the "About" page in
# Serpantinum's menu, SUPER+C, shows it and offers the update).
#
#   astrax-update version        print the installed Astrax version
#   astrax-update check [-n]     ask GitHub for the latest release and write the status
#                                (-n also sends a desktop notification, once per version)
#   astrax-update status         print the status (JSON)
#   astrax-update daemon         what runs at login: check after a minute, then every 6 hours
#   astrax-update run            update: fetch the latest release and run its ./install.sh
#   astrax-update changelog      what changed since the installed version (from GitHub)
#   astrax-update rollback       put the latest backup back (same as astrax-restore)
#
# State lives in ~/.local/state/astrax (version, update.json, notified).
# Overrides, for tests: ASTRAX_STATE_DIR, ASTRAX_CHANGELOG_URL (a file:// works), ASTRAX_RELEASE_URL (a file:// works), ASTRAX_REPO_URL.
set -u

STATE="${ASTRAX_STATE_DIR:-$HOME/.local/state/astrax}"
RELEASE_URL="${ASTRAX_RELEASE_URL:-https://api.github.com/repos/uryastra-beep/Astrax/releases/latest}"
CHANGELOG_URL="${ASTRAX_CHANGELOG_URL:-https://raw.githubusercontent.com/uryastra-beep/Astrax/main/CHANGELOG.md}"
REPO_URL="${ASTRAX_REPO_URL:-https://github.com/uryastra-beep/Astrax.git}"
CLONE="${XDG_CACHE_HOME:-$HOME/.cache}/astrax-installer"
GUIDE_CACHE="${QS_CACHE_DIR:-$HOME/.cache/serpantinum}/guide"
QS_MANAGER="$HOME/.local/share/serpantinum/src/scripts/qs_manager.sh"

local_version() { cat "$STATE/version" 2>/dev/null | tr -d "[:space:]"; }

# newer A B: success if A is a higher version than B
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]; }

write_status() { # local remote
    local avail=false
    [ -n "$1" ] && [ -n "$2" ] && newer "$2" "$1" && avail=true
    mkdir -p "$STATE"
    printf '{"local":"%s","remote":"%s","available":%s,"checked":%s}\n' "$1" "$2" "$avail" "$(date +%s)" \
        > "$STATE/update.json.tmp" && mv "$STATE/update.json.tmp" "$STATE/update.json"
}

fetch_remote() { # prints the latest release version, without the leading v
    local json
    json="$(curl -fsS --max-time 20 -H 'Accept: application/vnd.github+json' "$RELEASE_URL" 2>/dev/null)" || return 1
    printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("vV"))' 2>/dev/null
}

notify() { # version
    command -v notify-send >/dev/null 2>&1 || return 0
    (
        action="$(notify-send -a Astrax -i software-update-available \
            -A "default=Open About" \
            "Astrax $1 is available" \
            "You have $(local_version). Open the About page (SUPER+C) to update.")"
        if [ "$action" = default ]; then
            mkdir -p "$GUIDE_CACHE"; echo about > "$GUIDE_CACHE/last_tab.txt"
            [ -f "$QS_MANAGER" ] && bash "$QS_MANAGER" toggle guide
        fi
    ) >/dev/null 2>&1 &
}

check() {
    local l r
    l="$(local_version)"
    r="$(fetch_remote)" || { echo "couldn't reach GitHub" >&2; return 1; }
    [ -n "$r" ] || { echo "unexpected answer from GitHub" >&2; return 1; }
    write_status "$l" "$r"
    if [ "${1:-}" = "-n" ] && [ -n "$l" ] && newer "$r" "$l" && [ "$(cat "$STATE/notified" 2>/dev/null)" != "$r" ]; then
        echo "$r" > "$STATE/notified"
        notify "$r"
    fi
    echo "installed ${l:-unknown}, latest $r"
}

case "${1:-}" in
    version) v="$(local_version)"; echo "${v:-unknown}" ;;
    status)  cat "$STATE/update.json" 2>/dev/null || echo '{}' ;;
    check)   check "${2:-}" ;;
    daemon)
        sleep 60
        while true; do check -n >/dev/null 2>&1 || true; sleep 21600; done
        ;;
    changelog)
        l="$(local_version)"
        curl -fsS --max-time 20 "$CHANGELOG_URL" 2>/dev/null | python3 -c '
import re, sys
local = sys.argv[1]
key = lambda v: [int(x) if x.isdigit() else 0 for x in re.split(r"[.]", v)]
out, keep = [], False
for line in sys.stdin:
    m = re.match(r"^## (\S+)", line)
    if m:
        keep = (not local) or key(m.group(1)) > key(local)
    if keep:
        out.append(line)
print("".join(out).rstrip() or "Nothing newer than " + local + ".")' "$l" || { echo "couldn't reach GitHub" >&2; exit 1; }
        ;;
    rollback)
        command -v astrax-restore >/dev/null && exec astrax-restore "${@:2}"
        exec bash "$HOME/scripts/astrax-restore.sh" "${@:2}"
        ;;
    run)
        l="$(local_version)"
        r="$(fetch_remote)" || { echo "couldn't reach GitHub" >&2; exit 1; }
        if [ -z "$r" ] || { [ -n "$l" ] && ! newer "$r" "$l"; }; then
            echo "Astrax ${l:-?} is up to date."; exit 0
        fi
        echo "Astrax ${l:-?} -> $r"
        echo "./install.sh backs up every file it overwrites first, then re-copies the dotfiles."
        read -r -p "Update now? [y/N] " a
        [[ "$a" =~ ^[yYsS]$ ]] || { echo "Cancelled, nothing changed."; exit 0; }
        if [ -d "$CLONE/.git" ]; then
            git -C "$CLONE" fetch --tags --force -q || exit 1
        else
            rm -rf "$CLONE"; git clone -q "$REPO_URL" "$CLONE" || exit 1
        fi
        git -C "$CLONE" checkout -q -f "v$r" || { echo "tag v$r not found" >&2; exit 1; }
        ( cd "$CLONE" && ./install.sh ) && check >/dev/null 2>&1
        ;;
    *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
