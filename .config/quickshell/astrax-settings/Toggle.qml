import QtQuick

// On / off only (segmented control for choices). Knob widens while pressed, like iOS.
Item {
    id: t
    property bool checked: false
    property bool pressed: false
    signal toggled(bool value)
    implicitWidth: 48; implicitHeight: 28

    Rectangle {
        anchors.fill: parent; radius: height / 2
        color: t.checked ? Theme.accent : Theme.surfaceHi
        border.width: 1; border.color: t.checked ? "transparent" : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.ease } }
    }
    Rectangle {
        id: knob
        y: 3; height: 22; radius: 11
        width: t.pressed ? 27 : 22
        x: t.checked ? t.width - width - 3 : 3
        color: "#f1f1f6"
        Behavior on x { NumberAnimation { duration: Theme.ease; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
}
