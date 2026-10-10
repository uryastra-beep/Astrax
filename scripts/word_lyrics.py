#!/usr/bin/env python3
"""Shows Spotify's synced lyrics WORD BY WORD, big
(toilet -f bigmono12), like clock-rs but with the current lyric instead of the
time. Real-time timing via direct D-Bus (MPRIS Position, ~0.5ms per
query -- going through `caelestia shell` every time took ~280ms, too slow for
this). The synced lyrics (timestamps per LINE) come from lrclib.net; each
line's time is split evenly among its words, since there are no
per-word timestamps in the public sources."""

import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import dbus

LRCLIB_API = "https://lrclib.net/api/get"
COLORS_FILE = "/tmp/widget-colors.json"
# Manual sync tweak: lrclib lyrics are community-made and can come
# early/late relative to the real audio (even more so for live
# versions). Positive = delays the lyrics (shows them later); negative =
# advances them. Can be overridden with the WORD_LYRICS_OFFSET env var.
SYNC_OFFSET_SECONDS = float(os.environ.get("WORD_LYRICS_OFFSET", "0.4"))
TOILET_FONT = "bigmono12"
POLL_SECONDS = 0.08
METADATA_RECHECK_SECONDS = 1.0
LAST_LINE_TAIL_SECONDS = 5.0

BUS_NAME = "org.mpris.MediaPlayer2.spotify"
OBJ_PATH = "/org/mpris/MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"


def get_primary_color():
    try:
        with open(COLORS_FILE) as f:
            return json.load(f).get("primary", "cfbfeb")
    except Exception:
        return "cfbfeb"


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def render_word(word, rgb):
    if not word:
        os.system("clear")
        return
    try:
        out = subprocess.run(["toilet", "-f", TOILET_FONT, "-t", word],
                              capture_output=True, text=True, timeout=2).stdout
    except Exception:
        out = word
    r, g, b = rgb
    os.system("clear")
    print(f"\033[38;2;{r};{g};{b}m{out}\033[0m", end="")


def player_proxy(bus):
    obj = bus.get_object(BUS_NAME, OBJ_PATH)
    return dbus.Interface(obj, "org.freedesktop.DBus.Properties")


def get_position_seconds(props):
    return float(props.Get(PLAYER_IFACE, "Position")) / 1e6


def get_metadata(props):
    return props.Get(PLAYER_IFACE, "Metadata")


def get_playback_status(props):
    return str(props.Get(PLAYER_IFACE, "PlaybackStatus"))


def fetch_synced_lyrics(title, artist, album, duration):
    try:
        params = urllib.parse.urlencode({
            "track_name": title,
            "artist_name": artist,
            "album_name": album or "",
            "duration": int(round(duration)) if duration else 0,
        })
        req = urllib.request.Request(f"{LRCLIB_API}?{params}",
                                      headers={"User-Agent": "astrax-word-lyrics"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
        return data.get("syncedLyrics")
    except Exception:
        return None


LRC_LINE_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\](.*)")


def parse_lrc(synced_lyrics):
    """-> [(start_seconds, text), ...] sorted by time."""
    lines = []
    for raw in synced_lyrics.splitlines():
        m = LRC_LINE_RE.match(raw)
        if not m:
            continue
        minutes, seconds, text = m.groups()
        t = int(minutes) * 60 + float(seconds)
        lines.append((t, text.strip()))
    lines.sort(key=lambda x: x[0])
    return lines


def build_word_timeline(lines):
    """-> [(start, end, word), ...] splitting each line's time among
    its words (lrclib has no per-word timestamps, only per line)."""
    timeline = []
    for i, (start, text) in enumerate(lines):
        end = lines[i + 1][0] if i + 1 < len(lines) else start + LAST_LINE_TAIL_SECONDS
        words = text.split()
        if not words:
            continue
        span = max(end - start, 0.05)
        step = span / len(words)
        for j, w in enumerate(words):
            timeline.append((start + j * step, start + (j + 1) * step, w))
    return timeline


def word_at(timeline, position):
    for start, end, word in timeline:
        if start <= position < end:
            return word
    return ""


def track_key(metadata):
    return str(metadata.get("mpris:trackid", ""))


def load_track(props):
    metadata = get_metadata(props)
    title = str(metadata.get("xesam:title", ""))
    artists = metadata.get("xesam:artist", [])
    artist = str(artists[0]) if artists else ""
    album = str(metadata.get("xesam:album", ""))
    length_us = metadata.get("mpris:length", 0)
    duration = float(length_us) / 1e6 if length_us else None
    return title, artist, album, duration, track_key(metadata)


def main():
    rgb = hex_to_rgb(get_primary_color())
    bus = dbus.SessionBus()

    timeline = []
    current_key = None
    last_word = None
    last_metadata_check = 0.0

    while True:
        try:
            props = player_proxy(bus)
            status = get_playback_status(props)

            now = time.time()
            if now - last_metadata_check >= METADATA_RECHECK_SECONDS:
                last_metadata_check = now
                title, artist, album, duration, key = load_track(props)
                if key != current_key:
                    current_key = key
                    rgb = hex_to_rgb(get_primary_color())
                    synced = fetch_synced_lyrics(title, artist, album, duration) if title else None
                    timeline = build_word_timeline(parse_lrc(synced)) if synced else []
                    last_word = None

            if status != "Playing" or not timeline:
                time.sleep(POLL_SECONDS)
                continue

            position = get_position_seconds(props) - SYNC_OFFSET_SECONDS
            word = word_at(timeline, position)
            if word != last_word:
                render_word(word, rgb)
                last_word = word

        except dbus.exceptions.DBusException:
            # no spotify running (or it hasn't shown up on the bus yet)
            if last_word is not None:
                render_word("", rgb)
                last_word = None
            timeline = []
            current_key = None
        except Exception as e:
            print(f"error: {e}", file=sys.stderr, flush=True)

        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
