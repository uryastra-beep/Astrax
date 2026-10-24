#!/usr/bin/env bash
# astrax-icons: optional Apple-style app-icon pack for Astrax (Super, Alt+Tab, the macOS Dock).
#
#   astrax-icons install     download the pack to ~/.local/share/astrax/icons/ (sha256 checked)
#   astrax-icons remove      delete it (Astrax goes back to the normal system icons)
#   astrax-icons status      installed or not
#
# The pack is official App Store artwork plus a few macOS-style equivalents. It belongs to Apple and
# each app's developer, is NOT part of the Astrax source and is not covered by its license (see
# THIRD_PARTY_NOTICES.md). It is published as a separate release asset ("packs").
# Env: ASTRAX_PACKS_URL overrides the download base (tests use a file:// URL).
set -euo pipefail

BASE="${ASTRAX_PACKS_URL:-https://github.com/uryastra-beep/Astrax/releases/download/packs}"
FILE="astrax-icons-1.tar.gz"
SHA256="ea80c6b190f5736650aebaf482a1381f3da0fa7baad51d12010422f9173121f5"
# tests may pin another checksum, but only for a local file:// download
[[ "$BASE" == file://* && -n "${ASTRAX_TEST_SHA256:-}" ]] && SHA256="$ASTRAX_TEST_SHA256"
DEST="${ASTRAX_ICONS_DIR:-$HOME/.local/share/astrax/icons}"

case "${1:-}" in
    install)
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
        echo "Downloading the icon pack ($FILE)..."
        curl -fsSL "$BASE/$FILE" -o "$tmp/$FILE"
        got="$(sha256sum "$tmp/$FILE" | cut -d' ' -f1)"
        [ "$got" = "$SHA256" ] || { echo "sha256 mismatch for $FILE -- not installing." >&2; exit 1; }
        # only plain files directly inside the archive: no paths, links or devices
        if tar -tvzf "$tmp/$FILE" | grep -qvE '^-[rwx-]{9} .* [A-Za-z0-9._-]+$'; then
            echo "Unexpected content in the archive -- not installing." >&2; exit 1
        fi
        mkdir -p "$DEST"
        tar -xzf "$tmp/$FILE" -C "$DEST" --no-same-owner --no-same-permissions
        chmod 644 "$DEST"/* 2>/dev/null || true
        echo "Installed in $DEST. Icons appear in Super / Alt+Tab / the Dock after their panels reload."
        ;;
    remove)
        rm -rf "$DEST"
        echo "Removed $DEST (the normal system icons are used again)."
        ;;
    status)
        if [ -f "$DEST/SOURCES.json" ]; then echo "installed ($(ls "$DEST" | wc -l) files in $DEST)"; else echo "not installed"; fi
        ;;
    *)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        [ -z "${1:-}" ] || exit 2
        ;;
esac
