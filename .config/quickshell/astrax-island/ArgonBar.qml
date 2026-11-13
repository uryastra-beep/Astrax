import QtQuick

// Argon input bar: a dark pill washed with the panel's accent, a round leading glyph, the panel's own
// field in the middle (children go there) and an optional round trailing action.
Rectangle {
    id: bar
    property color accent: "#ffffff"
    property string iconFont: "Iosevka Nerd Font"
    property string textFont: "Rubik"
    property string glyph: ""
    property bool leadingClickable: false
    property string trailingGlyph: ""
    property bool trailingLive: false
    property bool focused: false
    signal leadingClicked()
    signal trailingClicked()
    default property alias content: slot.data
    function tint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }

    height: 42; radius: height / 2
    color: "#101012"
    border.width: 1; border.color: focused ? tint(0.32) : tint(0.14)
    Behavior on border.color { ColorAnimation { duration: 160 } }
    Rectangle {
        anchors.fill: parent; radius: bar.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: bar.tint(0.09) }
            GradientStop { position: 0.5; color: bar.tint(0.15) }
            GradientStop { position: 1.0; color: bar.tint(0.09) }
        }
    }
    Rectangle {
        id: lead
        x: 6; anchors.verticalCenter: parent.verticalCenter
        width: bar.height - 12; height: width; radius: width / 2
        color: leadArea.containsMouse && bar.leadingClickable ? "#26ffffff" : "#16ffffff"
        Behavior on color { ColorAnimation { duration: 140 } }
        Text {
            anchors.centerIn: parent
            text: bar.glyph; color: bar.accent
            font.family: bar.iconFont; font.pixelSize: 12
        }
        MouseArea {
            id: leadArea
            anchors.fill: parent; enabled: bar.leadingClickable; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor; onClicked: bar.leadingClicked()
        }
    }
    Item {
        id: slot
        anchors.left: lead.right; anchors.leftMargin: 10
        anchors.right: trail.visible ? trail.left : parent.right
        anchors.rightMargin: trail.visible ? 8 : 16
        anchors.top: parent.top; anchors.bottom: parent.bottom
    }
    Rectangle {
        id: trail
        visible: bar.trailingGlyph !== ""
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        width: bar.height - 12; height: width; radius: width / 2
        color: bar.trailingLive ? (trailArea.pressed ? Qt.darker(bar.accent, 1.2) : bar.accent) : bar.tint(0.22)
        Behavior on color { ColorAnimation { duration: 160 } }
        scale: trailArea.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Text {
            anchors.centerIn: parent
            text: bar.trailingGlyph; color: bar.trailingLive ? "#121212" : bar.accent
            font.family: bar.iconFont; font.pixelSize: 12
        }
        MouseArea { id: trailArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.trailingClicked() }
    }
}
