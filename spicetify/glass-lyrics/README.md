# Glass Lyrics

A small fork of [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics) by Spikerko for
[Spicetify](https://spicetify.app). Fetching, parsing, rendering and animating the lyrics is all
Spicy Lyrics. The fork only adds a visual layer on top:

- **Glass lyrics**: glass outline, translucent unsung words and a glow on sung ones.
- **Crossfade cover transition**: when Spotify crossfades or automixes into the next song, the next
  cover rises from behind the current one and swaps in. Press `M` during a song to teach it where the
  mix starts in that playlist.

- **Word sync**: a drift auditor (checks the lyric clock every 2 s), a 50 ms lead per word and a
  per-output-device audio latency. While lyrics are open, press `,` (earlier) or `.` (later) to
  nudge the lead for the current output device (10 ms steps); it is remembered per device.
- **Instrumental mode**: titles containing "instrumental", "inst.", "karaoke" or "backing track"
  skip the lyrics fetch and show "♪ Instrumental".

Everything else is configurable under **Glass Lyrics** in the lyrics settings panel.

## Install

Needs Spotify with [Spicetify](https://spicetify.app/docs/getting-started) already set up.

```bash
./install.sh
```

The script copies `glass-lyrics.js` into your Spicetify `Extensions` folder, disables Spicy Lyrics
and runs `spicetify apply`. If Spicy Lyrics came from the Marketplace, uninstall it there as well.

## Source

Glass Lyrics is licensed under the AGPL-3.0, like Spicy Lyrics (see `LICENSE`). The full source of
this build is Spicy Lyrics at commit `fcc5f836232e2f5e1690d744f9c1400ea6201f0d` plus
`glass-lyrics.patch`:

```bash
git clone https://github.com/Spikerko/spicy-lyrics.git
cd spicy-lyrics
git checkout fcc5f836232e2f5e1690d744f9c1400ea6201f0d
git apply /path/to/glass-lyrics.patch
bun install
bun run build   # writes dist/glass-lyrics.js
```
