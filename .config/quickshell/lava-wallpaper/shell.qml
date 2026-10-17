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
