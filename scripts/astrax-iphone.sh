#!/usr/bin/env bash
# astrax-iphone: optional iPhone bridge for the Dynamic Island (NOT part of the Astrax source).
#
#   astrax-iphone install [--phone AA:BB:CC:DD:EE:FF] [--buds AA:BB:CC:DD:EE:FF] [--adapter hci0]
#   astrax-iphone remove [--purge]     stop and delete it (--purge also deletes the saved addresses)
#   astrax-iphone status
#
# It adds iPhone notifications over Bluetooth (ANCS, via `ancs-linux`, MIT, source included in the
# pack), routes the phone's audio to a pair of Buds, and the helper scripts the island uses for
# lyrics and cover art. Everything is installed as your user (no root) under
# ~/.local/lib/iphone-notifications (mode 0700); the two user services are installed but left
# DISABLED: enable them yourself once the phone is paired:
#   systemctl --user enable --now iphone-notifications.service
#   systemctl --user enable --now iphone-buds-audio.service      (only if you gave --buds)
# Your Bluetooth addresses are stored only in ~/.config/astrax/iphone.conf (mode 0600).
# Env: ASTRAX_PACKS_URL overrides the download base (tests use a file:// URL).
set -euo pipefail

BASE="${ASTRAX_PACKS_URL:-https://github.com/uryastra-beep/Astrax/releases/download/packs}"
FILE="astrax-iphone-1.tar.gz"
SHA256="7bcd229b8887897ffb08590cafd8c83346f6d71fa3619e22a10897044f7a5a22"
# tests may pin another checksum, but only for a local file:// download
[[ "$BASE" == file://* && -n "${ASTRAX_TEST_SHA256:-}" ]] && SHA256="$ASTRAX_TEST_SHA256"
LIB="${ASTRAX_IPHONE_LIB:-$HOME/.local/lib/iphone-notifications}"
UNITS="${ASTRAX_IPHONE_UNITS:-$HOME/.config/systemd/user}"
CONF="${ASTRAX_IPHONE_CONF:-$HOME/.config/astrax/iphone.conf}"
MAC_RE='^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'

phone=""; buds=""; adapter="hci0"; purge=0
cmd="${1:-}"; [ $# -gt 0 ] && shift
while [ $# -gt 0 ]; do
    case "$1" in
        --phone) phone="${2:-}"; shift 2 ;;
        --buds) buds="${2:-}"; shift 2 ;;
        --adapter) adapter="${2:-}"; shift 2 ;;
        --purge) purge=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

units_systemctl() { systemctl --user "$@" 2>/dev/null || true; }

case "$cmd" in
    install)
        if [ -z "$phone" ]; then
            [ -t 0 ] || { echo "Give the phone's Bluetooth address with --phone (see: bluetoothctl devices)." >&2; exit 2; }
            echo "Paired devices:"; bluetoothctl devices 2>/dev/null || true
            read -r -p "iPhone Bluetooth address (AA:BB:CC:DD:EE:FF): " phone
        fi
        [[ "$phone" =~ $MAC_RE ]] || { echo "'$phone' is not a Bluetooth address." >&2; exit 2; }
        if [ -n "$buds" ] && ! [[ "$buds" =~ $MAC_RE ]]; then echo "'$buds' is not a Bluetooth address." >&2; exit 2; fi
        [[ "$adapter" =~ ^hci[0-9]+$ ]] || { echo "'$adapter' is not an adapter name (hci0, hci1...)." >&2; exit 2; }

        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
        echo "Downloading the iPhone bridge ($FILE)..."
        curl -fsSL "$BASE/$FILE" -o "$tmp/$FILE"
        got="$(sha256sum "$tmp/$FILE" | cut -d' ' -f1)"
        [ "$got" = "$SHA256" ] || { echo "sha256 mismatch for $FILE -- not installing." >&2; exit 1; }
        if tar -tzf "$tmp/$FILE" | grep -qE '(^/|\.\.)'; then echo "Unsafe paths in the archive -- not installing." >&2; exit 1; fi
        mkdir "$tmp/x" && tar -xzf "$tmp/$FILE" -C "$tmp/x" --no-same-owner

        mkdir -p "$LIB" "$UNITS" "$(dirname "$CONF")"
        chmod 700 "$LIB"
        install -m 755 "$tmp/x/bin/ancs-linux" "$LIB/ancs-linux"
        install -m 755 "$tmp/x"/lib/*.py "$LIB/"
        install -m 644 "$tmp/x/LICENSE" "$LIB/LICENSE"
        rm -rf "$LIB/source" && cp -r "$tmp/x/source" "$LIB/source" && chmod -R go-rwx "$LIB/source"
        install -m 644 "$tmp/x"/systemd/*.service "$UNITS/"
        umask 077
        {
            echo "ASTRAX_IPHONE_PHONE=$phone"
            echo "ASTRAX_IPHONE_ADAPTER=$adapter"
            [ -n "$buds" ] && echo "ASTRAX_IPHONE_BUDS=$buds"
        } > "$CONF"
        chmod 600 "$CONF"
        units_systemctl daemon-reload
        echo "Installed in $LIB. The services are NOT enabled yet. Pair the phone, then:"
        echo "  systemctl --user enable --now iphone-notifications.service"
        [ -n "$buds" ] && echo "  systemctl --user enable --now iphone-buds-audio.service"
        exit 0
        ;;
    remove)
        units_systemctl disable --now iphone-notifications.service
        units_systemctl disable --now iphone-buds-audio.service
        rm -f "$UNITS/iphone-notifications.service" "$UNITS/iphone-buds-audio.service"
        rm -rf "$LIB"
        [ "$purge" = 1 ] && rm -f "$CONF"
        units_systemctl daemon-reload
        echo "Removed the iPhone bridge.$([ "$purge" = 1 ] || echo " Your addresses are kept in $CONF (--purge deletes them).")"
        ;;
    status)
        if [ -x "$LIB/ancs-linux" ]; then
            echo "installed in $LIB"
            for u in iphone-notifications iphone-buds-audio; do
                echo "  $u: $(systemctl --user is-enabled $u.service 2>/dev/null || echo not-enabled) / $(systemctl --user is-active $u.service 2>/dev/null || echo inactive)"
            done
        else
            echo "not installed"
        fi
        ;;
    *)
        sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
        [ -z "$cmd" ] || exit 2
        ;;
esac
