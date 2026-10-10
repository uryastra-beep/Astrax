# Glass Lyrics

A small fork of [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics) by Spikerko for
[Spicetify](https://spicetify.app). Fetching, parsing, rendering and animating the lyrics is all
Spicy Lyrics. The fork only adds a visual layer on top:

- **Glass lyrics**: glass outline, translucent unsung words and a glow on sung ones.
- **Crossfade cover transition**: when Spotify crossfades or automixes into the next song, the next
  cover rises from behind the current one and swaps in. Press `M` during a song to teach it where the
  mix starts in that playlist.

Everything is configurable under **Glass Lyrics** in the lyrics settings panel.

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
