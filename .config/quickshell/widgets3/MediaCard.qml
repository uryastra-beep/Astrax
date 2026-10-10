import QtQuick
import Quickshell.Io

// Mini "now playing": title - artist + duration, nothing else (no cover,
// no controls -- simplified version). Used by widgets2 AND
// widgets3 (file duplicated on purpose in both folders -- each Quickshell
// config is its own self-contained package, there are no imports between
// different configs).
//
// Reuses the same caelestia mpris border_colors.py already uses (READ
// only, no new detector). No controls -> purely click-through,
// like the rest of the surface (the parent needs no special mask
// for this card).
Item {
    id: root

    property color primaryColor: "#cfbfeb"
    property color tertiaryColor: "#ffdcf0"

    property string title: ""
    property string artist: ""
    property real positionSec: 0

    visible: root.title.length > 0
    width: 320
    height: 22 + 4 + 16

    function formatTime(sec) {
        if (!sec || sec < 0) return "0:00";
        const m = Math.floor(sec / 60);
        const s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // -------- polling: title/artist/position, same mpris as
    // border_colors.py, READ only, every 2s. --------
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: pollProc.running = true
    }
    Process {
        id: pollProc
        command: ["bash", "-c",
            "caelestia shell mpris getActive trackTitle 2>/dev/null; printf '\\x1e'; " +
            "caelestia shell mpris getActive trackArtist 2>/dev/null; printf '\\x1e'; " +
            "caelestia shell mpris getActive position 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.split("\x1e");
                const clean = s => (!s || s === "Invalid property" || s === "No active player") ? "" : s.trim();
                root.title = clean(p[0]);
                root.artist = clean(p[1]);
                root.positionSec = parseFloat(p[2]) || 0;
            }
        }
    }

    Column {
        x: 0
        y: 0
        width: root.width
        spacing: 4

        Text {
            width: parent.width
            text: root.artist.length > 0 ? (root.title + " - " + root.artist) : root.title
            color: root.primaryColor
            font.family: "sans-serif"
            font.bold: true
            font.pixelSize: 15
            elide: Text.ElideRight
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.55)
        }
        Text {
            text: root.formatTime(root.positionSec)
            color: Qt.rgba(root.primaryColor.r, root.primaryColor.g, root.primaryColor.b, 0.75)
            font.family: "sans-serif"
            font.pixelSize: 12
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.55)
        }
    }
}
