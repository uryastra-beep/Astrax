import QtQuick
import Qt5Compat.GraphicalEffects

// Image clipped to a rounded rectangle.
Item {
    id: root
    property alias source: img.source
    property real radius: 10
    // Stable decode resolution: magnification must not reload the source every frame.
    property int decodeResolution: 256
    readonly property bool loaded: img.status === Image.Ready

    Image {
        id: img
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: false
        sourceSize.width: root.decodeResolution
        sourceSize.height: root.decodeResolution
    }
    Rectangle { id: mask; anchors.fill: parent; radius: root.radius; visible: false }
    OpacityMask { anchors.fill: parent; source: img; maskSource: mask; visible: root.loaded }
}
