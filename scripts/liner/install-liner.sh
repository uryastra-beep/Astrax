#!/usr/bin/env bash
# Optional: set up Liner (https://tryliner.fun) to share its lyrics with Astrax.
# Unofficial, not affiliated with Liner. Nothing of Liner is modified or
# redistributed: the official AppImage is downloaded from Liner's own GitHub
# releases (sha512 checked) and only launched through liner-bridge.
#
#   bash scripts/liner/install-liner.sh [--no-deps]
#
# Env: LINER_RELEASE_URL (base URL holding latest-linux.yml and the AppImage),
#      LINER_APPS_DIR (default ~/Applications).
set -euo pipefail

BASE="${LINER_RELEASE_URL:-https://github.com/tryliner/desktop/releases/latest/download}"
APPS="${LINER_APPS_DIR:-$HOME/Applications}"
DEPS=1
[ "${1:-}" = "--no-deps" ] && DEPS=0

if [ "$DEPS" = 1 ]; then
    sudo pacman -S --needed --noconfirm playerctl python-dbus python-gobject fuse2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$BASE/latest-linux.yml" -o "$tmp/latest.yml"

read -r ver file sum < <(python3 - "$tmp/latest.yml" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
v = re.search(r"^version:\s*(\S+)", t, re.M).group(1)
f = re.search(r"^path:\s*(\S+)", t, re.M).group(1)
s = re.search(r"^sha512:\s*(\S+)", t, re.M).group(1)
print(v, f, s)
PY
)
case "$file" in *.AppImage) ;; *) echo "Unexpected release file: $file" >&2; exit 1 ;; esac
case "$file" in */*|*..*) echo "Unexpected release file: $file" >&2; exit 1 ;; esac

mkdir -p "$APPS"
dest="$APPS/Liner-$ver.AppImage"
if [ ! -f "$dest" ]; then
    curl -fL --progress-bar "$BASE/$file" -o "$tmp/$file"
    got="$(openssl dgst -sha512 -binary "$tmp/$file" | base64 -w0)"
    [ "$got" = "$sum" ] || { echo "sha512 mismatch for $file -- not installing." >&2; exit 1; }
    install -m 755 "$tmp/$file" "$dest"
fi
echo "Liner $ver at $dest"

# icon and launcher: opening Liner from the menu goes through liner-bridge
icon_dir="$HOME/.local/share/icons/hicolor/512x512/apps"
mkdir -p "$icon_dir" "$HOME/.local/share/applications"
if [ ! -f "$icon_dir/liner.png" ]; then
    ( cd "$tmp" && "$dest" --appimage-extract liner.png >/dev/null 2>&1 || true
      [ -f squashfs-root/liner.png ] && cp squashfs-root/liner.png "$icon_dir/liner.png" ) || true
fi
cat > "$HOME/.local/share/applications/liner.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Liner
Comment=Liner with lyrics shared to Astrax (via liner-bridge)
Exec=$HOME/.local/bin/liner-bridge %U
Icon=liner
Categories=AudioVideo;Audio;Player;
Terminal=false
DESK
echo "Open Liner from the app menu (or run liner-bridge). Liner only shares"
echo "lyrics when it is opened through liner-bridge."
