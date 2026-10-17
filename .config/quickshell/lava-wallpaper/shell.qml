pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// WORT (Wallpaper On Real Time): "lava lamp" wallpaper with up to 7 colors from the
// music, the focused app or an idle purple palette. palette.py writes /tmp/lava-palette.json.
ShellRoot {
    id: root

    readonly property var defaults: ["#a855f7", "#7552b3", "#5b3a9e", "#c084fc", "#3b2470", "#8b5cf6", "#2a1a4e"]
    property var target: defaults.map(h => Qt.color(h))
    property var weights: [1, 1, 1, 1, 1, 1, 1]

    Process {
        running: true
        command: ["python3", Qt.resolvedUrl("palette.py").toString().replace("file://", "")]
    }

    FileView {
        path: "/tmp/lava-palette.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                const mx = Math.max(...j.map(e => e.w), 0.0001);
                root.target = j.slice(0, 7).map(e => Qt.color("#" + e.hex));
                root.weights = j.slice(0, 7).map(e => e.w / mx);
            } catch (e) {}
        }
    }

    // 7 animated colors (smooth transition between palettes)
    property color k0: target[0]
    property color k1: target[1]
    property color k2: target[2]
    property color k3: target[3]
    property color k4: target[4]
    property color k5: target[5]
    property color k6: target[6]
    Behavior on k0 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k1 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k2 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k3 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k4 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k5 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k6 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }

    // Bass pulse: a small cava of its own (cava.conf, 6 mono bars) makes the bubbles swell
    // with the bass and the colors brighten with any loud sound. pulseGain tones it down when
    // the palette is mostly white, where the brightening would blow out.
    property real bass: 0
    property real bassAvg: 0
    property real loud: 0      // hits across the whole spectrum (for the brightness)
    property real loudAvg: 0

    // Palette with whites (high brightness, low saturation) -> softer pulse
    readonly property real pulseGain: {
        let white = 0;
        for (const c of target) {
            const mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b);
            const sat = mx > 0 ? (mx - mn) / mx : 0;
            const w = Math.max(0, Math.min(1, (mx - 0.65) / 0.25)) * Math.max(0, Math.min(1, (0.45 - sat) / 0.3));
            white = Math.max(white, w);
        }
        return 1.0 - 0.7 * white;
    }
    Process {
        id: cavaProc
        running: true
        command: ["cava", "-p", Qt.resolvedUrl("cava.conf").toString().replace("file://", "")]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const p = data.split(";").filter(s => s.length > 0).map(s => parseInt(s, 10) || 0);
                if (p.length < 2) return;
                // hit = bass above its recent average (~1 s): only the beats light up,
                // sustained volume doesn't
                const b = (p[0] + p[1]) / 2 / 1000;
                root.bassAvg = root.bassAvg * 0.98 + b * 0.02;
                root.bass = Math.min(1, Math.max(0, b - root.bassAvg * 1.15 - 0.05) * 3.5);
                const l = p.reduce((a, v) => a + v, 0) / p.length / 1000;
                root.loudAvg = root.loudAvg * 0.98 + l * 0.02;
                root.loud = Math.min(1, Math.max(0, l - root.loudAvg * 1.15 - 0.04) * 3.5);
            }
        }
        onExited: cavaRestart.restart()
    }
    Timer { id: cavaRestart; interval: 500; onTriggered: cavaProc.running = true }

    property real t: 0
    Timer {
        interval: 33; running: true; repeat: true
        onTriggered: root.t += 0.033
    }

    Variants {
        model: Quickshell.screens.filter(s => (Quickshell.env("LW_SCREEN") || "") === "" || s.name === Quickshell.env("LW_SCREEN"))

        PanelWindow {
            required property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "lava-wallpaper"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            color: "black"
            mask: Region {}

            ShaderEffect {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.textureSize: Qt.size(Math.max(1, width / 3), Math.max(1, height / 3))

                property real time: root.t
                property real aspect: width / Math.max(1, height)
                property real bass: root.bass * root.pulseGain
                property real loud: root.loud * root.pulseGain
                function k(c, i) { return Qt.rgba(c.r, c.g, c.b, root.weights[i]); }
                property vector4d k0: Qt.vector4d(root.k0.r, root.k0.g, root.k0.b, root.weights[0])
                property vector4d k1: Qt.vector4d(root.k1.r, root.k1.g, root.k1.b, root.weights[1])
                property vector4d k2: Qt.vector4d(root.k2.r, root.k2.g, root.k2.b, root.weights[2])
                property vector4d k3: Qt.vector4d(root.k3.r, root.k3.g, root.k3.b, root.weights[3])
                property vector4d k4: Qt.vector4d(root.k4.r, root.k4.g, root.k4.b, root.weights[4])
                property vector4d k5: Qt.vector4d(root.k5.r, root.k5.g, root.k5.b, root.weights[5])
                property vector4d k6: Qt.vector4d(root.k6.r, root.k6.g, root.k6.b, root.weights[6])
                fragmentShader: Qt.resolvedUrl("lava.frag.qsb")
            }
        }
    }
}
