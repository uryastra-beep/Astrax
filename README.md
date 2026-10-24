# Astrax

[![CI](https://github.com/uryastra-beep/Astrax/actions/workflows/ci.yml/badge.svg)](https://github.com/uryastra-beep/Astrax/actions/workflows/ci.yml)

**A music-focused rice for Hyprland**, built on the [Serpantinum](https://github.com/ilyamiro/serpantinum)
shell (Quickshell/QML) with [Caelestia](https://github.com/caelestia-dots/shell) as a fallback session.

The desktop follows whatever you're listening to: window borders, widgets, visualizers and the
whole shell theme take their colors from the album art, lyrics are on screen word by word, and some
songs switch the desktop into their own hand-made theme.

**Version:** 1.9.0 (see [CHANGELOG.md](CHANGELOG.md))  
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

### Commands and health check

`astrax-help` lists every Astrax command. `astrax-doctor` checks the install (versions, drifted
overrides, monitors, the cursor plugin, commands, Glass Lyrics, backups) and prints how to fix
whatever is off; run it after any update. Both are read-only and never fix anything on their own.

If something misbehaves, `astrax-safe on` turns off the patched cursor plugin, uses the normal
cursor and enables opti; `astrax-safe off` puts it back. It also works from a TTY (Ctrl+Alt+F3)
when the desktop itself won't start. After a Hyprland update a notification tells you whether the
patched cursor still matches; the stock plugin is used meanwhile, never a mismatched one.

To stop lyrics for a source, add a regular expression per line to
`~/.config/astrax/lyrics-blocklist.txt` (matched against the player, URL, title and artist).

### Monitors

`astrax-monitors` lists your outputs and sets p1/p2 for you (or `astrax-monitors eDP-1 HDMI-A-1`).
By default Hyprland sets up every screen by itself (preferred mode, automatic position and scale),
so nothing is tied to the author's hardware. To pin modes, positions or scales, fill in
`MONITOR_LAYOUT` in `~/.config/hypr/config/monitors.lua`. That file is the only place monitors are
configured; it has the author's setup as an example.

The scripts call two outputs **p1** and **p2** (`MONITOR1` / `MONITOR2` in `variables.lua`, by default
`eDP-1` and `HDMI-A-1`). The widget sets and per-monitor workspaces use those names, so set them to
your outputs from `hyprctl monitors`.

### Updating Astrax

`SUPER+C` > **About** shows the Astrax version under Serpantinum's. When a newer release exists,
a green card appears there with **Changelog** and **Update** buttons (like Serpantinum's), and a
desktop notification arrives once per new version (clicking it opens the About page). The check
runs a minute after login and every 6 hours. From a terminal: `astrax-update check`, `astrax-update run`.
`Update` fetches the release tag and runs its `./install.sh`, which backs up every file it overwrites first.

### Updating Serpantinum while Astrax is installed

Serpantinum updates its own About page too, but **don't take that update blindly**. You have two options:

1. **Wait for a new Astrax release** that ships the new Serpantinum version. It is ported and tested
   first, and the About page will offer it as an Astrax update. This is the safe way.
2. **Update it yourself with `srp-update`** (backs up first, undo with `astrax-restore`). This is at
   your own risk: Astrax's replaced files get overwritten, the new Serpantinum code may not work
   with the rest of Astrax, and your setup can end up broken or corrupted.

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

### Liner lyrics (optional, unofficial)

[Liner](https://tryliner.fun) is a desktop music app with word- and syllable-synced lyrics.
`liner-bridge` opens it and passes those lyrics to the bar lyrics module (word by word, and
syllable by syllable for Liner), and adds a "Liner" MPRIS player so its title and cover always
show up. The installer asks about it (off by default); `bash scripts/liner/install-liner.sh`
sets it up any time. Open Liner through `liner-bridge` (the menu entry does) or it shares nothing.

This is **unofficial and not affiliated with Liner**. Astrax does not modify or redistribute
Liner (its official AppImage is downloaded from Liner's own releases and checksum-checked); it only
reads lyrics that Liner's own client already downloaded, through a local DevTools pipe, and the
injected script lives only in memory. Tested with Liner 0.1.35; newer versions may need adjustments. Details, limits and what can break: [docs/liner.md](docs/liner.md).

Click the lyrics module in the bar to rate how well the lyrics synced (1-5 stars). Lyrics rated
4-5 stars are saved and used for that song on any player.

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
2. **No music**: the colors of the focused app's icon (a terminal counts as no app).
3. **Nothing**: a purple palette.
4. **TV Girl mode** adds two black bubbles.

Serpantinum's theme follows the lava colors too, except while a special song mode is active.
The bubbles swell with the bass and the colors brighten with any loud sound (a small cava of its
own, `cava.conf`), a bit softer when the palette is mostly white.

Pick **`lava-live.mp4`** in `SUPER+W` > Videos to turn it on (the installer puts that small
placeholder video in your wallpaper folder; it is paused while the lava runs). Picking any other
wallpaper turns it off, and it comes back on its own after a restart if lava-live was the last one.
`lava-wallpaper on|off|toggle|status` controls it from the terminal.

It hooks into Serpantinum's `singletons/theme/Wallpaper.qml`. That file is overwritten by a
Serpantinum update; `patches/serpantinum-Wallpaper.qml-wort.patch` re-applies the hooks:

```bash
cd ~/.local/share/serpantinum && patch -p1 < /path/to/Astrax/patches/serpantinum-Wallpaper.qml-wort.patch
```

### Reactive cursor

A patched [hypr-dynamic-cursors](https://github.com/virtcode/hypr-dynamic-cursors) (BSD-3-Clause,
source in [`plugins/dynamic-cursors`](plugins/dynamic-cursors), changes in its `PATCHES.md`) draws a
colored glow around a plain arrow, depending on what the cursor means:

| Glow | Cursor type |
|---|---|
| blue | clickable (links, buttons) |
| white | text |
| light blue | draggable |
| orange | crosshair |
| pink | resize |
| green | copy |
| red | error / not allowed |
| half blue, half white | alias |
| every color, spinning | loading |
| purple | anything else |

Animations: a continuous light trail, the arrow shrinks on click, arrow and light stretch toward the
scroll direction and spring back, a 320 ms color fade, stretch by speed and rotation with movement.

Pick the style live in Serpantinum's menu (`SUPER+C` > General > **Cursor style**):
**Normal (classic white)** (Bibata-Modern-Ice, no glow and no animations), **Astrax** or
**High contrast** (another palette, based on Okabe-Ito). Under the selector there's a legend (each
color and what it means) and a switch for every animation. From a terminal: `cursor-style
normal|astrax|highcontrast`, `cursor-style anim <name> 0|1`.

Color is the only cue that tells the cursor types apart. Making the colors configurable, or adding
different shapes per type, is future work.

- **Cursor lock:** apps can't set their own cursor image (they all show the arrow), except a hidden
  cursor and the window classes listed in `~/.config/cursor-allow.txt` (games, by default).
- **Safety net** (`plugins.lua`): the patched plugin only loads at login, and only if it was built
  against the installed Hyprland headers. If it crashes in the first 25 s, the next login falls back to
  the stock hyprpm plugin (`rm -r ~/.cache/hypr-trail` to try again).
- **Rebuild it after every Hyprland update**: `cursor-plugin check` tells you, `cursor-plugin build`
  rebuilds it (until then the stock plugin is used). **Never hot-reload the plugin** (`hyprctl plugin
  load/unload`): log out and back in instead.
- The arrow-only theme `Bibata-ArrowBare` is derived from [Bibata](https://github.com/ful1e5/Bibata_Cursor)
  (GPL-3.0, see its `LICENSE-NOTE.md`).
- [`docs/cursor-test.html`](docs/cursor-test.html) is a page with every cursor type, to try them all.
- Serpantinum's menu row is a patch to its `GeneralTab.qml`: a Serpantinum update overwrites it.
  `./install.sh` puts it back, or re-apply it by hand:

  ```bash
  cd ~/.local/share/serpantinum && patch -p1 < /path/to/Astrax/patches/serpantinum-GeneralTab.qml-cursor-style.patch
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
- `astrax-island`: the Dynamic Island, see [below](#dynamic-island).
- `SUPER+R` pins a window's size and place; `SUPER+D` toggles floating ↔ tiled for the workspace.

### Dynamic Island

`astrax-island` is a black pill at the top of the screen (position configurable) that replaces
Serpantinum's notification popups and its volume/brightness OSD. It shows:

- notifications: click one to run its default action (screenshot and recording notifications open
  the folder), right-click dismisses it, action buttons sit under the text
- volume, microphone and brightness changes, Caps Lock and Num Lock, airplane mode
- charging, plugged/unplugged and low battery, Bluetooth and USB devices
- the current song, compact or expanded
- file activity: downloads with live progress (`.crdownload` / `.part`) and files added, changed,
  renamed or deleted, with bursts grouped ("12 items"). It watches Downloads, Documents and Desktop
  (Pictures, Videos and Music are optional; folders that don't exist are skipped) and ignores
  SQLite sidecars (`-wal`, `-shm`, `-journal`), lock files and anything that lives under 2 s
- the clipboard: copying, cutting and pasting text, images (with a thumbnail) and files. Copies a
  password manager marks as secret are never announced. Pasting is announced by two non-consuming
  binds (`Ctrl+V`, `Ctrl+Shift+V`); the key still reaches the app as before
- each app's real icon in notifications (from its `.desktop` entry; otherwise a generated squircle
  with the app's initial)

Triple-click the island (or `qs -c astrax-island ipc call island toggleList`) for the activity
list: notifications, files, clipboard and devices in one list, newest first. It closes when you
click outside (while it is open a transparent layer covers the screen and takes that click).

Gestures on the island: one click opens the media panel (after a 0.5 s wait so a triple click can
be told apart; closing is instant), triple left click = notification history, double right click =
Overview, triple right click = Files Shelf. Clicking outside compacts it without blocking the apps
behind it, and right-click on a notification dismisses it. New notifications stack on top of the
older ones (three visible at a time).

- **Super and Alt+Tab inside the island**: the app launcher (five apps per row, `WASD` / arrows,
  `Shift` / `Enter` to open, `Ctrl+L` to search, `Ctrl+F` to pin) and the window switcher (up to four
  windows per row) open in the island. With the island off, the original `astrax-launcher` and
  `astrax-app-switcher` panels are used.
- **Overview**: clock, device batteries, Wi-Fi / Bluetooth, an on-this-PC screen-time estimate
  (idle after 60 s, seven days kept locally), system and storage, and a files shortcut. Widgets can
  be turned on, off and reordered in `SUPER+C` > Dynamic Island.
- **Files Shelf**: keep up to eight groups of four files, drag or copy a whole group out again.
- **Lyrics in the island**: word-by-word lyrics under the media panel, read from the lyrics Astrax
  already has. They need the optional helper from `astrax-iphone install`; without it the island
  just shows no lyrics.

Optional Liquid Glass (off by default; not available while `opti` is on, it comes back when you turn opti off): the pill blurs what is behind it and refracts the edge
(a shader plus a single screen capture, taken only while glass is on).

Configure it in `SUPER+C` > Dynamic Island: a switch per kind of notice, X/Y position sliders, a
screen selector, glass / opacity / refraction, bounce, margin, duration, follow the monitor and hide
when idle. Settings live in the `island` key of Serpantinum's `settings.json`. It starts at login
(`autostart.lua`); to run it by hand: `qs -c astrax-island -d`.

It needs `inotify-tools`, `wl-clipboard`, `jq` and `util-linux` (the installer adds them). It needs Astrax's overrides of Serpantinum's `NotificationManager.qml`, `NotificationPopups.qml`,
`OsdController.qml`, `GuidePopup.qml` and `GuideSidebar.qml` (plus the new `IslandTab.qml`);
`patches/serpantinum-*-island.patch` re-apply them after a Serpantinum update. Turning the island
off in its tab gives Serpantinum's own popups back.

### macOS-style Dock (optional)

A separate Dock, independent of Serpantinum's: `~/.config/quickshell/astrax-mac-dock/`, run as the
user service `astrax-mac-dock.service`. Turn it on in `SUPER+C` > macOS Dock (that switch also
enables the service and turns Serpantinum's own Dock off; turning it off restores it). Magnification,
bounce on launch, dots for running apps, Shift+click for a new instance, right-click to keep / remove
or close windows, auto-hide, one Dock per screen, optional Liquid Glass. Its settings live in the
`macDock` key of `settings.json`.

### Optional downloads: Apple-style icons and the iPhone bridge

Two things are not in this repository on purpose; each is one command:

```bash
astrax-icons install      # Apple-style app icons for Super / Alt+Tab / the Dock (astrax-icons remove)
astrax-iphone install     # iPhone notifications + Bluetooth audio bridge (astrax-iphone remove)
```

The icon artwork belongs to Apple and the apps' developers and is not covered by Astrax's license
(see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). Without the icon pack Astrax uses the normal
system icons; without the bridge the island still works, it just has no iPhone data or island lyrics.

### Other commands

| Command | What it does |
|---|---|
| `mode music\|study\|gaming\|privacy\|code\|sleep` | quick app/volume profiles (combinable). Apps that aren't installed are skipped and reported; `study`/`gaming` close nothing unless their app can start |
| `opti on\|off` | fewer blur passes + stops the taskbar watcher |
| `sharp on\|off` (`CTRL+SUPER+G`) | sharp corners and no blur |
| `vm caelestia\|serpantium\|status` | switch shells live without restarting Hyprland; it reloads the binds of the new shell and goes back to the old one if the new one fails to start |
| `hz p1\|p2 set <hz>`, `check Hz all` | refresh rate per monitor, capped at what the screen advertises (overclocks only for panels you list in `~/.config/astrax/hz-limits`) |
| `workspace status` | open apps per workspace and the bind to reach each one |
| `mouse rotate\|tilt\|stretch\|none` | cursor movement animation (hypr-dynamic-cursors) |
| `cursor-style normal\|astrax\|highcontrast` | reactive cursor style; `cursor-style anim <name> 0\|1` toggles an animation (also in `SUPER+C` > General) |
| `cursor-plugin check\|build` | is the reactive cursor built for this Hyprland? / rebuild it (after every Hyprland update) |
| `lava-wallpaper on\|off\|toggle\|status` | WORT, the lava wallpaper (normally driven by picking `lava-live.mp4` in `SUPER+W`) |
| `astrax-update check\|run` | is there a newer Astrax release? / update to it |
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
- [@braccato/parsers](https://github.com/better-lyrics/braccato) (MIT) parses the lyric formats in `liner-bridge`; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- [hypr-dynamic-cursors](https://github.com/virtcode/hypr-dynamic-cursors), [infinite-desktop-v2](https://github.com/lipeazul/infinite-desktop-v2), [sptlrx](https://github.com/raitonoberu/sptlrx), [lavat](https://github.com/AngelJumbo/lavat)

## License

[AGPL-3.0](LICENSE), the same license as Serpantinum, whose source files Astrax modifies. Bundled
third-party pieces keep their own licenses.
