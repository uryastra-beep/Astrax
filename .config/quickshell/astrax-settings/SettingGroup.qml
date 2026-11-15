import QtQuick

// A titled card of rows.
Item {
    id: g
    property string title: ""
    property var rows: []
    width: parent ? parent.width : 400
    height: head.height + card.height + Theme.sp2

    Text {
        id: head
        visible: g.title.length > 0
        height: visible ? implicitHeight + Theme.sp2 : 0
        x: Theme.sp2; text: g.title.toUpperCase()
        color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.t1; font.weight: Font.DemiBold
        font.letterSpacing: 0.9
    }
    Rectangle {
        id: card
        y: head.height; width: parent.width; radius: Theme.groupRadius
        height: col.height; color: Theme.surface
        border.width: 1; border.color: Theme.line
        clip: true
        Column {
            id: col
            width: parent.width
            Repeater {
                model: g.rows
                delegate: SettingRow {
                    required property var modelData
                    required property int index
                    spec: modelData
                    first: index === 0
                }
            }
        }
    }
}
