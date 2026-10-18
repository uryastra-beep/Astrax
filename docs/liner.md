# Liner support (optional, unofficial)

[Liner](https://tryliner.fun) is a desktop music app that downloads word- and syllable-synced
lyrics. It does not share them with other apps. `liner-bridge` lets Astrax's bar lyrics module use
the ones Liner already has.

**Not affiliated with Liner.** Astrax does not modify or redistribute Liner. The installer downloads
Liner's official AppImage from Liner's own GitHub releases and checks its sha512. The bridge only
reads lyrics that Liner's own client already downloaded; the script it injects lives only in the
page's memory and is gone when Liner closes. Read Liner's license for what you may do with its app.

## Install

```bash
bash scripts/liner/install-liner.sh      # also offered by ./install.sh (off by default)
```

It installs `playerctl python-dbus python-gobject fuse2` (sudo), puts `Liner-<version>.AppImage` in
`~/Applications` and creates a menu entry that starts Liner through `liner-bridge`.
`liner-bridge` uses the newest `~/Applications/Liner-*.AppImage`, or `$LINER_APPIMAGE`.

**Open Liner through `liner-bridge`** (the menu entry, or run the command). If Liner was already open
without it, the bridge tells you; close Liner and start it again.

**Tested with Liner 0.1.35.** The installer downloads the latest release, and newer versions may change where Liner stores lyrics and need adjustments.

## How it works

1. `liner-bridge` starts Liner with `--remote-debugging-pipe` (a private pipe, no network port),
   sends one script (`page.bundle.js`) and disconnects. While a DevTools session stays attached,
   Chromium does not publish the song title to MPRIS, which is why it lets go right away.
2. The script runs inside the page. It reports the real audio position, title, artist, cover and
   the lyrics Liner cached (the source Liner shows; the syllable version only when its timing
   matches) to `127.0.0.1:8778`. That port listens on localhost only.
3. `liner-bridge` writes `~/.cache/liner-bridge/current.json` and `progress.json` in the same
   format as the Spotify bridge (`key` is `Artist - Title` as MPRIS shows it, `player: "liner"`).
   Words with syllable timing carry `syl: [{time, endTime, text}]`; background vocals are in `bg`.
4. `mirror.py` registers an MPRIS player named `Liner` (`org.mpris.MediaPlayer2.astrax_liner`).
   Chromium sometimes loses Liner's title, artist or cover on MPRIS; the mirror always has them
   from the page. Play, pause, next, previous and seek are forwarded to Chromium's own player.
   Its name sorts before `chromium.*`, so Serpantinum prefers it.
5. `Lyrics.qml` and `LyricsFace.qml` (Astrax overrides) read each bridge only for its own player.

## Star ratings

Click the lyrics module in the bar to rate how well the lyrics synced, 1-5 stars (a small star
appears for a minute after a song ends). `astrax-lyrics-rating` stores:

- `~/.config/astrax/lyrics-ratings.json`: every rating, per song and player
- `~/.local/share/astrax/best-lyrics/<id>.json`: the best lyrics of each song

Lyrics with 4-5 stars are used for that song on any player. The best lyrics keep the highest
score any player gave them (a 3-star from another player does not lower them), only lyrics with
more stars replace them, and the same song is matched even when the artist is spelled differently
(`unh0ly` / `saraunh0ly`) or the duration differs by up to 3 s.

## Files

| File | What |
|---|---|
| `scripts/liner/liner-bridge` | launcher + local receiver, linked as `liner-bridge` |
| `scripts/liner/mirror.py` | the MPRIS mirror |
| `scripts/liner/page.bundle.js` | the injected script (built, minified) |
| `scripts/liner/src/page.js` | its source |
| `scripts/liner/install-liner.sh` | optional Liner setup |
| `scripts/astrax-lyrics-rating` | ratings and best lyrics |

## Rebuild `page.bundle.js`

It bundles `src/page.js` with `@braccato/parsers@0.2.1` (MIT, see `THIRD_PARTY_NOTICES.md`):

```bash
mkdir build && cd build && cp ../scripts/liner/src/page.js . && bun add @braccato/parsers@0.2.1
bun build page.js --format=iife --minify --target=browser --outfile=../scripts/liner/page.bundle.js
```

## Troubleshooting and limits

- **No lyrics from Liner**: check `liner-bridge` printed no warning, that Liner was started by it,
  and look at `~/.cache/liner-bridge/`. `LINER_BRIDGE_DEBUG=1 liner-bridge` logs more.
- **Liner updates itself.** If it changes where it stores lyrics (localStorage
  `liner_lyrics_session_v1`, `liner_lyrics_v2_item_<id>`, IndexedDB `liner_db_v1`) the bridge
  stops finding them without an error. Update `src/page.js` and rebuild.
- The mirror's controls are tested against a fake Chromium, not extensively against the real one.
  `LINER_BRIDGE_POKE=1` turns on an experiment that re-publishes metadata; it did not help and is off.
- Port 8778 is used by the bridge (the Spotify bridge uses 8777).
