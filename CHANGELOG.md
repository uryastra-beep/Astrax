# Changelog

## 1.4.0

**Tests.** GitHub Actions now runs three levels on every push (see `tests/`):

1. static checks: shell, Python, Lua and JSON syntax, `shellcheck`, that every script and
   Quickshell config the binds call exists, and no personal data in the repo;
2. `srp-update` / `astrax-restore` against a fake home and a fake Serpantinum (28 checks);
3. a full install on a **clean Arch container**, then checks that Serpantinum is on the pinned
   commit with telemetry off, every dotfile and command is in place, and that a second run works
   and backs up first.

The clean install found three installer bugs, all fixed here. **Installing on plain Arch
(not CachyOS) failed before this release:**

- `zsh-theme-powerlevel10k` only exists in CachyOS/chaotic repos: the installer now takes the AUR
  package on plain Arch, and `.zshrc` loads the theme itself when CachyOS's zsh config isn't there.
- `caelestia-shell` (AUR) depends on `quickshell-git`, which conflicted with the official
  `quickshell` installed first. The installer now lets it pull `quickshell-git` and swaps back to
  the official package Serpantinum needs, like Serpantinum's own installer does.
- New `./install.sh --non-interactive`: safe defaults instead of questions, Serpantinum's
  telemetry off. Serpantinum's final "reboot now?" prompt no longer fails it without a terminal.

## 1.3.0

**Current Serpantinum version: 2.2.10.**

- The installer now pins **Serpantinum 2.2.10** (commit `e2a91af`) instead of `1eec762` (between
  2.2.6 and 2.2.7). Every Serpantinum file Astrax overrides was updated to 2.2.10 with Astrax's
  changes kept: the lock screen, theme backend, cava, widget registry and editor, bar module
  registry, lyrics view, `Main.qml` and the translations.
- The power-off wave moved to `SystemPanelPowerActions.qml`, where Serpantinum 2.2.9+ keeps the
  power buttons. That file also fixes the panel-closed check (upstream points it at an id that
  doesn't exist).
- README shows the current Serpantinum version at the top. The version line was also stuck at 1.0.1.
- Already on an older Serpantinum? Update with `srp-update` (it backs everything up first), then
  run `./install.sh` again to copy Astrax's 2.2.10 files. Undo with `astrax-restore`.

## 1.2.0

> ⚠️ **Updating Serpantinum can break Astrax and you can lose your setup.** Astrax is pinned to one
> Serpantinum commit and replaces some of Serpantinum's source files; a Serpantinum update wipes
> them. Update only with `srp-update`, and undo it with `astrax-restore`.

- **`srp-update`**: asks first, backs up everything a Serpantinum update can touch (Serpantinum's
  files, settings and state, `~/.config/hypr`, `~/.config/quickshell`, `~/scripts`, `~/.local/bin`)
  to `~/astrax-backups/`, checks the backup can be read, then updates Serpantinum to its latest
  version.
- **`astrax-restore`**: puts everything back from the latest backup (or `astrax-restore <file>`;
  `--list` shows them) and returns Serpantinum to the commit it was on.
- README: a warning about updating Serpantinum under Install, plus `SUPER+I` in the keybinds table.

## 1.1.0

- **Bind search** (`SUPER+I`): a centered search menu for every keybind, styled like the
  Astrax launcher (same card, selection bubble and animations, live Serpantinum theme colors).
  Type to filter by key, description or group; a corner selector switches between Serpantinum
  (default), Caelestia and All (`Tab`/`Shift+Tab` or click). The panel shrinks to fit the results
  and scrolls past its max height. Binds live in `~/.config/quickshell/astrax-binds/binds.json`.

## 1.0.1

Fixes from a code review of 1.0.0.

- **Security:** wallpaper file names were pasted into `bash -c` scripts, so a crafted name
  could run commands. They are now passed as arguments.
- **Lock screens:** passwords may contain spaces (Serpantinum lock and the SDDM theme). The space
  that only wakes the lock screen is still not typed.
- **Sleep mode** (`CTRL+SUPER+N`) aborts if the lock screen doesn't engage, instead of freezing apps
  with the session open, and wakes up as soon as any screen turns back on.
- **Lyrics:** the bar lyrics module and the Simple Lyrics widget now ship everything they
  need (the `Lyrics` singleton, `LyricsView`, the bar module registry). Serpantinum is pinned to
  the commit these overrides were tested against (`1eec762`), and overrides that matched upstream
  were dropped.
- **Installer:** the backup is taken before anything is installed and includes existing
  `~/.local/bin` commands. It also asks for a keyboard layout, reports Hyprland plugin failures,
  installs every default app the binds use, and no longer links a `taskbar` command for a
  taskbar it doesn't ship.
- **Monitors:** auto-detected by default, configured in one place (`monitors.lua`). `hz` caps
  come from each screen's own modes or a per-panel limits file, not from the port name.
- **`vm`** records the active shell, reloads the binds for it and rolls back if the new shell fails;
  sleep mode, `mode gaming`, `workspace` and the color daemon follow the active shell.
- **Power button:** a session logind inhibitor keeps logind from powering off behind the wave
  animation; the Caelestia session gets the same bind.
- Clipboard history watcher starts reliably (its `pgrep` guard matched itself).
- Window navigation/moving uses logical monitor sizes (scaled and rotated screens).
- `mode`: skips and reports apps that aren't installed; never closes your apps when the
  replacement can't start.
- Widget pidfiles live in the session runtime dir and are checked against the real process
  before being trusted or killed.
- Brave watcher is opt-in, ignores failed Hyprland queries and never kills an active download.
- Smaller fixes: kitty color reload, `sync-theme.sh` on a fresh system, `word_lyrics.py`
  retries, the obsolete `infinite-desktop.sh` wrapper removed, `mouse trail` build script
  included, leftover Spanish strings translated.

## 1.0.0

First public release.
