# Astrax

[![CI](https://github.com/uryastra-beep/Astrax/actions/workflows/ci.yml/badge.svg)](https://github.com/uryastra-beep/Astrax/actions/workflows/ci.yml)

**A music-focused rice for Hyprland**, built on the [Serpantinum](https://github.com/ilyamiro/serpantinum)
shell (Quickshell/QML) with [Caelestia](https://github.com/caelestia-dots/shell) as a fallback session.

The desktop follows whatever you're listening to: window borders, widgets, visualizers and the
whole shell theme take their colors from the album art, lyrics are on screen word by word, and some
songs switch the desktop into their own hand-made theme.

**Version:** 1.6.0 (see [CHANGELOG.md](CHANGELOG.md))  
**Current Serpantinum version: 2.2.12** (the version Astrax is developed and tested on; the installer pins it)

## Install

Arch Linux or a derivative (made on CachyOS), as your normal user:

```bash
git clone https://github.com/uryastra-beep/Astrax.git && cd Astrax && ./install.sh
```

The installer:

- installs the packages (pacman + yay; it installs yay if it's missing),
- installs Serpantinum **2.2.12** with its own installer, pinned to the commit Astrax was tested with,
- **before changing anything**, backs up every file it will overwrite (dotfiles, the Serpantinum
  sources Astrax overrides and the command names in `~/.local/bin`) to
  `~/astrax-backup-<date>.tar.gz`. Restore it with `tar -xzf ~/astrax-backup-<date>.tar.gz -C ~`,
- copies the dotfiles to `$HOME` and links the commands into `~/.local/bin`,
- asks which **keyboard layout** to use (Astrax's own keymap is Latin American with Caps Lock
  only on Ctrl+Caps Lock, or any XKB layout you type),
- **asks first** before touching the system: the SDDM session, the Hyprland plugins, enabling sddm,
  changing your login shell and installing Glass Lyrics. If a plugin fails to build it tells you
  at the end.

`./install.sh --non-interactive` answers every question with a safe default instead of asking
(keeps Astrax's keymap, installs the SDDM session file, skips the plugins, Glass Lyrics, enabling
sddm and `chsh`, and turns Serpantinum's telemetry off).

Then log in with the **Hyprland (Serpantinum)** session from SDDM. The plain **Hyprland** session
starts Caelestia instead.

### ⚠️ Updating Serpantinum can break Astrax

Astrax is tested against **one pinned Serpantinum version (currently 2.2.12)** and replaces some of Serpantinum's own
source files (widget registry, widget faces, wallpaper engine, lock screen, bar modules). Updating
Serpantinum (its own installer or `serpantinum update`) wipes and re-copies
`~/.local/share/serpantinum`, so **those changes are lost** and the newer Serpantinum code may not
work with the rest of Astrax. **You can lose your setup.**

Don't update Serpantinum directly. Use:

```bash
srp-update
```

It asks first, backs up everything a Serpantinum update can touch (Serpantinum's files, its
settings and state, `~/.config/hypr`, `~/.config/quickshell`, `~/scripts`, `~/.local/bin`) to
`~/astrax-backups/srp-update-<date>.tar.gz`, checks the backup can be read, and only then updates
Serpantinum. If anything breaks, put **everything** back with one command:

```bash
astrax-restore
```

It restores the latest backup and returns Serpantinum to the commit it was on (log out and back
in afterwards). `astrax-restore --list` shows every backup and `astrax-restore <file>` restores a
specific one.

### Monitors

By default Hyprland sets up every screen by itself (preferred mode, automatic position and scale),
so nothing is tied to the author's hardware. To pin modes, positions or scales, fill in
`MONITOR_LAYOUT` in `~/.config/hypr/config/monitors.lua`. That file is the only place monitors are
configured; it has the author's setup as an example.

The scripts call two outputs **p1** and **p2** (`MONITOR1` / `MONITOR2` in `variables.lua`, by default
`eDP-1` and `HDMI-A-1`). The widget sets and per-monitor workspaces use those names, so set them to
your outputs from `hyprctl monitors`.

## Glass Lyrics for Spotify

Astrax ships **Glass Lyrics**, a fork of [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics)
for [Spicetify](https://spicetify.app): glass-styled lyrics plus a cover transition when Spotify
crossfades into the next song. It lives in [`spicetify/glass-lyrics`](spicetify/glass-lyrics).

1. Install Spotify and Spicetify (skip what you already have):

   ```bash
   yay -S spotify spicetify-cli
   ```

   ```bash
   sudo chgrp -R "$(id -gn)" /opt/spotify && sudo chmod -R g+w /opt/spotify
   ```

   ```bash
   spicetify backup apply
   ```

   This is only needed for the AUR `spotify` package: Spicetify has to write into its folder. It gives
   write access to **your** group only (on Arch, your private user group), not to every user.

2. Install Glass Lyrics (the main installer also offers this step):

   ```bash
   ./spicetify/glass-lyrics/install.sh
   ```

It replaces Spicy Lyrics, because both extensions use the same lyrics page. If you installed Spicy Lyrics
from the Spicetify Marketplace, uninstall it there too. Settings are in the lyrics settings panel
under **Glass Lyrics**.

## What's in it

### Music → color

- `scripts/border_colors.py` follows the active MPRIS player (`playerctl`), extracts colors from the
  album art and applies them to the active window border, the custom widgets and the cava
  visualizers. With nothing playing, it falls back to the wallpaper's colors.
- `CTRL+SUPER+C` makes **every** Serpantinum widget follow the song colors; `ALT+SUPER+C` forces the
  real wallpaper colors instead.
- **Cover mode**: every song without a special mode (see below) gets a four-color theme built from
  the most abundant colors of its album art.

### Special song modes

`scripts/special_modes.json` matches songs by artist, title or album (regex) and switches the whole
desktop into a hand-made theme. The theme covers the shell palette, border and widget colors, a
screen shader gradient, a different color for each lyric line and the visualizer gradient. Three
modes are included: **TV Girl**, **Streetcat** and **La Jangada**. Themes cross-fade when a mode starts
or ends. Read the `_doc` field in that file to add your own.

### Lyrics and visualizers

- Native Serpantinum widgets added by Astrax: **Lyrics** (synced, via `sptlrx`), **Lavat**
  (metaballs that follow the song color) and **Unimatrix** (Matrix rain). Add them from Serpantinum's
  widget editor.
- Bar lyrics module (`lyrics`, enabled on the left of the bar) that shows the current word, with
  background vocals underneath; `ALT+SUPER+A` hides it. Lyrics come from NetEase/lrclib, word-by-word
  when available and estimated from syllables otherwise.
- Widget sets controlled from the terminal, each one `play | off | p1 | p2 | opti on|off | status | help`:

  | Command | What it is |
  |---|---|
  | `widgets` | clock + lavat (kitty windows), plus the native visualizer/lyrics preset |
  | `widgets2` | clock + lyrics + fullscreen cava on a click-through layer surface |
  | `widgets3` | fullscreen cava only, "part of the wallpaper" |
  | `widgets4` | mini desktop tied to a workspace: terminal, btop, unimatrix, lavat |
  | `widgets5` | p2-only mini desktop: terminal, unimatrix, lavat |
  | `widgets6` | unimatrix + lavat + btop with a fixed layout per monitor |

### Video wallpaper with sound

Serpantinum's wallpaper engine is extended with:

- real audio (muted by default, `CTRL+SUPER+S`) that follows your default output device,
- a pause on each screen while a real app covers it (`CTRL+SUPER+A` keeps it playing),
- audio priority for p1 and position sync between screens playing the same video.

Optionally, put a still image at `~/Pictures/Wallpapers/fallback.jpg`. It is shown over a paused video.

### WORT — Wallpaper On Real Time (lava wallpaper)

A "lava lamp" wallpaper drawn live by a shader (`~/.config/quickshell/lava-wallpaper/`): up to 7
colored bubbles that melt into each other. The colors follow what you're doing:

1. **Music playing**: the same colors as the visualizer (the special mode's palette, or the song
   colors). Without a special mode they come from the album art.
2. **No music**: the colors of the focused app's icon.
3. **Nothing**: a purple palette.
4. **TV Girl mode** adds two black bubbles.

Serpantinum's theme follows the lava colors too, except while a special song mode is active.

Pick **`lava-live.mp4`** in `SUPER+W` > Videos to turn it on (the installer puts that small
placeholder video in your wallpaper folder; it is paused while the lava runs). Picking any other
wallpaper turns it off, and it comes back on its own after a restart if lava-live was the last one.
`lava-wallpaper on|off|toggle|status` controls it from the terminal.

It hooks into Serpantinum's `singletons/theme/Wallpaper.qml`. That file is overwritten by a
Serpantinum update; `patches/serpantinum-Wallpaper.qml-wort.patch` re-applies the hooks:

```bash
cd ~/.local/share/serpantinum && patch -p1 < /path/to/Astrax/patches/serpantinum-Wallpaper.qml-wort.patch
```

### Intro, outro and the power wave

- `intro`: splash screen where the logo lights up like a neon tube and the theme waves drop to reveal
  the desktop. It also plays on boot and after unlocking.
- `outro`: the same animation in reverse. The physical power button starts the wave: tap again before
  it reaches the top to cancel. While you're logged in, Astrax holds a logind inhibitor
  (`systemd-inhibit --what=handle-power-key`, no root needed) so the button doesn't power off
  behind the animation's back.
- `boot-splash/` holds a matching Plymouth theme and SDDM theme. They're optional and installed by
  hand, see [`boot-splash/README.md`](boot-splash/README.md).

### Launchers and window handling

- `astrax-launcher`: left icon rail opened by tapping `SUPER`. Shows most-used apps first;
  `Ctrl+F` pins the selected app.
- `astrax-app-switcher`: `ALT+Tab` or the `Menu` key; a grid of live window previews for the
  focused screen.
- `astrax-ws-osd`: workspace number on screen when switching.
- `SUPER+R` pins a window's size and place; `SUPER+D` toggles floating ↔ tiled for the workspace.

### Other commands

| Command | What it does |
|---|---|
| `mode music\|study\|gaming\|privacy\|code\|sleep` | quick app/volume profiles (combinable). Apps that aren't installed are skipped and reported; `study`/`gaming` close nothing unless their app can start |
| `opti on\|off` | fewer blur passes + stops the taskbar watcher |
| `sharp on\|off` (`CTRL+SUPER+G`) | sharp corners and no blur |
| `vm caelestia\|serpantium\|status` | switch shells live without restarting Hyprland; it reloads the binds of the new shell and goes back to the old one if the new one fails to start |
| `hz p1\|p2 set <hz>`, `check Hz all` | refresh rate per monitor, capped at what the screen advertises (overclocks only for panels you list in `~/.config/astrax/hz-limits`) |
| `workspace status` | open apps per workspace and the bind to reach each one |
| `mouse rotate\|tilt\|stretch\|none` | cursor animation (hypr-dynamic-cursors); `mouse trail on` needs `~/.local/share/hypr-plugins/build-trail.sh` first |
| `lava-wallpaper on\|off\|toggle\|status` | WORT, the lava wallpaper (normally driven by picking `lava-live.mp4` in `SUPER+W`) |
| `srp-update` | back up everything, then update Serpantinum (see the warning under Install) |
| `astrax-restore` | undo `srp-update`: restore the latest backup (`--list`, or pass a file) |
| `CTRL+SUPER+N` | sleep mode: locks, then screens off and idle apps frozen; music keeps playing. If the lock doesn't engage, nothing is frozen |

## Keybinds (Serpantinum session)

| Keys | Action |
|---|---|
| tap `SUPER` | Astrax launcher |
| `SUPER+SPACE` | Serpantinum launcher |
| `SUPER+RETURN` | kitty |
| `SUPER+Q` | close window |
| `SUPER+1..0` / `SUPER+SHIFT+1..0` | go to / move window to workspace (per monitor) |
| `SUPER+scroll` | previous / next workspace |
| `SUPER+arrows` | focus window in that direction |
| `SUPER+SHIFT+arrows` / `SUPER+CTRL+arrows` | move / resize floating window |
| `ALT+Tab`, `Menu` | app switcher |
| `SUPER+M` | small floating Spotify (toggle) |
| `SUPER+C`, `SUPER+H` | Serpantinum settings |
| `SUPER+W` | wallpaper picker |
| `SUPER+SHIFT+W` | widgets on/off on the focused screen |
| `CTRL+SUPER+ALT+G` | hide/show the desktop widgets (gaming) |
| `CTRL+SUPER+C` / `ALT+SUPER+C` | colors from music / from wallpaper |
| `CTRL+SUPER+S` | wallpaper sound on/off |
| `CTRL+SUPER+SHIFT+S` | keep wallpaper sound playing through apps |
| `CTRL+SUPER+A` | keep the video wallpaper playing through apps |
| `SUPER+I` | search every keybind (Serpantinum / Caelestia / All) |
| `SUPER+V` | clipboard history |
| `SUPER+.` | emoji picker |
| `SUPER+N` | do not disturb |
| `SUPER+A` / `ALT+SUPER+A` | auto-hide the bar / hide the bar lyrics |
| `SUPER+L` | lock |
| `SUPER+R` | pin / unpin window |
| `Power` | power-off wave (tap again to cancel) |

The full list lives in `~/.config/hypr/config/binds-serpantinum.lua` and `hyprland.lua`.

## Notes

- Hyprland is configured in **Lua** (`~/.config/hypr/hyprland.lua` + `config/*.lua`). Classic
  `hyprctl keyword` doesn't apply here; use `hyprctl repl` and `hl.dsp.*` dispatchers.
- Workspaces use the [infinite-desktop-v2](https://github.com/lipeazul/infinite-desktop-v2) plugin
  and are addressed per monitor (`m~N`).
- Some files override Serpantinum's own sources under `~/.local/share/serpantinum/src`. Updating
  Serpantinum overwrites them: update with `srp-update` and undo with `astrax-restore`.
- No API keys or accounts are needed. Lyrics come from public APIs (lrclib.net, NetEase).
- Optional extras, off unless you set them up:
  - `~/scripts/brave_watcher.sh` closes Brave once it has no windows left. It never does this
    during a download. Enable it with `touch ~/.config/astrax/enable-brave-watcher`.
  - The eww taskbar scripts (`taskbar-*`) need your own eww config.
  - `Lyrics.qml` can also read a word-synced feed from `~/.cache/spicy-bridge` and YouTube captions
    from a `~/.local/bin/yt-lyrics` tool. Neither one ships with Astrax.
- **Tests** (`tests/`, run by GitHub Actions on every push):
  1. static checks: shell, Python, Lua and JSON syntax, `shellcheck`, that every script and
     Quickshell config the binds call exists, and no personal data in the repo;
  2. `srp-update` / `astrax-restore` against a fake home and a fake Serpantinum;
  3. a full `./install.sh --non-interactive` on a **clean Arch container**, then checks that
     Serpantinum is on the pinned commit, every dotfile and command is in place, and that running
     the installer a second time works and backs up first.

  A container has no screen, so the CI doesn't start Hyprland or Quickshell: it proves the install
  finishes and puts everything in place, not that the desktop looks right.

## Credits

- [Serpantinum](https://github.com/ilyamiro/serpantinum) by ilyamiro, the main shell (AGPL-3.0)
- [Caelestia](https://github.com/caelestia-dots/shell), the fallback shell, clipboard and emoji picker
- [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics) by Spikerko, the base of Glass Lyrics (AGPL-3.0)
- cava shaders by rezky_nightky and the cava project; Material You SDDM theme by Darkkal44 (MIT)
- [hypr-dynamic-cursors](https://github.com/virtcode/hypr-dynamic-cursors), [infinite-desktop-v2](https://github.com/lipeazul/infinite-desktop-v2), [sptlrx](https://github.com/raitonoberu/sptlrx), [lavat](https://github.com/AngelJumbo/lavat)

## License

[AGPL-3.0](LICENSE), the same license as Serpantinum, whose source files Astrax modifies. Bundled
third-party pieces keep their own licenses.
