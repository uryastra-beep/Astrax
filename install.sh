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
#
# ./install.sh --non-interactive (or ASTRAX_NONINTERACTIVE=1) answers every
# question with a safe default instead of asking: keep Astrax's keymap,
# install the SDDM session file, skip the Hyprland plugins, Glass Lyrics,
# enabling sddm, chsh and Liner (ASTRAX_LINER=1 turns Liner on), and stop if a different Serpantinum is installed.
# Serpantinum's own installer gets its defaults with telemetry turned off
# (keys in ASTRAX_SERP_KEYS, default "56"). Used by the CI test.

set -euo pipefail

PLUGIN_FAILURES=()

NONINTERACTIVE="${ASTRAX_NONINTERACTIVE:-0}"
for arg in "$@"; do
    case "$arg" in
        --non-interactive|-y) NONINTERACTIVE=1 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { echo; bold "== $* =="; }
# confirm "question" [default]: the default (y/n, "n" if omitted) is only
# used in --non-interactive mode
confirm() {
    local prompt="$1" default="${2:-n}" reply
    if [ "$NONINTERACTIVE" = 1 ]; then
        echo "$prompt [auto: $default]"
        [ "$default" = y ]
        return
    fi
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

# commands linked into ~/.local/bin at the end (declared here so the backup
# below can include whatever already exists under those names)
declare -A CMD_TARGETS=(
    [vm]=vm-ctl.sh
    [mode]=mode-ctl.sh
    [opti]=opti-ctl.sh
    [sharp]=sharp-transparent-ctl.sh
    [workspace]=workspace-ctl.sh
    [show]=show-ctl.sh
    [intro]=intro.sh
    [srp-update]=srp-update.sh
    [astrax-update]=astrax-update.sh
    [astrax-restore]=astrax-restore.sh
    [astrax-doctor]=astrax-doctor.sh
    [astrax-monitors]=astrax-monitors.sh
    [astrax-help]=astrax-help.sh
    [astrax-safe]=astrax-safe.sh
    [astrax-hypr-guard]=astrax-hypr-guard.sh
    [astrax-tour]=astrax-tour.sh
    [astrax-icons]=astrax-icons.sh
    [astrax-iphone]=astrax-iphone.sh
    [liner-bridge]=liner/liner-bridge
    [astrax-lyrics-rating]=astrax-lyrics-rating
    [lava-wallpaper]=lava-wallpaper.sh
    [cursor-style]=cursor-style.sh
    [cursor-plugin]=cursor-plugin.sh
    [outro]=outro.sh
    [hz]=hz-ctl.sh [Hz]=hz-ctl.sh [check]=hz-ctl.sh
    [widget]=widget-ctl.sh [widgets]=widget-ctl.sh
    [widget2]=widget2-ctl.sh [widgets2]=widget2-ctl.sh
    [widget3]=widget3-ctl.sh [widgets3]=widget3-ctl.sh
    [widget4]=widget4-ctl.sh [widgets4]=widget4-ctl.sh
    [widget5]=widget5-ctl.sh [widgets5]=widget5-ctl.sh
    [widget6]=widget6-ctl.sh [widgets6]=widget6-ctl.sh
)

step "Backing up everything Astrax will overwrite (before touching anything)"
# Every file of this repo that already exists in $HOME (dotfiles and the
# Serpantinum sources Astrax overrides) plus whatever already sits under the
# command names in ~/.local/bin -- taken BEFORE any package or Serpantinum's
# own installer runs, so it is the state you had. Restore with:
#   tar -xzf <backup> -C "$HOME"
BACKUP="$HOME/astrax-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
mapfile -t existing < <(
    {
        find .config .local scripts .zshrc .p10k.zsh \( -type f -o -type l \) 2>/dev/null
        for name in "${!CMD_TARGETS[@]}"; do echo ".local/bin/$name"; done
    } | while read -r f; do [ -e "$HOME/$f" ] || [ -L "$HOME/$f" ] && echo "$f"; done | sort -u
)
if [ "${#existing[@]}" -gt 0 ]; then
    tar -czf "$BACKUP" -C "$HOME" "${existing[@]}"
    tar -tzf "$BACKUP" > /dev/null || { echo "The backup can't be read back -- stopping before changing anything." >&2; exit 1; }
    echo "${#existing[@]} files saved to $BACKUP"
    echo "Restore later with: tar -xzf '$BACKUP' -C \"\$HOME\""
else
    echo "Nothing to back up (clean install)."
fi

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
    hyprland uwsm sddm xdg-desktop-portal-hyprland hyprpolkitagent \
    kitty fish zsh micro fastfetch btop \
    jq socat grim slurp imagemagick ffmpeg util-linux xorg-xhost libnotify \
    wireplumber playerctl cava cmatrix wl-clipboard cliphist fuzzel \
    python python-pillow python-numpy python-gobject python-dbus python-evdev \
    qt6-multimedia-ffmpeg nautilus gnome-calculator inotify-tools

# powerlevel10k is in some repos (CachyOS, chaotic-aur) but not in Arch's:
# take the repo package when there is one, the AUR one otherwise
P10K=zsh-theme-powerlevel10k
pacman -Si "$P10K" >/dev/null 2>&1 || P10K=zsh-theme-powerlevel10k-git
if pacman -Qq zsh-theme-powerlevel10k >/dev/null 2>&1 || pacman -Qq zsh-theme-powerlevel10k-git >/dev/null 2>&1; then
    P10K=""  # already installed, whichever one it is
fi
if [ "$P10K" = zsh-theme-powerlevel10k ]; then
    sudo pacman -S --needed --noconfirm "$P10K"
    P10K=""
fi

step "AUR packages (yay)"
# caelestia-shell's AUR package depends on quickshell-git, which conflicts
# with the official quickshell that Serpantinum needs. Same dance as
# Serpantinum's own installer: let caelestia pull quickshell-git, then swap
# back to the official package (see "quickshell" below).
if ! pacman -Qq caelestia-shell >/dev/null 2>&1 && pacman -Qq quickshell >/dev/null 2>&1; then
    sudo pacman -Rdd --noconfirm quickshell
fi
yay -S --needed --noconfirm \
    caelestia-shell caelestia-cli sptlrx-bin lavat unimatrix-git clock-rs-git \
    toilet ttf-rubik-vf bibata-cursor-theme brave-bin $P10K

step "Serpantinum (main shell -- not an AUR package, it has its own installer)"
# Pinned commit: Serpantinum's installer always resets to the latest master.
# Astrax overrides several of its QML files (WidgetRegistry.qml,
# WallpaperEngine.qml, faces/*, ...) and those were tested against this
# commit. Bump it by hand after validating a newer one.
# Serpantinum 2.3.0 (the v2.3.0 tag plus 23 later commits of its master: settings window option,
# dock/launcher fixes). Astrax is tested on exactly this commit.
SERPANTINUM_PINNED_COMMIT="ec45c01ff04ce2cfaff3eebab33f49075ee64f65"
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
    if [ "$NONINTERACTIVE" = 1 ]; then
        # its installer is a key-driven menu: "5" turns telemetry off,
        # "6" installs (CI also sends "4" for the small wallpaper set)
        # its last step asks "reboot now?" on /dev/tty, which fails without a
        # terminal (CI, cron) even though the install itself went fine: judge
        # it by the version it recorded instead of by its exit code
        if ! printf '%s' "${ASTRAX_SERP_KEYS:-56}" | bash "$SERPANTINUM_CACHE_DIR/install/install.sh"; then
            recorded="$(sed -n 's/^SERPANTINUM_COMMIT="\(.*\)"/\1/p' "$HOME/.local/state/serpantinum/version" 2>/dev/null)"
            if [ -n "$recorded" ] && [ "${SERPANTINUM_PINNED_COMMIT#"$recorded"}" != "$SERPANTINUM_PINNED_COMMIT" ]; then
                echo "Serpantinum's installer exited with an error after installing $recorded (its reboot prompt has no terminal) -- continuing."
            else
                echo "Serpantinum's installer failed." >&2
                exit 1
            fi
        fi
    else
        bash "$SERPANTINUM_CACHE_DIR/install/install.sh"
    fi
fi

step "quickshell (the official package, which Serpantinum needs)"
if pacman -Qq quickshell-git >/dev/null 2>&1; then
    sudo pacman -Rdd --noconfirm quickshell-git
fi
sudo pacman -S --needed --noconfirm quickshell

step "Copying the dotfiles to \$HOME"
cp -r .config "$HOME/"
cp -r .local "$HOME/"
cp -r scripts "$HOME/"
cp .zshrc .p10k.zsh "$HOME/"
chmod +x "$HOME"/scripts/*.sh "$HOME"/scripts/*.py "$HOME"/scripts/astrax-lyrics-rating "$HOME"/scripts/liner/liner-bridge 2>/dev/null || true
chmod +x "$HOME"/.config/quickshell/astrax-island/clip-event.sh "$HOME"/.config/quickshell/astrax-island/*.py \
    "$HOME"/.config/quickshell/astrax-mac-dock/control.py 2>/dev/null || true
# the macOS-style Dock is a user service: installed here, enabled only when the user turns the
# Dock on in SUPER+C > macOS Dock (that switch enables and disables the service)
systemctl --user daemon-reload 2>/dev/null || true
# a few JSON/QML files can't expand $HOME by themselves: fill in the placeholder
grep -rlI "@HOME@" .config .local 2>/dev/null |
    while read -r f; do sed -i "s|@HOME@|$HOME|g" "$HOME/$f"; done || true
# the installed version: the About page (SUPER+C) and astrax-update read it
mkdir -p "$HOME/.local/state/astrax"
tr -d '[:space:]' < VERSION > "$HOME/.local/state/astrax/version"
mkdir -p "$HOME/Pictures/Wallpapers"
# WORT: lava-live.mp4 is the entry that turns the lava wallpaper on from
# SUPER+W > Videos; it goes in Serpantinum's wallpaperDir
wall_dir="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wallpaperDir",""))' "$HOME/.config/serpantinum/settings.json" 2>/dev/null || true)"
wall_dir="${wall_dir:-$HOME/Pictures/Wallpapers}"
mkdir -p "$wall_dir"
cp wallpapers/lava-live.mp4 "$wall_dir/"

step "Keyboard layout"
echo "Astrax ships the author's keymap: Latin American layout, and Caps Lock only"
echo "toggles with Ctrl+Caps Lock (alone it does nothing)."
if confirm "Keep that keymap?" y; then
    echo "Kept (~/.config/hypr/custom-capslock.xkb)."
else
    read -r -p "XKB layout to use instead (e.g. us, es, de, latam) [us]: " layout
    layout="${layout:-us}"
    if [[ "$layout" =~ ^[a-z]{2,8}(,[a-z]{2,8})*$ ]]; then
        sed -i "s|^\( *\)kb_file = .*-- @astrax-keymap.*$|\1kb_layout = \"$layout\", -- @astrax-keymap|" "$HOME/.config/hypr/config/inputs.lua"
        echo "Using the '$layout' layout."
    else
        echo "'$layout' doesn't look like an XKB layout -- keeping Astrax's keymap."
    fi
fi
echo "Done -- this includes Astrax's versions of Serpantinum's widget registry,"
echo "widget faces, wallpaper engine, lock screen and bar modules."

step "Commands in ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for name in "${!CMD_TARGETS[@]}"; do
    ln -sfn "$HOME/scripts/${CMD_TARGETS[$name]}" "$HOME/.local/bin/$name"
done
echo "Linked: ${!CMD_TARGETS[*]}"

step "SDDM session for Serpantinum"
if confirm "Install the 'Hyprland (Serpantinum)' session into /usr/share/wayland-sessions/? (sudo)" y; then
    sudo cp system/hyprland-serpantinum.desktop /usr/share/wayland-sessions/
    echo "Done -- pick it in the SDDM session menu."
else
    echo "Skipped. Without it you get the plain 'Hyprland' session (Caelestia)."
fi

step "Hyprland plugins (hyprpm)"
if confirm "Build/enable hypr-dynamic-cursors and infinite-desktop-v2 now? (sudo, takes a while)"; then
    hyprpm update || PLUGIN_FAILURES+=("hyprpm update")
    hyprpm add https://github.com/virtcode/hypr-dynamic-cursors || PLUGIN_FAILURES+=("add hypr-dynamic-cursors")
    hyprpm enable dynamic-cursors || PLUGIN_FAILURES+=("enable dynamic-cursors (cursor animations, 'mouse' command)")
    hyprpm add https://github.com/lipeazul/infinite-desktop-v2 || PLUGIN_FAILURES+=("add infinite-desktop-v2")
    hyprpm enable infinite-desktop-v2 || PLUGIN_FAILURES+=("enable infinite-desktop-v2 (per-monitor workspace binds)")
    if [ "${#PLUGIN_FAILURES[@]}" -gt 0 ]; then
        echo "WARNING: some plugin steps failed:" >&2
        printf '  - %s\n' "${PLUGIN_FAILURES[@]}" >&2
    fi
else
    echo "Skipped -- the \"m~N\" workspace binds need infinite-desktop-v2 to work."
fi

step "Reactive cursor (patched hypr-dynamic-cursors)"
# The source goes to ~/.local/share/hypr-plugins/astrax-cursor and is built
# there. plugins.lua only loads it at login, and only if it was built against
# the installed Hyprland headers; otherwise it uses the stock hyprpm plugin.
CURSOR_DIR="$HOME/.local/share/hypr-plugins/astrax-cursor"
mkdir -p "$CURSOR_DIR"
cp -r plugins/dynamic-cursors/. "$CURSOR_DIR/"
[ -f "$HOME/.config/cursor-style" ] || echo astrax > "$HOME/.config/cursor-style"
if confirm "Build the reactive cursor plugin now? (needs Hyprland's headers, about a minute)" y; then
    if bash scripts/cursor-plugin.sh build; then
        echo "Built -- it loads at your next login. Rebuild it after every Hyprland update: cursor-plugin build"
    else
        PLUGIN_FAILURES+=("build the reactive cursor (cursor-plugin build)")
        echo "WARNING: the reactive cursor didn't build; the stock plugin is used meanwhile." >&2
    fi
else
    echo "Skipped -- build it later with: cursor-plugin build"
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

step "Liner (optional, unofficial -- see docs/liner.md)"
echo "Liner (tryliner.fun) has word and syllable synced lyrics. liner-bridge shares"
echo "them with Astrax. Not affiliated with Liner; nothing of Liner is modified or"
echo "redistributed -- its official AppImage is downloaded from its own releases."
if [ "${ASTRAX_LINER:-0}" = 1 ] || confirm "Download Liner and set it up for Astrax? (sudo for a few packages)"; then
    bash scripts/liner/install-liner.sh || echo "WARNING: the Liner setup failed (Astrax works without it)." >&2
else
    echo "Skipped -- run bash scripts/liner/install-liner.sh any time."
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
if [ "${#PLUGIN_FAILURES[@]}" -gt 0 ]; then
    echo "Finished WITH PROBLEMS -- these Hyprland plugin steps failed:"
    printf '  - %s\n' "${PLUGIN_FAILURES[@]}"
    echo "Fix them with hyprpm before relying on the features listed."
fi
echo "Optional downloads (not part of this repo): astrax-icons install (Apple-style app icons),"
echo "astrax-iphone install (iPhone notifications / Bluetooth audio bridge)."
echo "Log in with 'Hyprland (Serpantinum)'. See README.md for the keybinds,"
echo "the music modes and the widget commands."
