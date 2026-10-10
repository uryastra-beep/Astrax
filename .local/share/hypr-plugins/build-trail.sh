#!/usr/bin/env bash
# Builds dynamic-cursors-trail.so (see README.md).
# Run it after every Hyprland update: a plugin built against old headers
# doesn't load.
set -euo pipefail

PR_BASE=e9056fd4f2b229d9924aa853c4763d6bc314bb34   # base of PR #161
PR_HEAD=30814504521ee500ebed9c53b40137fc240809d0   # head of PR #161
DEST="$HOME/.local/share/hypr-plugins/dynamic-cursors-trail.so"

hyprland_ver=$(hyprctl version | head -1 | grep -oP 'v?\d+\.\d+\.\d+' | head -1)
echo "Hyprland detected: $hyprland_ver"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git clone -q https://github.com/VirtCode/hypr-dynamic-cursors.git "$tmp/src"
cd "$tmp/src"
git remote add fork https://github.com/world-pc/hypr-dynamic-cursors.git
git fetch -q fork

# plugin commit pinned for THIS Hyprland version
hl_commit=$(hyprctl version | grep -oP 'commit \K[0-9a-f]{40}' | head -1)
target=$(grep -F "$hl_commit" hyprpm.toml | grep -oP '"\K[0-9a-f]{40}(?=")' | tail -1)
if [ -z "$target" ]; then
    echo "ERROR: hyprpm.toml has no pin for Hyprland commit $hl_commit." >&2
    echo "       Wait for the plugin to add the pin, or adjust this script." >&2
    exit 1
fi
echo "Plugin commit for this version: $target"

git checkout -q "$target"
git diff "$PR_BASE" "$PR_HEAD" > "$tmp/trail.patch"
git apply --3way "$tmp/trail.patch"

make -j2
install -Dm755 out/dynamic-cursors.so "$DEST"
echo "OK -> $DEST"
