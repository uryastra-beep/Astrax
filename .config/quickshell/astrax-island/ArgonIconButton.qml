import QtQuick

// Argon round icon button. With a `label`, hovering opens a curtain to the right of the icon with
// the text (icon first, text only on hover when it helps).
Rectangle {
    id: b
    property string glyph: ""
    property string label: ""
    property string iconFont: "Iosevka Nerd Font"
    property string textFont: "Rubik"
    property color accent: "#ffffff"
    property bool filled: false          // solid accent (primary action)
    property int size: 28
    property real glyphSize: Math.round(size * 0.44)
    property color glyphColor: filled ? "#121212" : "#e5e5ea"
    signal clicked()
    readonly property bool hot: area.containsMouse
    height: size; radius: size / 2
    width: size + (hot && label !== "" ? labelText.implicitWidth + 12 : 0)
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    clip: true
    color: filled ? (area.pressed ? Qt.darker(accent, 1.2) : accent)
                  : (area.pressed ? "#33ffffff" : hot ? "#24ffffff" : "#16ffffff")
    Behavior on color { ColorAnimation { duration: 140 } }
    scale: area.pressed ? 0.93 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Text {
        width: b.size; height: b.size
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        text: b.glyph; color: b.glyphColor
        font.family: b.iconFont; font.pixelSize: b.glyphSize
    }
    Text {
        id: labelText
        x: b.size - 3; anchors.verticalCenter: parent.verticalCenter
        text: b.label; color: "#e5e5ea"
        opacity: b.hot ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        font.family: b.textFont; font.pixelSize: 11; font.weight: Font.Medium
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
