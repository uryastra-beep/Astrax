import QtQuick

// Choose one of a few options. Segments are all the same width; the highlight travels between them.
Item {
    id: g
    property var options: []          // [{ value, label }]
    property var current: ""
    signal picked(var value)
    readonly property int index: Math.max(0, options.findIndex(o => o.value === current))
    readonly property real segW: options.length ? (width - 8) / options.length : 0
    implicitHeight: 36; implicitWidth: Math.max(160, options.length * 88 + 8)

    Rectangle { anchors.fill: parent; radius: Theme.controlRadius; color: Theme.surfaceHi; border.width: 1; border.color: Theme.line }
    Rectangle {
        y: 4; height: parent.height - 8; width: g.segW; radius: Theme.controlRadius - 4
        x: 4 + g.index * g.segW
        color: Theme.accent
        Behavior on x { NumberAnimation { duration: Theme.ease + 40; easing.type: Easing.OutCubic } }
    }
    Repeater {
        model: g.options
        delegate: Item {
            required property var modelData
            required property int index
            x: 4 + index * g.segW; y: 4; width: g.segW; height: g.height - 8
            Text {
                anchors.centerIn: parent
                text: parent.modelData.label
                color: index === g.index ? "#f6f6fa" : Theme.textDim
                font.family: Theme.font; font.pixelSize: Theme.t2; font.weight: Font.Medium
                Behavior on color { ColorAnimation { duration: Theme.ease } }
            }
            MouseArea { anchors.fill: parent; onClicked: g.picked(parent.modelData.value) }
        }
    }
}
