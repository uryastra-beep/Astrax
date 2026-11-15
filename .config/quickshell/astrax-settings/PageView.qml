import QtQuick

// One settings page: big title, short subtitle, then groups. Scrolls smoothly; the bar only shows while scrolling.
Item {
    id: p
    property string title: ""
    property string subtitle: ""
    property var groups: []

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width; contentHeight: col.height + Theme.sp5
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2600; maximumFlickVelocity: 3200
        clip: true
        Column {
            id: col
            x: 0; width: flick.width - Theme.sp2
            spacing: Theme.sp3
            Column {
                width: parent.width; spacing: 4; bottomPadding: Theme.sp2
                Text { text: p.title; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.t5; font.weight: Font.DemiBold }
                Text {
                    visible: text.length > 0; text: p.subtitle; width: parent.width; wrapMode: Text.WordWrap
                    color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.t2
                }
            }
            Repeater {
                model: p.groups
                delegate: SettingGroup {
                    required property var modelData
                    title: modelData.title || ""
                    rows: modelData.rows
                }
            }
        }
    }
    Rectangle {
        id: bar
        anchors.right: parent.right
        width: 4; radius: 2; color: Theme.textDim
        height: Math.max(32, flick.height * flick.height / Math.max(flick.contentHeight, 1))
        y: flick.contentHeight > flick.height ? flick.contentY / (flick.contentHeight - flick.height) * (flick.height - height) : 0
        opacity: flick.moving && flick.contentHeight > flick.height ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }
}
