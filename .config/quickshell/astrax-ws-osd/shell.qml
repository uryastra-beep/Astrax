import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Workspace OSD: when the workspace changes it shows the number for a while in the
// bottom-right corner of THAT monitor and fades out by itself. Click-through
// (empty mask), doesn't steal focus. The number is relative to the monitor (1..20), same
// as infinite-desktop's "m~N" navigation: p2 uses ids 21-40 internally.
ShellRoot {
    id: root

    readonly property int workspacesPerMonitor: 20
    // GLASS on the numbers (translucent fill + light border; the blur comes
    // from the "astrax-ws-osd-glass" layer_rule in windowrules.lua, which follows the
    // text shape). To remove it: false here and delete that layer_rule.
    readonly property bool glass: true

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property var hmon: Hyprland.monitorFor(modelData)
            readonly property var ws: hmon ? hmon.activeWorkspace : null
            property string label: ""
            property int num: 0          // 1..20, 0 = special
            property int lastId: 0
            readonly property int rowH: 38
            property bool shown: false
            property bool ready: false

            WlrLayershell.namespace: "astrax-ws-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}

            anchors {
                bottom: true
                right: true
            }
            margins {
                bottom: 28
                right: 28
            }
            implicitWidth: 60
            implicitHeight: 80
            visible: shown || card.opacity > 0

            function labelFor(w) {
                if (!w) return "";
                if (w.id < 0) return (w.name || "").replace("special:", "");
                return String(((w.id - 1) % root.workspacesPerMonitor) + 1);
            }

            // without this it shows up once when the daemon starts
            Component.onCompleted: Qt.callLater(() => win.ready = true)

            onWsChanged: {
                if (!ws || !ready) return;
                label = labelFor(ws);
                num = ws.id > 0 ? ((ws.id - 1) % root.workspacesPerMonitor) + 1 : 0;
                // wheel: goes up if you move to the next one, down if to the previous one
                let dir = (lastId && ws.id > 0) ? Math.sign(ws.id - lastId) : 0;
                lastId = ws.id;
                wheel.offset = dir * win.rowH;
                slideAnim.restart();
                shown = true;
                hideTimer.restart();
            }

            Timer {
                id: hideTimer
                interval: 1100
                onTriggered: win.shown = false
            }

            // just the number, no box -- black outline
            // so it's readable over any wallpaper/app.
            Item {
                id: card
                anchors.fill: parent
                opacity: win.shown ? 1 : 0
                scale: win.shown ? 1 : 0.85
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }


                // previous on top, current in the middle, next at the bottom; the
                // neighbours at half opacity. Slides from bottom to top.
                Item {
                    id: wheel
                    anchors.fill: parent
                    clip: true
                    property real offset: 0
                    // neighbours cut in half and fading towards the
                    // edge (picker/app wheel style)
                    layer.enabled: true
                    // real alpha mask: top and bottom fade out
                    layer.effect: OpacityMask { maskSource: fadeMask }
                    NumberAnimation on offset { id: slideAnim; to: 0; duration: 260; easing.type: Easing.OutCubic; running: false }

                    Column {
                        id: wheelCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: (parent.height - win.rowH * 3) / 2 + wheel.offset
                        // stretch while moving up/down: stretches vertically
                        // proportional to the slide speed and returns to 1
                        readonly property real k: Math.min(1, Math.abs(wheel.offset) / win.rowH)
                        transform: Scale {
                            origin.x: 30
                            origin.y: win.rowH * 1.5
                            yScale: 1 + 0.45 * wheelCol.k
                            xScale: 1 - 0.18 * wheelCol.k
                        }
                        Repeater {
                            model: [-1, 0, 1]
                            Text {
                                required property int modelData
                                width: 60
                                height: win.rowH
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                readonly property int n: win.num + modelData
                                text: modelData === 0 ? win.label
                                    : (win.num > 0 && n >= 1 && n <= root.workspacesPerMonitor ? String(n) : "")
                                color: root.glass ? Qt.rgba(1, 1, 1, 0.05) : "#cdd6f4"
                                style: Text.Outline
                                styleColor: root.glass ? Qt.rgba(1, 1, 1, 0.75) : "black"
                                opacity: modelData === 0 ? 1.0 : 0.7
                                font.pixelSize: modelData === 0 ? (win.label.length > 2 ? 16 : 30) : 20
                                font.family: "Rubik"   // rounded corners on the numbers
                                font.weight: Font.Black
                            }
                        }
                    }
                }

                Item {
                    id: fadeMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.32; color: "white" }
                            GradientStop { position: 0.68; color: "white" }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }
            }
        }
    }
}
