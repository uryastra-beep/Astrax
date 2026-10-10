import QtQuick
import "../../../"

// Vertical bar: the lyrics don't fit in a column, just an icon.
Item {
    id: root
    property var module: null
    property var widget: module
    readonly property var barWindow: module ? module.barWindow : null
    property real targetHeight: barWindow ? barWindow.s(36) : 36
    implicitHeight: targetHeight
    implicitWidth: parent ? parent.width : 0
    Text {
        anchors.centerIn: parent
        text: "󰎈"
        font.family: "Iosevka Nerd Font"
        font.pixelSize: root.barWindow ? root.barWindow.s(18) : 18
        color: ThemeBackend.mauve
    }
}
