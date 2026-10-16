#!/usr/bin/env bash
# astrax-restore: undo `srp-update`. Puts back every folder it backed up and
# returns Serpantinum's repo to the commit it was on.
#
#   astrax-restore              restore the latest backup
#   astrax-restore <file>       restore a specific backup
#   astrax-restore --list       list the backups
set -euo pipefail

BACKUP_DIR="$HOME/astrax-backups"
SERP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-installer"

if [ "${1:-}" = "--list" ]; then
    ls -1t "$BACKUP_DIR"/srp-update-*.tar.gz 2>/dev/null || echo "No backups in $BACKUP_DIR."
    exit 0
fi

BACKUP="${1:-$BACKUP_DIR/latest.tar.gz}"
BACKUP="$(realpath "$BACKUP" 2>/dev/null || true)"
if [ -z "$BACKUP" ] || [ ! -f "$BACKUP" ]; then
    echo "No backup found. Make one by running srp-update, or see: astrax-restore --list" >&2
    exit 1
fi
tar -tzf "$BACKUP" > /dev/null || { echo "$BACKUP can't be read -- nothing changed." >&2; exit 1; }

echo "Restoring from $BACKUP"
read -r -p "This replaces your current Serpantinum and Astrax files. Continue? [y/N] " answer
[[ "$answer" =~ ^[yYsS]$ ]] || { echo "Cancelled, nothing changed."; exit 0; }

# Serpantinum's installer wipes and re-copies this folder, so files added by
# the update must go too: move it aside instead of deleting it.
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ -d "$HOME/.local/share/serpantinum" ] && tar -tzf "$BACKUP" | grep -q '^\.local/share/serpantinum/'; then
    mv "$HOME/.local/share/serpantinum" "$HOME/.local/share/serpantinum.before-restore-$STAMP"
    echo "Current Serpantinum moved to ~/.local/share/serpantinum.before-restore-$STAMP"
fi

tar -xzf "$BACKUP" -C "$HOME"

commit="$(sed -n 's/^serpantinum_commit=//p' "$HOME/.local/state/astrax-srp-backup.txt" 2>/dev/null || true)"
if [ -n "$commit" ] && [ -d "$SERP_CACHE/.git" ]; then
    git -C "$SERP_CACHE" checkout -q "$commit" 2>/dev/null \
        && echo "Serpantinum's repo is back at $commit." \
        || echo "Couldn't move Serpantinum's repo back to $commit (your files are restored anyway)."
fi

echo
echo "Done. Log out and back in to load the restored setup."
echo "Once it works, you can delete ~/.local/share/serpantinum.before-restore-$STAMP"
