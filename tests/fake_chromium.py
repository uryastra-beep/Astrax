"""Stand-in for Liner's Chromium MPRIS player (used by tests/test-liner.sh).
Runs in its own process, as the real one does, and records the calls it gets."""
import sys
import dbus, dbus.mainloop.glib, dbus.service
from gi.repository import GLib

log = sys.argv[1]


class Fake(dbus.service.Object):
    def rec(self, s):
        with open(log, "a") as f:
            f.write(s + "\n")

    @dbus.service.method("org.mpris.MediaPlayer2.Player")
    def PlayPause(self): self.rec("PlayPause")

    @dbus.service.method("org.mpris.MediaPlayer2.Player")
    def Next(self): self.rec("Next")

    @dbus.service.method("org.mpris.MediaPlayer2.Player", in_signature="x")
    def Seek(self, o): self.rec("Seek %d" % o)


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.mpris.MediaPlayer2.chromium.instance4242", bus)
Fake(name, "/org/mpris/MediaPlayer2")
open(log + ".ready", "w").write("1")
GLib.MainLoop().run()
