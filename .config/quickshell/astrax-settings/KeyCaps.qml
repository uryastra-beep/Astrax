import QtQuick

// A shortcut drawn as key caps: ["Super", "."]
Row {
    id: k
    property var keys: []
    spacing: 4
    Repeater {
        model: k.keys
        delegate: Rectangle {
            required property string modelData
            width: Math.max(28, label.implicitWidth + 16); height: 28; radius: 8
            color: Theme.surfaceHi; border.width: 1; border.color: Theme.line
            Text {
                id: label
                anchors.centerIn: parent; text: parent.modelData
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.t2; font.weight: Font.Medium
            }
        }
    }
}
