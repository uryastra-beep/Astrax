#!/usr/bin/env bash
# Level 3 checks, run AFTER ./install.sh on a clean machine (the CI does it in
# a fresh Arch container). Usage: bash tests/assert-install.sh
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
fail=0
pass() { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*"; fail=1; }
check() { local what="$1"; shift; if "$@"; then pass "$what"; else bad "$what"; fi; }

PINNED="$(sed -n 's/^SERPANTINUM_PINNED_COMMIT="\(.*\)"/\1/p' install.sh)"

echo "== packages"
for cmd in hyprland quickshell qs kitty fish yay caelestia sptlrx lavat brave; do
    check "$cmd is installed" command -v "$cmd" >/dev/null
done

echo "== Serpantinum"
check "serpantinum command" command -v serpantinum >/dev/null
check "installed from the pinned commit" [ "$(git -C "$HOME/.cache/serpantinum-installer" rev-parse HEAD 2>/dev/null)" = "$PINNED" ]
check "its version file exists" [ -f "$HOME/.local/state/serpantinum/version" ]
check "telemetry is off" grep -q '^ENABLE_TELEMETRY="false"' "$HOME/.local/state/serpantinum/version"

echo "== dotfiles copied (Astrax's copy wins over Serpantinum's)"
missing=0; differ=0
while IFS= read -r -d '' f; do
    [ -e "$HOME/$f" ] || { missing=$((missing + 1)); bad "missing ~/$f"; continue; }
    if grep -qI "@HOME@" "$f"; then
        # placeholder files: compare after filling in $HOME like the installer does
        cmp -s <(sed "s|@HOME@|$HOME|g" "$f") "$HOME/$f" || { differ=$((differ + 1)); bad "~/$f differs from the repo"; }
    elif [ "$f" = .config/hypr/config/inputs.lua ]; then
        :  # the keymap step may rewrite it
    else
        cmp -s "$f" "$HOME/$f" || { differ=$((differ + 1)); bad "~/$f differs from the repo"; }
    fi
done < <(git ls-files -z .config .local scripts .zshrc .p10k.zsh)
check "no missing files" [ "$missing" = 0 ]
check "no differing files" [ "$differ" = 0 ]
check "no @HOME@ placeholder left" sh -c "! grep -rlI '@HOME@' '$HOME/.config' '$HOME/.local/share/serpantinum' 2>/dev/null | grep -q ."

echo "== commands in ~/.local/bin"
while read -r name target; do
    link="$HOME/.local/bin/$name"
    check "$name -> scripts/$target" [ "$(readlink "$link")" = "$HOME/scripts/$target" ]
    check "$name is executable" [ -x "$link" ]
done < <(grep -oE '\[[A-Za-z0-9_-]+\]=[A-Za-z0-9_.-]+' install.sh | sed -E 's/^\[([^]]+)\]=(.*)$/\1 \2/')

echo "== WORT (lava wallpaper)"
wall_dir="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wallpaperDir",""))' "$HOME/.config/serpantinum/settings.json")"
check "lava-live.mp4 in Serpantinum's wallpaperDir ($wall_dir)" cmp -s wallpapers/lava-live.mp4 "$wall_dir/lava-live.mp4"
check "lava shader is compiled" [ -s "$HOME/.config/quickshell/lava-wallpaper/lava.frag.qsb" ]
check "Wallpaper.qml has the WORT hooks" grep -q lavaBootTimer "$HOME/.local/share/serpantinum/src/quickshell/singletons/theme/Wallpaper.qml"

echo "== system files"
check "SDDM session installed" cmp -s system/hyprland-serpantinum.desktop /usr/share/wayland-sessions/hyprland-serpantinum.desktop

echo
if [ "$fail" = 0 ]; then echo "install checks: all passed"; else echo "install checks: FAILED"; fi
exit "$fail"
