#!/usr/bin/env bash
# astrax-doctor: checks that an Astrax install is healthy and says how to fix what isn't.
#
#   astrax-doctor        run every check (exit 1 if anything FAILS, warnings don't count)
#   astrax-doctor -q     quiet: print only warnings and failures
#
# Read-only: it never changes anything. Overrides for tests: ASTRAX_REPO.
set -u

QUIET=0; [ "${1:-}" = "-q" ] && QUIET=1
SERP="$HOME/.local/share/serpantinum"
STATE="$HOME/.local/state/astrax"
fails=0; warns=0

ok()   { [ "$QUIET" = 1 ] || printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { warns=$((warns + 1)); printf '  \033[33mwarn\033[0m  %s\n        fix: %s\n' "$1" "${2:--}"; }
bad()  { fails=$((fails + 1)); printf '  \033[31mFAIL\033[0m  %s\n        fix: %s\n' "$1" "${2:--}"; }
sec()  { [ "$QUIET" = 1 ] || printf '\n%s\n' "$*"; }

REPO="${ASTRAX_REPO:-$HOME/Astrax}"

sec "Versions"
av="$(tr -d '[:space:]' < "$STATE/version" 2>/dev/null)"
[ -n "$av" ] && ok "Astrax $av" || warn "Astrax version not recorded" "run ./install.sh from the Astrax repo"

sv="$(sed -n 's/^SERPANTINUM_VERSION="\(.*\)"/\1/p' "$HOME/.local/state/serpantinum/version" 2>/dev/null)"
if [ -z "$sv" ]; then
    bad "Serpantinum is not installed" "run ./install.sh"
else
    want=""
    [ -f "$REPO/install.sh" ] && want="$(sed -n 's/^SERPANTINUM_VERSION="\(.*\)"/\1/p' "$REPO/install.sh" | head -n1)"
    [ -z "$want" ] && want="$(sed -n 's/^\*\*Current Serpantinum version: \(.*\)\*\*.*/\1/p' "$REPO/README.md" 2>/dev/null | head -n1)"
    if [ -n "$want" ] && [ "$sv" != "$want" ]; then
        bad "Serpantinum is $sv but this Astrax is tested on $want" "astrax-restore (or ./install.sh) -- never update Serpantinum directly, use srp-update"
    else
        ok "Serpantinum $sv${want:+ (matches what Astrax is tested on)}"
    fi
fi

sec "Overrides (Astrax files Serpantinum must not overwrite)"
if [ -d "$REPO/.config/quickshell" ] || [ -d "$REPO/.local/share/serpantinum" ]; then
    drift=0; names=""
    while IFS= read -r f; do
        rel="${f#"$REPO"/}"
        [ -e "$HOME/$rel" ] || continue
        grep -qI "@HOME@" "$f" && continue
        cmp -s "$f" "$HOME/$rel" || { drift=$((drift + 1)); [ "$drift" -le 5 ] && names="$names ~/$rel"; }
    done < <(find "$REPO/.local/share/serpantinum" -type f 2>/dev/null)
    if [ "$drift" = 0 ]; then ok "every Serpantinum override is intact"
    else warn "$drift override(s) differ from the repo, e.g.:$names" "re-run ./install.sh (it backs up first); expected if you edited them on purpose"; fi
else
    warn "Astrax repo not found at $REPO, skipping the override check" "set ASTRAX_REPO=/path/to/Astrax"
fi

sec "Hyprland and monitors"
if command -v hyprctl >/dev/null && hyprctl monitors >/dev/null 2>&1; then
    outs="$(hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys; print(" ".join(m["name"] for m in json.load(sys.stdin)))' 2>/dev/null)"
    ok "outputs: ${outs:-none}"
    vars="$HOME/.config/hypr/config/variables.lua"
    for v in MONITOR1 MONITOR2; do
        n="$(sed -n "s/^$v = \"\(.*\)\"/\1/p" "$vars" 2>/dev/null)"
        [ -z "$n" ] && continue
        case " $outs " in
            *" $n "*) ok "$v = $n is connected" ;;
            *) warn "$v = $n is not a connected output" "run: astrax-monitors" ;;
        esac
    done
else
    warn "Hyprland is not running (skipping monitor checks)" "log in to the Hyprland (Serpantinum) session"
fi

sec "Reactive cursor plugin"
if command -v cursor-plugin >/dev/null; then
    out="$(cursor-plugin check 2>&1)"; rc=$?
    [ "$rc" = 0 ] && ok "$out" || warn "$out" "cursor-plugin build, then log out and back in"
else
    warn "cursor-plugin is not installed" "re-run ./install.sh"
fi

sec "Safe mode and Hyprland updates"
if [ -f "$STATE/safe" ]; then warn "safe mode is ON (patched cursor off, opti on)" "astrax-safe off"; else ok "safe mode is off"; fi
g="$(astrax-hypr-guard status 2>/dev/null || bash "$HOME/scripts/astrax-hypr-guard.sh" status 2>/dev/null)"
case "$g" in
    changed) warn "Hyprland was updated since the last check" "cursor-plugin check; cursor-plugin build if it says so" ;;
    ok) ok "Hyprland unchanged since the last check" ;;
esac

sec "Commands"
for c in srp-update astrax-update astrax-restore cursor-style astrax-help astrax-safe astrax-monitors astrax-tour; do
    command -v "$c" >/dev/null && ok "$c" || warn "$c is not in PATH" "re-run ./install.sh and make sure ~/.local/bin is in PATH"
done

sec "Glass Lyrics (Spicetify)"
if command -v spicetify >/dev/null; then
    ext="$(spicetify config extensions 2>/dev/null)"
    case "$ext" in
        *glass-lyrics*) ok "extension enabled" ;;
        *) warn "Glass Lyrics is not enabled in Spicetify" "spicetify/glass-lyrics/install.sh" ;;
    esac
else
    ok "Spicetify not installed (Glass Lyrics is optional)"
fi

sec "Liner (optional)"
if ls "$HOME"/Applications/Liner-*.AppImage >/dev/null 2>&1 || [ -n "${LINER_APPIMAGE:-}" ]; then
    ok "Liner AppImage found"
    command -v liner-bridge >/dev/null && ok "liner-bridge" || warn "liner-bridge is not in PATH" "re-run ./install.sh"
    python3 -c "import dbus, gi" 2>/dev/null && ok "python-dbus and python-gobject" || warn "python-dbus / python-gobject missing (the Liner mirror needs them)" "sudo pacman -S python-dbus python-gobject"
    command -v playerctl >/dev/null && ok "playerctl" || warn "playerctl is missing" "sudo pacman -S playerctl"
else
    ok "Liner not installed (optional, see docs/liner.md)"
fi

sec "Backups"
n="$(ls "$HOME"/astrax-backup-*.tar.gz "$HOME"/astrax-backups/*.tar.gz 2>/dev/null | wc -l)"
[ "$n" -gt 0 ] && ok "$n backup(s) available (astrax-restore --list)" || warn "no backups found" "srp-update makes one before it touches anything"

printf '\n'
if [ "$fails" -gt 0 ]; then echo "$fails failure(s), $warns warning(s)."; exit 1; fi
echo "healthy: 0 failures, $warns warning(s)."
