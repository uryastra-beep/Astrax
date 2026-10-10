pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// widgets2: clock + lyrics (sptlrx) + fullscreen cava on top, ALL in a
// single wlr-layer-shell surface -- same as widgets3,
// click-through and
// unfocusable. The 3 elements must be ONE single surface -- if cava were its
// own surface on the "Bottom" layer it would end up UNDER the clock/lyrics
// (normal windows), inverting the current visual order (cava on top of
// everything). In QML, the order is simply the declaration order (cava last).
ShellRoot {
    id: root

    readonly property string colorsFile: "/tmp/widget-colors.json"
    readonly property string sptlrxModeFile: "/tmp/widget-sptlrx-mode"
    readonly property string cavaConfig: `${Quickshell.env("HOME")}/.config/cava/config-widget2`

    // Read SYNCHRONOUSLY from an env var set by widget2-ctl.sh before
    // launching "qs -c widgets2" -- see the same note in widgets3/shell.qml: reading it
    // via FileView (async) is a real race -- zwlr_layer_shell_v1
    // fixes the output when the surface is CREATED, and if "screen:" changes only
    // after it's mapped, Quickshell doesn't move it by itself.
    property string targetMonitor: Quickshell.env("WIDGETS2_MONITOR") || ""
    property string sptlrxMode: "lyrics" // "lyrics" or "pipes" (no lyrics -> clock takes everything)
    property color primaryColor: "#cfbfeb"
    property color tertiaryColor: "#ffdcf0"
    property string currentLyric: ""
    property var barValues: []
    property int barCount: 64
    property int animMs: 16

    function hexToColor(hex) {
        if (!hex) return undefined;
        const h = hex.replace("#", "");
        if (h.length !== 6) return undefined;
        return Qt.rgba(parseInt(h.substr(0, 2), 16) / 255,
                        parseInt(h.substr(2, 2), 16) / 255,
                        parseInt(h.substr(4, 2), 16) / 255, 1);
    }
    function lerpColor(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    FileView {
        path: root.colorsFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.primaryColor = root.hexToColor(c.primary) || root.primaryColor;
                root.tertiaryColor = root.hexToColor(c.tertiary) || root.tertiaryColor;
            } catch (e) {
                console.warn("widgets2: could not parse widget-colors.json:", e);
            }
        }
        onLoadFailed: {
            root.primaryColor = "#cfbfeb";
            root.tertiaryColor = "#ffdcf0";
        }
    }

    FileView {
        path: root.sptlrxModeFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.sptlrxMode = text().trim() || "lyrics"
        onLoadFailed: root.sptlrxMode = "lyrics"
    }

    FileView {
        path: root.cavaConfig
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = text().match(/^framerate\s*=\s*(\d+)/m);
            if (m) root.animMs = Math.max(8, Math.round(1000 / parseInt(m[1], 10)));
        }
    }

    // -------- clock: native QML, doesn't depend on clock-rs --------
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "h:mm AP")
    }

    // -------- lyrics: "sptlrx pipe" prints the current line to stdout --------
    Process {
        id: sptlrxProc
        command: ["sptlrx", "pipe"]
        running: root.sptlrxMode === "lyrics"
        stdout: SplitParser {
            onRead: data => { root.currentLyric = data; }
        }
        onExited: if (root.sptlrxMode === "lyrics") sptlrxRestart.restart()
    }
    Timer { id: sptlrxRestart; interval: 500; onTriggered: sptlrxProc.running = true }

    // -------- cava in raw mode --------
    Process {
        id: cavaProc
        command: ["cava", "-p", root.cavaConfig]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (!data) return;
                const parts = data.split(";").filter(s => s.length > 0);
                if (parts.length === 0) return;
                root.barValues = parts.map(s => parseInt(s, 10) || 0);
                root.barCount = root.barValues.length;
            }
        }
        onExited: cavaRestart.restart()
    }
    Timer { id: cavaRestart; interval: 150; onTriggered: cavaProc.running = true }

    PanelWindow {
        id: win

        screen: {
            if (!root.targetMonitor) return null;
            const found = Quickshell.screens.find(s => s.name === root.targetMonitor);
            return found || null;
        }

        WlrLayershell.namespace: "widgets2"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        color: "transparent"
        exclusiveZone: 0
        // click-through on the whole surface -- the mini player no longer
        // has controls (text only), so no interactive
        // sub-region is needed.
        mask: Region {}

        anchors { left: true; right: true; top: true; bottom: true }

        // translucent background behind clock/lyrics (equivalent to the blur
        // clock2/sptlrx2 had as separate kitty windows -- a single
        // surface can't blur only part of itself)
        Rectangle {
            id: backdrop
            anchors.fill: parent
            visible: root.sptlrxMode !== undefined
            color: Qt.rgba(0.1, 0.09, 0.13, 0.18)
        }

        // -------- clock (left if there are lyrics, full screen otherwise) --------
        Item {
            id: clockArea
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: root.sptlrxMode === "pipes" ? parent.width : (parent.width - 5) / 2

            Text {
                id: clockText
                anchors.centerIn: parent
                color: root.primaryColor
                font.family: "monospace"
                font.bold: true
                font.pixelSize: Math.min(clockArea.width, clockArea.height) * 0.22
                text: Qt.formatDateTime(new Date(), "h:mm AP")
            }
        }

        // -------- lyrics (right, only if there are lyrics) --------
        Item {
            id: lyricsArea
            visible: root.sptlrxMode === "lyrics"
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: (parent.width - 5) / 2

            Text {
                anchors.centerIn: parent
                anchors.margins: 24
                width: lyricsArea.width - 48
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: root.primaryColor
                font.family: "sans-serif"
                font.bold: true
                font.pixelSize: 26
                text: root.currentLyric
            }
        }

        // -------- fullscreen cava, ON TOP of clock/lyrics (last = topmost) --------
        Item {
            id: viz
            anchors.fill: parent

            Repeater {
                model: root.barCount
                delegate: Rectangle {
                    id: bar
                    required property int index

                    readonly property real raw: index < root.barValues.length ? root.barValues[index] : 0
                    readonly property real norm: Math.max(0, Math.min(1, raw / 1000))
                    readonly property real gradT: root.barCount > 1 ? index / (root.barCount - 1) : 0

                    width: viz.width / root.barCount * 0.7
                    x: (viz.width / root.barCount) * index + (viz.width / root.barCount * 0.15)
                    height: Math.max(3, norm * viz.height * 0.5)
                    y: viz.height - height
                    radius: width * 0.3
                    color: root.lerpColor(root.primaryColor, root.tertiaryColor, gradT)
                    opacity: 0.85

                    Behavior on height {
                        NumberAnimation { duration: root.animMs; easing.type: Easing.OutQuad }
                    }
                }
            }
        }

        // -------- mini player, top left, ON TOP of everything --------
        MediaCard {
            id: mediaCard
            primaryColor: root.primaryColor
            tertiaryColor: root.tertiaryColor
            x: 12
            y: 12
        }
    }
}
