import QtQuick

// iPhone clock without the date: the same face with showDate off
Item {
    id: wrap
    anchors.fill: parent

    property real minWidth: 100
    property real minHeight: 120
    property real maxWidth: 900
    property real maxHeight: 1400
    property real minAspect: 0.3
    property real maxAspect: 2.5
    property bool isRound: false

    Loader {
        anchors.fill: parent
        source: Qt.resolvedUrl("ClockFaceIOS.qml")
        onLoaded: item.showDate = false
    }
}
