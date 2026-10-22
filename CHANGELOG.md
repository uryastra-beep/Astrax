# Changelog

## 1.11.0

- **Dynamic Island (`astrax-island`).** A black pill at the top of the screen that shows
  notifications, volume / microphone / brightness, Caps and Num Lock, airplane mode, charging and
  low battery, Bluetooth, USB and music (compact or expanded). It replaces Serpantinum's
  notification popups and OSD. Clicking a notification runs its default action (screenshot and
  recording notifications open the folder), right-click dismisses it, and action buttons show under
  the text.
- **Liquid Glass (optional, off by default)**: blur behind the pill plus a refraction shader on the
  edge; one screen capture, taken only while glass is on.
- **Settings in `SUPER+C` > Dynamic Island**: a switch per kind of notice, X/Y sliders, screen
  selector, glass / opacity / refraction, bounce, margin, duration, follow monitor, hide when idle.
- New Serpantinum overrides: `GuidePopup.qml` (registers the tab), `GuideSidebar.qml` (falls back
  to the tab name when there is no translation), `OsdController.qml` (does nothing when the island
  replaces the OSD), `IslandTab.qml` (new); `NotificationManager.qml` and `NotificationPopups.qml`
  send events to the island. `patches/serpantinum-*-island.patch` re-apply them against the pinned
  Serpantinum 2.2.12.
- Not tested live yet: real Bluetooth and USB events, plugging the charger, the bubble effect, the
  expanded music view, and bringing the app to the front for a notification without actions.

**Current Serpantinum version: 2.2.12.**

## 1.10.0

- **Liner support (optional, unofficial, not affiliated with Liner).** `liner-bridge` opens
  [Liner](https://tryliner.fun) with a private DevTools pipe (no network port), injects one reporter
  script (kept only in memory) and detaches. The reporter sends the real audio position and the
  lyrics Liner already downloaded to `127.0.0.1:8778`, and `liner-bridge` writes them where the bar
  lyrics module reads them. Liner's syllable timing is shown syllable by syllable ("Cu", "Cuan",
  "Cuando"). Nothing of Liner is modified or redistributed. See `docs/liner.md`.
- **Background vocals (adlibs) word by word.** The lines shown under the main lyric build up as they are sung ("and", "and i", "and i wanna"...), and syllable by syllable with Liner. Only when the adlib has per-word timing; without it, it shows whole, never estimated.
- **MPRIS mirror "Liner"** (`org.mpris.MediaPlayer2.astrax_liner`): Chromium sometimes drops
  Liner's title, artist or cover from MPRIS. The mirror always has them and forwards play, pause,
  next, previous and seek to Chromium's own player.
- **Lyrics.qml / LyricsFace.qml**: each bridge is read only for its own player (a song that played
  earlier on Spotify no longer wins over Liner's data); background vocals are built word by word
  and only when they have per-word timing; syllable boundaries drive the redraw timing.
- **Star ratings and best lyrics**: click the bar lyrics module to rate the sync 1-5 (a small star
  shows for a minute after a song ends). `astrax-lyrics-rating` keeps the ratings in
  `~/.config/astrax/lyrics-ratings.json` and the best lyrics in `~/.local/share/astrax/best-lyrics/`.
  Lyrics with 4-5 stars are used on any player. The best lyrics keep the highest score any player
  gave them, only lyrics with more stars replace them, and the same song is recognised even if the
  artist is spelled differently or the duration differs by up to 3 s.
- **Installer**: new optional "Liner" step (off with `--non-interactive`, `ASTRAX_LINER=1` turns it
  on); `scripts/liner/install-liner.sh` installs `playerctl python-dbus python-gobject fuse2`,
  downloads Liner's official AppImage (sha512 checked) and creates a menu entry that starts it
  through `liner-bridge`. `liner-bridge` and `astrax-lyrics-rating` are linked into `~/.local/bin`.
- `astrax-help` and `astrax-doctor` know the new commands; `patches/serpantinum-Lyrics.qml-eligible.patch`
  is regenerated against the pinned Serpantinum 2.2.12.
- Tests: `tests/test-liner.sh` (ratings in an isolated HOME; the mirror on a private session bus
  with a fake Chromium in another process), added to CI.
- The mirror always reports `CanGoNext/CanGoPrevious/CanPlay/CanPause/CanSeek` as true: Quickshell reads them once, so announcing "can't" while Stopped left the music widget's buttons dead.
- Tested with Liner 0.1.35. Newer Liner versions (0.1.40 exists) may need adjustments. The installer always downloads the latest from `latest-linux.yml`.
- Known limits: Liner updates itself, and if it changes where it stores lyrics the bridge stops
  reading them without a warning; while a DevTools session is attached Chromium does not publish
  the title to MPRIS, so the bridge attaches only to inject and lets go.

**Current Serpantinum version: 2.2.12.**

## 1.9.0

Quality-of-life tools; none of them touches Serpantinum's code or the shaders.

- **`astrax-doctor`**: one read-only command that checks the install and prints a `fix:` line for
  everything that is off: Astrax and Serpantinum versions against the pinned one, Serpantinum
  overrides that drifted from the repo, whether `p1`/`p2` are connected outputs, the cursor plugin
  against the installed Hyprland headers, the commands in `PATH`, Glass Lyrics in Spicetify and
  whether any backup exists. `-q` prints only warnings and failures; it exits 1 on a failure.
- **`astrax-monitors`**: lists the connected outputs and sets `MONITOR1`/`MONITOR2` (p1/p2) in
  `variables.lua` for you, so a new install no longer needs hand-editing. Interactive, or
  `astrax-monitors eDP-1 HDMI-A-1`. Keeps `variables.lua.bak`.
- **`astrax-help`**: every Astrax command with a one-line description, grouped; `astrax-help cursor`
  filters.
- **`astrax-safe on|off|status`**: safe mode in one command. Patched cursor plugin off at the next
  login, `cursor-style normal`, `opti on`; `off` restores exactly what `on` changed (including a
  `disabled` marker that was already there). It only writes files, so it works from a TTY
  (Ctrl+Alt+F3) when Hyprland or Quickshell are broken. It asks first; `-y` skips the question and
  is required without a terminal. `astrax-doctor` flags it when it is on.
- **`astrax-hypr-guard`**: at login, tells you once per Hyprland version when an update left the
  patched cursor plugin out of date. It changes nothing: `plugins.lua` already refuses to load a
  plugin built against other headers, so the stock plugin runs instead of risking the compositor.
  Rebuilding stays manual (`cursor-plugin build`).
- **`astrax-tour`**: five welcome notifications (SUPER, SUPER+I, SUPER+C, `astrax-help`,
  `astrax-doctor`) shown once after install; `astrax-tour --force` shows them again.
- **`astrax-update changelog`** prints what changed since your version; **`astrax-update rollback`**
  runs `astrax-restore` (any extra arguments are passed on).
- **Lyrics blocklist**: put one regular expression per line in `~/.config/astrax/lyrics-blocklist.txt`
  (`#` starts a comment, case-insensitive) to stop lyrics for a player, URL, title or artist; it is
  reloaded when the file changes. `patches/serpantinum-Lyrics.qml-eligible.patch` carries it.
- `tests/check-binds.py` (in CI) fails when a letter/punctuation keybind in the Lua files is missing
  from `binds.json` (SUPER+I) or the other way round.
- README: new "Commands" and "Health check" sections; the Monitors section points at `astrax-monitors`.
- New CI test `tests/test-tools.sh`.
- **Not in this release** (need a live session or can crash the compositor, so they were left out on
  purpose): configurable cursor colors and per-app cursor profiles (C++ plugin), a lyrics-offset hotkey
  and "retry lyrics" outside the Spotify window (Glass Lyrics bundle), and Rollback/Changelog buttons in
  the About page (QML). The CLI equivalents above exist.

## 1.8.1

- **No more invented lyrics for non-songs**: the lyrics lookup (`Lyrics.qml`) now has a `lyricsEligible` check.
  It skips Spotify's DJ narration (a track id that isn't `/track/`, or an artist/title starting with "DJ")
  and browsers playing TikTok, Instagram, Facebook, Twitter/X, Snapchat or Reddit, which used to match an
  unrelated song in another language. `patches/serpantinum-Lyrics.qml-eligible.patch` re-applies it on
  Serpantinum's own file after a Serpantinum update (or run `./install.sh` again).
- **Glass Lyrics: instrumental mode**. If the song title contains "instrumental", "inst.", "karaoke" or
  "backing track", the lyrics fetch is skipped and a "♪ Instrumental" notice is shown (no Discord
  link; hidden in fullscreen like "lyrics not found"), instead of a skeleton and a pointless 404.
- **Glass Lyrics: better word-by-word sync**.
  - A drift auditor checks the lyric clock against the player every 2 seconds and gently corrects
    only a *change* in the gap (stalled source, output-latency shifts, crossfades), so a calibrated
    lead is never fought. Jumps above 400 ms (seeks, track changes) are left to the normal snap.
  - Each word now lights up 50 ms early (it was 0) to match how it is perceived.
  - Per-device audio latency: Bluetooth sits 150-250 ms behind wired audio, so the lead is
    remembered per output device. Nudge it with `,` (earlier) or `.` (later) while lyrics are open
    (10 ms steps, from -200 to 600 ms, default 100 ms); a notification shows the value.
  - `spicetify/glass-lyrics/glass-lyrics.js` is rebuilt and `glass-lyrics.patch` regenerated (still
    on Spicy Lyrics `fcc5f83`). Re-run `spicetify/glass-lyrics/install.sh` to update it.

## 1.8.0

- **Astrax version and updates in Serpantinum's menu**: `SUPER+C` > About shows `Astrax v1.8.0` under
  Serpantinum's version. When a newer GitHub release exists, a card shows **Changelog** and **Update**
  (the same buttons as Serpantinum's update). `Update` opens a terminal, fetches the release tag and
  runs its `./install.sh` (which backs up what it overwrites first).
- **Update notification**: a desktop notification arrives once per new Astrax version (click it to open
  the About page). The check runs a minute after login and every 6 hours.
- New `astrax-update` command (`version`, `check`, `status`, `run`); `install.sh` now records the
  installed version in `~/.local/state/astrax/version`.
- Docs: new README sections explaining that, to update Serpantinum with Astrax installed, you can
  either wait for an Astrax release that ships it, or update it manually with `srp-update` at your own
  risk of breaking or corrupting your setup.
- Patch `patches/serpantinum-AboutTab.qml-astrax.patch` for the About page (re-apply it after a
  Serpantinum update, or run `./install.sh` again). New CI test `tests/test-update.sh`.

## 1.7.0

- **Reactive cursor**: a patched hypr-dynamic-cursors (`plugins/dynamic-cursors`, BSD-3-Clause) draws
  a colored glow around the arrow depending on the cursor type: blue = clickable, white = text, light
  blue = draggable, orange = crosshair, pink = resize, green = copy, red = error / not allowed, half
  blue and half white = alias, every color spinning = loading, purple = anything else.
  - Animations: a continuous light trail, shrink on click, scroll stretch (arrow and light) with a
    spring back, a 320 ms color fade, stretch by speed and rotation with movement.
  - Three styles picked live in Serpantinum's menu (`SUPER+C` > General > Cursor style): Normal
    (classic white, no glow or animations), Astrax and High contrast (an Okabe-Ito based palette),
    with a legend and a switch per animation. Also `cursor-style` from a terminal.
  - Cursor lock: apps can't set their own cursor image, except a hidden cursor and the window
    classes in `~/.config/cursor-allow.txt`.
  - Safety net in `plugins.lua`: the patched plugin only loads at login and only if it was built
    against the installed Hyprland headers; if it crashes in the first 25 s, the next login uses the
    stock plugin. `cursor-plugin check|build` after Hyprland updates. Never hot-reload it.
  - Color is the only cue between cursor types; configurable colors or distinct shapes are future work.
  - New arrow-only cursor theme `Bibata-ArrowBare` (derived from Bibata, GPL-3.0),
    `docs/cursor-test.html` to try every cursor, and `patches/serpantinum-GeneralTab.qml-cursor-style.patch`
    for the menu row (re-apply it after a Serpantinum update, or run `./install.sh` again).
  - The old unofficial trail build (`build-trail.sh`, `mouse trail on|off`, which hot-loaded the
    plugin) is gone: the reactive cursor replaces it.
- **WORT**: the bubbles swell with the bass and the colors brighten with any loud sound (its own small
  cava, `cava.conf`), softer when the palette is mostly white. A focused terminal no longer counts as
  an app: the lava keeps the idle purple palette.
- **Special song modes**: pausing the music turns the special theme off (and the same song is
  re-checked when it resumes), and a mode left on by a restored state file is now cleared too.
- CI checks the reactive cursor after a clean install (built against the installed headers, theme,
  menu row).

## 1.6.1

**Faster song change detection.** The border, the widgets and the lava wallpaper now switch to the
new song's colors in **~2s instead of ~10s**.

- **Quicker confirmation:** a track change is confirmed after 0.12s (was 0.35s), and the burst of
  player events is grouped for 0.05s (was 0.15s).
- **Faster cover download:** the album art is fetched with `curl -4` (~0.3s). `urllib` tried IPv6
  first and took ~5.5s on networks without IPv6; it stays as the fallback.
- **Colors first:** the lyrics lookup (a network request) now runs after the colors are applied, so
  it no longer delays them.
- **Lava wallpaper:** checks for changes every 0.25s (was 1s), waits 0.03s before reading the cover
  (was 0.15s), and fades to the new colors in 0.8s (was 2s).
- `border_colors.py` log lines now start with the time (`HH:MM:SS`), to measure how fast a change
  lands.

## 1.6.0

**Current Serpantinum version: 2.2.12.**

- The installer now pins **Serpantinum 2.2.12** (commit `c72992d`) instead of 2.2.10. Every
  Serpantinum file Astrax overrides was carried over to 2.2.12 with Astrax's changes kept: lock
  screen and `lock.sh`, theme backend, wallpaper engine (with the safe-arguments fix from 1.0.1),
  `Wallpaper.qml` (WORT hooks), lyrics, bar, power actions, widget registry/loader/editor and the
  translations.
- Serpantinum 2.2.12 draws its visualizers (bar cava, the round music widget) with a shared
  single-color `Visualizer`. Astrax now adds the special song mode gradient there, so the bar cava
  and the ring around the music disc take the mode's colors again (left to right, or bottom to top
  on screen for the ring). Its new continuous/wave style works too.
- The round music widget keeps Astrax's cover crossfade on top of Serpantinum 2.2.12's version.
- The bar lyrics module picks its horizontal or vertical face again (`BarModule.qml` passes the
  bar orientation).
- Already on an older Serpantinum? Update with `srp-update`, then run `./install.sh` again to copy
  Astrax's 2.2.12 files, and re-apply `patches/serpantinum-Wallpaper.qml-wort.patch` only if you
  skip the installer. Undo with `astrax-restore`.

## 1.5.0

- **WORT — Wallpaper On Real Time**: a live "lava lamp" wallpaper (Quickshell shader) with up to 7
  colored bubbles. Colors come from the music (the visualizer's palette, or the album art), from the
  focused app's icon when nothing plays, or an idle purple palette; TV Girl mode adds two black
  bubbles. Serpantinum's theme follows the lava colors (except in special song modes). Turn it on by
  picking `lava-live.mp4` in `SUPER+W` > Videos, or with `lava-wallpaper on|off|toggle|status`.
- Serpantinum's `Wallpaper.qml` gets the WORT hooks (start/stop the lava, pause the placeholder
  video, restart it on boot). Since a Serpantinum update overwrites it,
  `patches/serpantinum-Wallpaper.qml-wort.patch` re-applies them.
- CI checks the lava files, the placeholder video and the hooks after a clean install.

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
