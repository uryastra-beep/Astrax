"""MPRIS mirror of Liner, fed by the reporter that runs inside Liner's page.

Chromium sometimes publishes Liner's song to MPRIS without its title/artist (and drops
the cover now and then), even though the page has them. This registers a second MPRIS
player, "Liner" (org.mpris.MediaPlayer2.astrax_liner), that always has the data the page
has: title, artist, album, cover, duration, the real <audio> position and play state.
Its name sorts before "chromium.*", so Serpantinum prefers it. Play, pause, next,
previous and seek are passed on to Chromium's own MPRIS player, whose controls keep
working even when its metadata is missing.
"""
import hashlib
import os
import re
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "org.mpris.MediaPlayer2.astrax_liner"
OBJ = "/org/mpris/MediaPlayer2"
ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"
STALE_AFTER = 12   # s without news from the page -> Stopped (page gone or frozen)


def find_chromium(bus):
    """Bus name of the Chromium MPRIS player whose process is Liner."""
    try:
        names = [str(n) for n in bus.list_names() if str(n).startswith(ROOT + ".chromium.instance")]
        dbus_obj = bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus")
        for n in names:
            pid = int(dbus_obj.GetConnectionUnixProcessID(n, dbus_interface="org.freedesktop.DBus"))
            try:
                exe = os.readlink("/proc/%d/exe" % pid)
            except OSError:
                continue
            if re.search(r"(\.mount_Liner[^/]*|/opt/Liner)/liner$", exe):
                return n
    except Exception:
        pass
    return None


class Mirror(dbus.service.Object):
    def __init__(self, log=print):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SessionBus()
        self.log = log
        name = dbus.service.BusName(BUS_NAME, self.bus, do_not_queue=True)
        super().__init__(name, OBJ)
        self.title = self.artist = self.album = self.art = ""
        self.length_us = 0
        self.status = "Stopped"
        self.pos0 = 0.0          # position at pos_stamp (s)
        self.pos_stamp = time.time()
        self.rate = 1.0
        self.last_news = 0.0
        self.trackid = "/org/astrax/liner/none"
        GLib.timeout_add_seconds(3, self._check_stale)

    # ---- state, always called on the GLib main loop (use GLib.idle_add from threads) ----
    def position_s(self):
        if self.status == "Playing":
            return max(0.0, self.pos0 + (time.time() - self.pos_stamp) * self.rate)
        return self.pos0

    def update_state(self, st):
        """st: key, title, artist, album, art, dur, pos, paused, stamp (from the page)."""
        self.last_news = time.time()
        title = st.get("title") or ""
        changed = {}
        if title:
            status = "Paused" if st.get("paused") else "Playing"
            artist, album, art = st.get("artist") or "", st.get("album") or "", st.get("art") or ""
            length = int(float(st.get("dur") or 0) * 1e6)
            if (title, artist, album, art, length) != (self.title, self.artist, self.album, self.art, self.length_us):
                new_track = (title, artist) != (self.title, self.artist)
                self.title, self.artist, self.album, self.art, self.length_us = title, artist, album, art, length
                if new_track:
                    key = "%s - %s" % (artist.strip(), title.strip())
                    self.trackid = "/org/astrax/liner/track/" + hashlib.md5(key.encode()).hexdigest()[:16]
                changed["Metadata"] = self._metadata()
        else:
            status = "Stopped"
            if self.title:
                self.title = self.artist = self.album = self.art = ""
                self.length_us = 0
                changed["Metadata"] = self._metadata()
        if "pos" in st and st["pos"] is not None and float(st["pos"]) >= 0:
            self._set_position(float(st["pos"]), float(st.get("stamp") or time.time()), status == "Playing")
        if status != self.status:
            self.status = status
            changed["PlaybackStatus"] = self.status
        self._emit(changed)

    def update_progress(self, progress, playing, stamp, rate=1.0):
        self.last_news = time.time()
        self.rate = rate or 1.0
        changed = {}
        status = ("Playing" if playing else "Paused") if self.title else "Stopped"
        self._set_position(progress, stamp, playing)
        if status != self.status:
            self.status = status
            changed["PlaybackStatus"] = self.status
        self._emit(changed)

    def _set_position(self, pos, stamp, playing):
        expected = self.position_s()
        self.pos0, self.pos_stamp = pos, stamp
        # a jump (seek, new song) tells clients to re-read the position
        if abs(pos - expected) > 1.5 and self.title:
            try:
                self.Seeked(dbus.Int64(int(self.position_s() * 1e6)))
            except Exception:
                pass

    def _check_stale(self):
        if self.status != "Stopped" and time.time() - self.last_news > STALE_AFTER:
            self.update_state({})
        return True

    # ---- helpers ----
    def _metadata(self):
        if not self.title:
            return dbus.Dictionary({}, signature="sv")
        md = {
            "mpris:trackid": dbus.ObjectPath(self.trackid),
            "xesam:title": dbus.String(self.title),
            "xesam:artist": dbus.Array([self.artist] if self.artist else [], signature="s"),
            "xesam:album": dbus.String(self.album or "Liner"),
        }
        if self.length_us > 0:
            md["mpris:length"] = dbus.Int64(self.length_us)
        if self.art:
            md["mpris:artUrl"] = dbus.String(self.art)
        return dbus.Dictionary(md, signature="sv")

    def _player_props(self):
        # Always True: clients read these once (GetAll) and only refresh on PropertiesChanged,
        # which is not sent for them; starting as "can't" (Stopped) left the widget's
        # buttons disabled for good. The controls are passed on to Chromium anyway.
        playing_ok = True
        return {
            "PlaybackStatus": dbus.String(self.status),
            "LoopStatus": dbus.String("None"),
            "Rate": dbus.Double(1.0),
            "Shuffle": dbus.Boolean(False),
            "Metadata": self._metadata(),
            "Volume": dbus.Double(1.0),
            "Position": dbus.Int64(int(self.position_s() * 1e6)),
            "MinimumRate": dbus.Double(1.0),
            "MaximumRate": dbus.Double(1.0),
            "CanGoNext": dbus.Boolean(playing_ok),
            "CanGoPrevious": dbus.Boolean(playing_ok),
            "CanPlay": dbus.Boolean(playing_ok),
            "CanPause": dbus.Boolean(playing_ok),
            "CanSeek": dbus.Boolean(playing_ok),
            "CanControl": dbus.Boolean(True),
        }

    def _root_props(self):
        return {
            "CanQuit": dbus.Boolean(False),
            "CanRaise": dbus.Boolean(False),
            "HasTrackList": dbus.Boolean(False),
            "Identity": dbus.String("Liner"),
            "DesktopEntry": dbus.String("liner"),
            "SupportedUriSchemes": dbus.Array([], signature="s"),
            "SupportedMimeTypes": dbus.Array([], signature="s"),
        }

    def _emit(self, changed):
        if changed:
            self.PropertiesChanged(PLAYER, dbus.Dictionary(changed, signature="sv"), dbus.Array([], signature="s"))

    def _delegate(self, method, *args):
        name = find_chromium(self.bus)
        if not name:
            return None
        try:
            obj = self.bus.get_object(name, OBJ, introspect=False)
            return getattr(dbus.Interface(obj, PLAYER), method)(*args, timeout=3)
        except Exception as e:
            self.log("delegate %s failed: %s" % (method, e))
            return None

    def _chromium_position_us(self):
        name = find_chromium(self.bus)
        if not name:
            return None
        try:
            obj = self.bus.get_object(name, OBJ, introspect=False)
            return int(dbus.Interface(obj, PROPS).Get(PLAYER, "Position", timeout=2))
        except Exception:
            return None

    # ---- org.freedesktop.DBus.Properties ----
    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        props = self._player_props() if iface == PLAYER else self._root_props() if iface == ROOT else {}
        if prop not in props:
            raise dbus.exceptions.DBusException("Unknown property " + prop, name="org.freedesktop.DBus.Error.UnknownProperty")
        return props[prop]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return dbus.Dictionary(self._player_props() if iface == PLAYER else self._root_props() if iface == ROOT else {}, signature="sv")

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, iface, prop, value):
        pass  # volume, loop and shuffle are not mirrored

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    # ---- org.mpris.MediaPlayer2 ----
    @dbus.service.method(ROOT)
    def Raise(self):
        pass

    @dbus.service.method(ROOT)
    def Quit(self):
        pass

    # ---- org.mpris.MediaPlayer2.Player: passed on to Chromium's player ----
    @dbus.service.method(PLAYER)
    def Next(self):
        self._delegate("Next")

    @dbus.service.method(PLAYER)
    def Previous(self):
        self._delegate("Previous")

    @dbus.service.method(PLAYER)
    def Pause(self):
        self._delegate("Pause")

    @dbus.service.method(PLAYER)
    def PlayPause(self):
        self._delegate("PlayPause")

    @dbus.service.method(PLAYER)
    def Stop(self):
        self._delegate("Stop")

    @dbus.service.method(PLAYER)
    def Play(self):
        self._delegate("Play")

    @dbus.service.method(PLAYER, in_signature="x")
    def Seek(self, offset):
        self._delegate("Seek", dbus.Int64(offset))

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, track_id, position):
        # Chromium's track id differs from ours: seek relative to where Chromium is
        cur = self._chromium_position_us()
        if cur is not None:
            self._delegate("Seek", dbus.Int64(int(position) - cur))

    @dbus.service.method(PLAYER, in_signature="s")
    def OpenUri(self, uri):
        pass

    @dbus.service.signal(PLAYER, signature="x")
    def Seeked(self, position):
        pass


def run_loop():
    GLib.MainLoop().run()
