# Astrax

**A music-focused rice for Hyprland**, built on the [Serpantinum](https://github.com/ilyamiro/serpantinum)
shell (Quickshell/QML) with [Caelestia](https://github.com/caelestia-dots/shell) as a fallback session.

The desktop follows whatever you're listening to: window borders, widgets, visualizers and the
whole shell theme take their colors from the album art, lyrics are on screen word by word, and some
songs switch the desktop into their own hand-made theme.

**Version:** 1.0.0

## Install

Arch Linux or a derivative (made on CachyOS), as your normal user:

```bash
git clone https://github.com/uryastra-beep/Astrax.git && cd Astrax && ./install.sh
```

The installer:

- installs the packages (pacman + yay; it installs yay if it's missing),
- installs Serpantinum with its own installer, pinned to the commit Astrax was tested with,
- backs up every file it is about to overwrite to `~/astrax-backup-<date>.tar.gz`,
- copies the dotfiles to `$HOME` and links the commands into `~/.local/bin`,
- **asks first** before touching the system: the SDDM session, the Hyprland plugins, enabling sddm,
  changing your login shell and installing Glass Lyrics.

Then log in with the **Hyprland (Serpantinum)** session from SDDM. The plain **Hyprland** session
starts Caelestia instead.

Astrax was made for a laptop panel (`eDP-1`, called **p1**) plus an external HDMI monitor (`HDMI-A-1`,
called **p2**). With other outputs, check `hyprctl monitors` and adjust
`~/.config/hypr/config/monitors.lua` and `variables.lua`.

## Glass Lyrics for Spotify

Astrax ships **Glass Lyrics**, a fork of [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics)
for [Spicetify](https://spicetify.app): glass-styled lyrics plus a cover transition when Spotify
crossfades into the next song. It lives in [`spicetify/glass-lyrics`](spicetify/glass-lyrics).

1. Install Spotify and Spicetify (skip what you already have):

   ```bash
   yay -S spotify spicetify-cli
   ```

   ```bash
   sudo chmod a+wr /opt/spotify /opt/spotify/Apps -R
   ```

   ```bash
   spicetify backup apply
   ```

   The `chmod` is only needed for the AUR `spotify` package (Spicetify has to write into its folder).

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
- Bar lyrics module that shows the current line word by word.
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

### Intro, outro and the power wave

- `intro`: splash screen where the logo lights up like a neon tube and the theme waves drop to reveal
  the desktop. It also plays on boot and after unlocking.
- `outro`: the same animation in reverse. The physical power button starts the wave: tap again before
  it reaches the top to cancel.
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
| `mode music\|study\|gaming\|privacy\|code\|sleep` | quick app/volume profiles (combinable) |
| `opti on\|off` | fewer blur passes + stops the taskbar watcher |
| `sharp on\|off` (`CTRL+SUPER+G`) | sharp corners and no blur |
| `vm caelestia\|serpantium\|status` | switch shells live without restarting Hyprland |
| `hz p1\|p2 set <hz>`, `check Hz all` | refresh rate per monitor, with a safety cap |
| `workspace status` | open apps per workspace and the bind to reach each one |
| `mouse rotate\|tilt\|stretch\|none` | cursor animation (hypr-dynamic-cursors) |
| `CTRL+SUPER+N` | sleep mode: screens off, idle apps frozen, music keeps playing |

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
| `SUPER+V` | clipboard history |
| `SUPER+.` | emoji picker |
| `SUPER+N` | do not disturb |
| `SUPER+L` | lock |
| `SUPER+R` | pin / unpin window |
| `Power` | power-off wave (tap again to cancel) |

The full list lives in `~/.config/hypr/config/binds-serpantinum.lua` and `hyprland.lua`.

## Notes

- Hyprland is configured in **Lua** (`~/.config/hypr/hyprland.lua` + `config/*.lua`). Classic
  `hyprctl keyword` doesn't apply here; use `hyprctl repl` and `hl.dsp.*` dispatchers.
- Workspaces use the [infinite-desktop-v2](https://github.com/lipeazul/infinite-desktop-v2) plugin
  and are addressed per monitor (`m~N`).
- Some files override Serpantinum's own sources under `~/.local/share/serpantinum/src`. A
  `serpantinum update` can overwrite them: run `./install.sh` again to restore them.
- No API keys or accounts are needed. Lyrics come from the public lrclib.net API through `sptlrx`.

## Credits

- [Serpantinum](https://github.com/ilyamiro/serpantinum) by ilyamiro, the main shell (AGPL-3.0)
- [Caelestia](https://github.com/caelestia-dots/shell), the fallback shell, clipboard and emoji picker
- [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics) by Spikerko, the base of Glass Lyrics (AGPL-3.0)
- cava shaders by rezky_nightky and the cava project; Material You SDDM theme by Darkkal44 (MIT)
- [hypr-dynamic-cursors](https://github.com/virtcode/hypr-dynamic-cursors), [infinite-desktop-v2](https://github.com/lipeazul/infinite-desktop-v2), [sptlrx](https://github.com/raitonoberu/sptlrx), [lavat](https://github.com/AngelJumbo/lavat)

## License

[AGPL-3.0](LICENSE), the same license as Serpantinum, whose source files Astrax modifies. Bundled
third-party pieces keep their own licenses.
