import QtQuick

// Argon header: the panel's glyph (or image) centered above its title, both in the panel's accent,
// like "Ask Claude". Optional round actions in the corners: close (right) and one extra (left).
Item {
    id: h
    property string glyph: ""
    property url image: ""
    property string title: ""
    property string subtitle: ""
    property color accent: "#ffffff"
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    property bool closable: true
    property string leftGlyph: ""
    property string leftLabel: ""
    property bool leftVisible: leftGlyph !== ""
    signal closeClicked()
    signal leftClicked()
    width: parent ? parent.width : 0
    height: subtitle !== "" ? 62 : 48

    Item {
        id: mark
        width: 24; height: 24
        anchors.horizontalCenter: parent.horizontalCenter
        Text {
            anchors.centerIn: parent
            visible: h.image.toString() === ""
            text: h.glyph; color: h.accent
            font.family: h.iconFont; font.pixelSize: 21
            Behavior on color { ColorAnimation { duration: 220 } }
        }
        Image {
            anchors.fill: parent
            visible: h.image.toString() !== ""
            source: h.image; sourceSize: Qt.size(48, 48); smooth: true; mipmap: true
            fillMode: Image.PreserveAspectFit
        }
    }
    Text {
        id: titleText
        anchors.horizontalCenter: parent.horizontalCenter
        y: 28
        text: h.title; color: h.accent
        font.family: h.textFont; font.pixelSize: 16; font.weight: Font.DemiBold
        Behavior on color { ColorAnimation { duration: 220 } }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: titleText.bottom; anchors.topMargin: 2
        visible: h.subtitle !== ""
        width: Math.min(implicitWidth, h.width - 90); elide: Text.ElideRight
        text: h.subtitle; color: "#8e8e93"
        font.family: h.textFont; font.pixelSize: 11
    }
    ArgonIconButton {
        visible: h.leftVisible
        x: 0; y: 2
        glyph: h.leftGlyph; label: h.leftLabel
        iconFont: h.iconFont; textFont: h.textFont
        onClicked: h.leftClicked()
    }
    ArgonIconButton {
        visible: h.closable
        anchors.right: parent.right; y: 2
        glyph: ""; glyphSize: 12
        iconFont: h.iconFont; textFont: h.textFont
        onClicked: h.closeClicked()
    }
}
