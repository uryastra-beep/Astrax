pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// widgets3: single fullscreen Cava visualizer, transparent, click-through,
// unfocusable, undecorated -- "part of the wallpaper". Unlike
// widgets/widgets2 (kitty + cava in ncurses mode, normal floating
// windows), this one uses a real wlr-layer-shell surface: it's the ONLY way
// to get true click-through + zero focus on Hyprland/Wayland (an
// xdg-toplevel window like kitty can always receive clicks). cava runs
// in "raw" mode (prints bar numbers to stdout instead of drawing them
// itself) and this QML draws the bars.
ShellRoot {
    id: root

    readonly property string colorsFile: "/tmp/widget-colors.json"
    readonly property string cavaConfig: `${Quickshell.env("HOME")}/.config/cava/config-widget3`

    // Read SYNCHRONOUSLY from an env var set by widget3-ctl.sh before
    // launching "qs -c widgets3" -- on purpose, NOT via FileView (async).
    // zwlr_layer_shell_v1 fixes the output when the surface is CREATED: if
    // "screen:" changes only after the surface was mapped
    // (a real race that happened with the file + FileView), Quickshell doesn't
    // move it by itself and the window stays stuck on the default monitor
    // forever, even if the binding "fixes" the value later. With an env var the
    // value is available before the first frame, no race possible.
    property string targetMonitor: Quickshell.env("WIDGETS3_MONITOR") || ""
    property color primaryColor: "#cfbfeb"
    property color tertiaryColor: "#ffdcf0"
    property var barValues: []
    property int barCount: 64
    property int animMs: 16 // recomputed by reading "framerate" from cavaConfig

    function hexToColor(hex) {
        if (!hex) return undefined;
        const h = hex.replace("#", "");
        if (h.length !== 6) return undefined;
        return Qt.rgba(parseInt(h.substr(0, 2), 16) / 255,
                        parseInt(h.substr(2, 2), 16) / 255,
                        parseInt(h.substr(4, 2), 16) / 255, 1);
    }

    function lerpColor(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t,
                        a.g + (b.g - a.g) * t,
                        a.b + (b.b - a.b) * t, 1);
    }

    // -------- current song colors (same source as widgets/widgets2) --------
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
                console.warn("widgets3: could not parse widget-colors.json:", e);
            }
        }
        onLoadFailed: {
            root.primaryColor = "#cfbfeb";
            root.tertiaryColor = "#ffdcf0";
        }
    }

    // -------- current framerate (patched by "widgets3 opti on|off") --------
    FileView {
        path: root.cavaConfig
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = text().match(/^framerate\s*=\s*(\d+)/m);
            if (m) root.animMs = Math.max(8, Math.round(1000 / parseInt(m[1], 10)));
        }
    }

    // -------- cava in raw mode: one number per bar, separated by ";" --------
    Process {
        id: cavaProc
        command: ["cava", "-p", root.cavaConfig]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data) return;
                const parts = data.split(";").filter(s => s.length > 0);
                if (parts.length === 0) return;
                root.barValues = parts.map(s => parseInt(s, 10) || 0);
                root.barCount = root.barValues.length;
            }
        }
        onExited: restartTimer.restart()
    }

    Timer {
        id: restartTimer
        interval: 150
        onTriggered: cavaProc.running = true
    }

    PanelWindow {
        id: win

        screen: {
            if (!root.targetMonitor) return null;
            const found = Quickshell.screens.find(s => s.name === root.targetMonitor);
            return found || null;
        }

        WlrLayershell.namespace: "widgets3"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        color: "transparent"
        exclusiveZone: 0
        // click-through on the whole surface -- the mini player no longer
        // has controls (text only), so no interactive
        // sub-region is needed.
        mask: Region {}

        anchors { left: true; right: true; top: true; bottom: true }

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
                    height: Math.max(3, norm * viz.height * 0.9)
                    y: viz.height - height
                    radius: width * 0.3
                    color: root.lerpColor(root.primaryColor, root.tertiaryColor, gradT)
                    opacity: 0.92

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
