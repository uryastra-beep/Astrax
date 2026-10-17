#!/usr/bin/env bash
# cursor-plugin: builds Astrax's patched hypr-dynamic-cursors (the reactive cursor).
#
#   cursor-plugin build   compile it against the installed Hyprland headers
#   cursor-plugin check   say whether it must be rebuilt (Hyprland was updated)
#   cursor-plugin hash    print the hash of the installed Hyprland headers
#
# The source is copied to ~/.local/share/hypr-plugins/astrax-cursor by
# install.sh. A plugin built against other headers must not be loaded, so
# plugins.lua only loads it when the hash saved at build time matches the
# installed headers (otherwise it falls back to the stock hyprpm plugin).
# Rebuild after every Hyprland update, then log out and back in. Never
# hot-reload the plugin (hyprctl plugin load/unload): it can crash Hyprland.
set -euo pipefail

DIR="$HOME/.local/share/hypr-plugins/astrax-cursor"
# hyprland.pc doesn't always set includedir: fall back to the usual prefix
INCLUDEDIR="$(pkg-config --variable=includedir hyprland 2>/dev/null || true)"
HEADERS="${INCLUDEDIR:-/usr/include}/hyprland"

headers_hash() {
    [ -d "$HEADERS" ] || { echo "Hyprland headers not found in $HEADERS" >&2; return 1; }
    find "$HEADERS" -type f -name '*.h*' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
}

case "${1:-}" in
    hash)
        headers_hash
        ;;
    check)
        [ -f "$DIR/out/dynamic-cursors.so" ] || { echo "not built: run 'cursor-plugin build'"; exit 1; }
        if [ "$(cat "$DIR/built.hash" 2>/dev/null)" = "$(headers_hash)" ]; then
            echo "up to date"
        else
            echo "Hyprland changed since the last build: run 'cursor-plugin build', then log out and back in"
            exit 1
        fi
        ;;
    build)
        [ -f "$DIR/Makefile" ] || { echo "source missing in $DIR (run Astrax's install.sh)" >&2; exit 1; }
        hash="$(headers_hash)"
        make -C "$DIR" -j"$(nproc)"
        printf '%s\n' "$hash" > "$DIR/built.hash"
        echo "built $DIR/out/dynamic-cursors.so -- log out and back in to load it (never hot-reload it)"
        ;;
    *)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
