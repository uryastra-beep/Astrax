#!/usr/bin/env bash
# Installs Glass Lyrics into Spicetify. It replaces Spicy Lyrics: both
# extensions own the same lyrics page, so only one of them can be loaded.
set -euo pipefail
cd "$(dirname "$0")"

command -v spicetify >/dev/null || {
    echo "spicetify not found. Install it first: https://spicetify.app/docs/getting-started" >&2
    exit 1
}

ext_dir="$(dirname "$(spicetify -c)")/Extensions"
mkdir -p "$ext_dir"
cp glass-lyrics.js "$ext_dir/"
spicetify config extensions spicy-lyrics.mjs- extensions spicy-lyrics.js- extensions glass-lyrics.js
spicetify apply

echo
echo "Glass Lyrics installed. If Spicy Lyrics was installed from the Spicetify"
echo "Marketplace, uninstall it there too."
