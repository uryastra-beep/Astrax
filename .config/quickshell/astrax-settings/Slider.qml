import QtQuick

// Direct manipulation: drag anywhere on the track. Snaps to `step`, fixed-width readout lives in the row.
Item {
    id: s
    property real from: 0
    property real to: 100
    property real step: 1
    property real value: 0
    property bool dragging: false
    signal moved(real value)          // while dragging (throttled by the caller)
    signal committed(real value)      // on release
    implicitWidth: 200; implicitHeight: 28

    readonly property real shown: dragging ? dragValue : value
    property real dragValue: value
    readonly property real frac: to > from ? Math.max(0, Math.min(1, (shown - from) / (to - from))) : 0

    function snap(v) {
        const n = Math.round((v - from) / step);
        return Math.max(from, Math.min(to, from + n * step));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3
        color: Theme.surfaceHi
        Rectangle {
            width: Math.max(handle.width / 2, handle.x + handle.width / 2); height: parent.height; radius: 3
            color: Theme.accent
        }
    }
    Rectangle {
        id: handle
        anchors.verticalCenter: parent.verticalCenter
        width: s.dragging ? 24 : 20; height: width; radius: width / 2
        x: s.frac * (s.width - 20) + (20 - width) / 2
        color: "#f1f1f6"
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on x { enabled: !s.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        preventStealing: true
        function at(x) { return s.snap(s.from + (s.to - s.from) * Math.max(0, Math.min(1, (x - 10) / (s.width - 20)))); }
        onPressed: m => { s.dragging = true; s.dragValue = at(m.x); s.moved(s.dragValue); }
        onPositionChanged: m => { if (!pressed) return; const v = at(m.x); if (v !== s.dragValue) { s.dragValue = v; s.moved(v); } }
        onReleased: { s.dragging = false; s.committed(s.dragValue); }
        onCanceled: { s.dragging = false; s.committed(s.dragValue); }
    }
}
