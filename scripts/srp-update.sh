#!/usr/bin/env bash
# srp-update: back up everything a Serpantinum update can overwrite, then
# update Serpantinum to its latest version.
#
# Astrax replaces parts of Serpantinum (widget registry, widget faces,
# wallpaper engine, lock screen, bar modules) and was tested against one
# pinned Serpantinum commit. A Serpantinum update wipes and re-copies
# ~/.local/share/serpantinum, so those Astrax changes are lost and newer
# Serpantinum code may not work with the rest of Astrax.
#
# Undo everything with: astrax-restore
set -euo pipefail

BACKUP_DIR="$HOME/astrax-backups"
SERP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-installer"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_DIR/srp-update-$STAMP.tar.gz"

# everything Serpantinum's installer can touch, plus Astrax's own files
PATHS=(
    .local/share/serpantinum
    .local/state/serpantinum
    .config/serpantinum
    .config/hypr
    .config/quickshell
    .local/share/hypr-plugins
    scripts
    .local/bin
)

if [ ! -d "$SERP_CACHE/.git" ]; then
    echo "Serpantinum's repo isn't at $SERP_CACHE -- was it installed with Astrax's install.sh?" >&2
    exit 1
fi

echo "WARNING: updating Serpantinum can break Astrax. Astrax's changes to"
echo "Serpantinum are overwritten, and newer Serpantinum code may not work with"
echo "the rest of Astrax. A full backup is taken first; undo it all with: astrax-restore"
read -r -p "Continue? [y/N] " answer
[[ "$answer" =~ ^[yYsS]$ ]] || { echo "Cancelled, nothing changed."; exit 0; }

mkdir -p "$BACKUP_DIR"
existing=()
for p in "${PATHS[@]}"; do
    [ -e "$HOME/$p" ] && existing+=("$p")
done

old_commit="$(git -C "$SERP_CACHE" rev-parse HEAD)"
# the manifest travels inside the tarball, so restore knows which commit to go back to
manifest="$HOME/.local/state/astrax-srp-backup.txt"
mkdir -p "$(dirname "$manifest")"
{
    echo "date=$STAMP"
    echo "serpantinum_commit=$old_commit"
} > "$manifest"
existing+=(".local/state/astrax-srp-backup.txt")

echo "Backing up ${#existing[@]} folders to $BACKUP ..."
tar -czf "$BACKUP" -C "$HOME" "${existing[@]}"
tar -tzf "$BACKUP" > /dev/null || { echo "The backup can't be read back -- stopping before changing anything." >&2; exit 1; }
ln -sfn "$BACKUP" "$BACKUP_DIR/latest.tar.gz"
echo "Backup OK ($(du -h "$BACKUP" | cut -f1))."

echo "Fetching the latest Serpantinum..."
git -C "$SERP_CACHE" fetch origin
git -C "$SERP_CACHE" reset --hard origin/HEAD 2>/dev/null \
    || git -C "$SERP_CACHE" reset --hard origin/main 2>/dev/null \
    || git -C "$SERP_CACHE" reset --hard origin/master
new_commit="$(git -C "$SERP_CACHE" rev-parse HEAD)"
if [ "$new_commit" = "$old_commit" ]; then
    echo "Serpantinum is already at the latest commit ($new_commit). Nothing to update."
    exit 0
fi
echo "Updating Serpantinum: $old_commit -> $new_commit"
echo "Running Serpantinum's installer..."
bash "$SERP_CACHE/install/install.sh"

echo
echo "Serpantinum updated. Log out and back in to load it."
echo "If anything broke, put everything back with: astrax-restore"
