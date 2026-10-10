# Changelog

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
