import QtQuick
import Quickshell.Io

// Runs a command. `confirm` makes it a two-step button (destructive actions): the first click arms it,
// the second one (within 3 s) runs it. Feedback is the label itself; no spinner.
Item {
    id: b
    property string label: ""
    property var command: []
    property bool confirm: false
    property string state: "idle"     // idle | armed | done
    implicitWidth: Math.max(confirm ? 188 : 96, text.implicitWidth + 32); implicitHeight: 36

    Process { id: proc; command: b.command; onRunningChanged: if (!running && b.state === "run") { b.state = "done"; reset.restart(); } }
    Timer { id: reset; interval: 1800; onTriggered: b.state = "idle" }
    Timer { id: disarm; interval: 3000; onTriggered: if (b.state === "armed") b.state = "idle" }

    function press() {
        if (b.state === "run" || b.state === "done") return;
        if (b.confirm && b.state !== "armed") { b.state = "armed"; disarm.restart(); return; }
        b.state = "run"; proc.running = true;
    }

    Rectangle {
        anchors.fill: parent; radius: Theme.controlRadius
        color: b.state === "armed" ? Theme.danger : b.state === "done" ? Theme.surfaceHi : area.containsMouse ? Theme.surfaceHi : "transparent"
        border.width: 1; border.color: b.state === "armed" ? "transparent" : Theme.line
        scale: area.pressed ? 0.97 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Text {
            id: text
            anchors.centerIn: parent
            text: b.state === "armed" ? "Click again to confirm" : b.state === "done" ? "Done" : b.label
            color: b.state === "armed" ? "#fff6f6" : b.state === "done" ? Theme.accent : Theme.text
            font.family: Theme.font; font.pixelSize: Theme.t2; font.weight: Font.Medium
        }
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: b.press() }
}
