import QtQuick

// Sidebar entry: icon + short label. The accent pill that marks the active one lives in the sidebar (shared element).
Item {
    id: s
    property string icon: ""
    property string label: ""
    property bool active: false
    signal clicked()
    height: 44

    Rectangle {
        anchors.fill: parent; radius: Theme.controlRadius + 2
        color: Theme.surfaceHi
        opacity: !s.active && area.containsMouse ? 0.7 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    Text {
        x: 14; anchors.verticalCenter: parent.verticalCenter; width: 22
        text: s.icon; horizontalAlignment: Text.AlignHCenter
        color: s.active ? "#f6f6fa" : Theme.textDim
        font.family: Theme.iconFont; font.pixelSize: 18
        Behavior on color { ColorAnimation { duration: Theme.ease } }
    }
    Text {
        x: 48; anchors.verticalCenter: parent.verticalCenter
        text: s.label
        color: s.active ? "#f6f6fa" : Theme.text
        font.family: Theme.font; font.pixelSize: Theme.t2; font.weight: s.active ? Font.Medium : Font.Normal
        Behavior on color { ColorAnimation { duration: Theme.ease } }
    }
    scale: area.pressed ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: s.clicked() }
}
