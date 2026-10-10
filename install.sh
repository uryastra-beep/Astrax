#!/usr/bin/env bash
# Astrax installer.
#
#   git clone https://github.com/uryastra-beep/Astrax.git
#   cd Astrax && ./install.sh
#
# Done without asking: install packages (pacman + yay), install Serpantinum
# (its own installer, pinned to a tested commit) if it's missing, back up
# every file that is about to be overwritten, copy the dotfiles to $HOME
# (this includes the custom Serpantinum QML, copied AFTER Serpantinum's
# installer so ours win), make the scripts executable and link the commands
# into ~/.local/bin.
#
# Asked first (system-level): the SDDM session file, the Hyprland plugins,
# enabling sddm, changing the login shell, Glass Lyrics for Spotify.
#
# Not done: boot splash / GRUB / Plymouth (see boot-splash/README.md) and
# renaming monitors if yours aren't eDP-1 + HDMI-A-1.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { echo; bold "== $* =="; }
confirm() {
    local prompt="$1" reply
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

step "Platform check"
command -v pacman >/dev/null || {
    echo "Astrax is for Arch Linux and derivatives (pacman not found)." >&2
    exit 1
}
[ "$(id -u)" -ne 0 ] || {
    echo "Run this as your normal user, not root (it asks for sudo when needed)." >&2
    exit 1
}
echo "pacman found."

step "yay (AUR helper)"
if ! command -v yay >/dev/null; then
    echo "yay not found -- installing it..."
    sudo pacman -S --needed --noconfirm git base-devel
    tmp="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay.git "$tmp/yay"
    (cd "$tmp/yay" && makepkg -si --noconfirm)
    rm -rf "$tmp"
else
    echo "yay is already installed."
fi

step "Official packages (pacman)"
sudo pacman -S --needed --noconfirm \
    hyprland uwsm sddm xdg-desktop-portal-hyprland hyprpolkitagent quickshell \
    kitty fish zsh zsh-theme-powerlevel10k micro fastfetch btop \
    jq socat grim slurp imagemagick ffmpeg util-linux xorg-xhost libnotify \
    wireplumber playerctl cava cmatrix wl-clipboard cliphist fuzzel \
    python python-pillow python-numpy python-gobject python-dbus python-evdev \
    qt6-multimedia-ffmpeg nautilus

step "AUR packages (yay)"
yay -S --needed --noconfirm \
    caelestia-shell caelestia-cli sptlrx-bin lavat unimatrix-git clock-rs-git \
    toilet ttf-rubik-vf bibata-cursor-theme brave-bin

step "Serpantinum (main shell -- not an AUR package, it has its own installer)"
# Pinned commit: Serpantinum's installer always resets to the latest master.
# Astrax overrides several of its QML files (WidgetRegistry.qml,
# WallpaperEngine.qml, faces/*, ...) and those were tested against this
# commit. Bump it by hand after validating a newer one.
SERPANTINUM_PINNED_COMMIT="df443798ef6b3bd0aaf10500533fcd75ca1b0cd8"
SERPANTINUM_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-installer"

if command -v serpantinum >/dev/null 2>&1; then
    echo "Serpantinum is already installed ($(command -v serpantinum)) -- skipping its installer."
    installed_commit="$(git -C "$SERPANTINUM_CACHE_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [ "$installed_commit" != "$SERPANTINUM_PINNED_COMMIT" ]; then
        echo "WARNING: Serpantinum was installed from '$installed_commit', not the pinned commit."
        echo "         Astrax's QML overrides may not match. To align: delete"
        echo "         $SERPANTINUM_CACHE_DIR, uninstall Serpantinum and run this again."
        confirm "Continue anyway?" || exit 1
    fi
else
    echo "Preparing the Serpantinum repo at the pinned commit ($SERPANTINUM_PINNED_COMMIT)..."
    if [ ! -d "$SERPANTINUM_CACHE_DIR/.git" ]; then
        rm -rf "$SERPANTINUM_CACHE_DIR"
        git clone https://github.com/ilyamiro/serpantinum.git "$SERPANTINUM_CACHE_DIR"
    else
        git -C "$SERPANTINUM_CACHE_DIR" fetch origin
    fi
    git -C "$SERPANTINUM_CACHE_DIR" checkout "$SERPANTINUM_PINNED_COMMIT"
    echo "Running Serpantinum's official installer..."
    bash "$SERPANTINUM_CACHE_DIR/install/install.sh"
fi

step "Backing up what is about to be overwritten"
BACKUP="$HOME/astrax-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
mapfile -t existing < <(
    find .config .local scripts .zshrc .p10k.zsh -type f 2>/dev/null |
        while read -r f; do [ -f "$HOME/$f" ] && echo "$f"; done
)
if [ "${#existing[@]}" -gt 0 ]; then
    tar -czf "$BACKUP" -C "$HOME" "${existing[@]}"
    echo "${#existing[@]} files saved to $BACKUP"
else
    echo "Nothing to back up (clean install)."
fi

step "Copying the dotfiles to \$HOME"
cp -r .config "$HOME/"
cp -r .local "$HOME/"
cp -r scripts "$HOME/"
cp .zshrc .p10k.zsh "$HOME/"
chmod +x "$HOME"/scripts/*.sh "$HOME"/scripts/*.py 2>/dev/null || true
# a few JSON/QML files can't expand $HOME by themselves: fill in the placeholder
grep -rlI "@HOME@" .config .local 2>/dev/null |
    while read -r f; do sed -i "s|@HOME@|$HOME|g" "$HOME/$f"; done || true
mkdir -p "$HOME/Pictures/Wallpapers"
echo "Done -- this includes Astrax's versions of Serpantinum's widget registry,"
echo "widget faces, wallpaper engine, lock screen and bar modules."

step "Commands in ~/.local/bin"
mkdir -p "$HOME/.local/bin"
declare -A CMD_TARGETS=(
    [vm]=vm-ctl.sh
    [mode]=mode-ctl.sh
    [opti]=opti-ctl.sh
    [sharp]=sharp-transparent-ctl.sh
    [workspace]=workspace-ctl.sh
    [taskbar]=taskbar-ctl.sh
    [show]=show-ctl.sh
    [intro]=intro.sh
    [outro]=outro.sh
    [hz]=hz-ctl.sh [Hz]=hz-ctl.sh [check]=hz-ctl.sh
    [widget]=widget-ctl.sh [widgets]=widget-ctl.sh
    [widget2]=widget2-ctl.sh [widgets2]=widget2-ctl.sh
    [widget3]=widget3-ctl.sh [widgets3]=widget3-ctl.sh
    [widget4]=widget4-ctl.sh [widgets4]=widget4-ctl.sh
    [widget5]=widget5-ctl.sh [widgets5]=widget5-ctl.sh
    [widget6]=widget6-ctl.sh [widgets6]=widget6-ctl.sh
)
for name in "${!CMD_TARGETS[@]}"; do
    ln -sf "$HOME/scripts/${CMD_TARGETS[$name]}" "$HOME/.local/bin/$name"
done
echo "Linked: ${!CMD_TARGETS[*]}"

step "SDDM session for Serpantinum"
if confirm "Install the 'Hyprland (Serpantinum)' session into /usr/share/wayland-sessions/? (sudo)"; then
    sudo cp system/hyprland-serpantinum.desktop /usr/share/wayland-sessions/
    echo "Done -- pick it in the SDDM session menu."
else
    echo "Skipped. Without it you get the plain 'Hyprland' session (Caelestia)."
fi

step "Hyprland plugins (hyprpm)"
if confirm "Build/enable hypr-dynamic-cursors and infinite-desktop-v2 now? (sudo, takes a while)"; then
    hyprpm update
    hyprpm add https://github.com/virtcode/hypr-dynamic-cursors || true
    hyprpm enable dynamic-cursors || true
    hyprpm add https://github.com/lipeazul/infinite-desktop-v2 || true
    hyprpm enable infinite-desktop-v2 || true
else
    echo "Skipped -- the \"m~N\" workspace binds need infinite-desktop-v2 to work."
fi

step "Glass Lyrics (Spotify, via Spicetify)"
if command -v spicetify >/dev/null; then
    if confirm "Install Glass Lyrics into Spicetify now? (replaces Spicy Lyrics, runs spicetify apply)"; then
        bash spicetify/glass-lyrics/install.sh
    else
        echo "Skipped -- run spicetify/glass-lyrics/install.sh any time."
    fi
else
    echo "Spicetify isn't installed -- see the README to set it up, then run"
    echo "spicetify/glass-lyrics/install.sh."
fi

step "Monitors"
echo "Astrax is written for eDP-1 (laptop, p1) + HDMI-A-1 (external, p2)."
echo "If yours differ, start Hyprland, check 'hyprctl monitors' and adjust"
echo "~/.config/hypr/config/monitors.lua and variables.lua."

step "sddm + login shell"
if confirm "Enable and start the sddm service now?"; then
    sudo systemctl enable sddm
    sudo systemctl start sddm
else
    echo "Skipped. Later: sudo systemctl enable --now sddm"
fi
if confirm "Make fish your login shell? (chsh -- Astrax assumes it)"; then
    chsh -s /usr/bin/fish
fi

step "Done"
echo "Log in with 'Hyprland (Serpantinum)'. See README.md for the keybinds,"
echo "the music modes and the widget commands."
