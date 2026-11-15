import QtQuick
import Quickshell.Io

// One setting. spec: { type: toggle|slider|segmented|action|keys|value, key, title, desc, icon,
//   from, to, step, unit, def, options, keys, command, confirm, label, text, showIf: { key, eq?, ne? } }
Item {
    id: row
    property var spec: ({})
    property bool first: false
    readonly property string type: spec.type || "toggle"
    readonly property var current: spec.key ? Cfg.get(spec.key, spec.def) : undefined
    readonly property bool shown: {
        const c = spec.showIf;
        if (!c) return true;
        const v = Cfg.get(c.key, c.def);
        if (c.eq !== undefined) return v === c.eq;
        if (c.ne !== undefined) return v !== c.ne;
        return v === true;
    }
    readonly property real natural: Math.max(Theme.rowH, textCol.implicitHeight + 2 * Theme.sp3 - 4)

    width: parent ? parent.width : 400
    height: shown ? natural : 0
    opacity: shown ? 1 : 0
    visible: height > 0.5
    clip: true
    Behavior on height { NumberAnimation { duration: Theme.ease + 40; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Theme.ease } }

    Rectangle {
        anchors.fill: parent
        color: Theme.surfaceHi
        opacity: rowMouse.containsMouse && (row.type === "toggle") ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    Rectangle {
        visible: !row.first
        x: Theme.sp3 + 44; width: parent.width - x - Theme.sp3; height: 1; color: Theme.line; opacity: 0.7
    }

    Rectangle {
        id: tile
        x: Theme.sp3; anchors.verticalCenter: parent.verticalCenter
        width: 32; height: 32; radius: 10; color: Theme.surfaceHi
        visible: !!row.spec.icon
        Text {
            anchors.centerIn: parent; text: row.spec.icon || ""
            color: Theme.textDim; font.family: Theme.iconFont; font.pixelSize: 17
        }
    }
    Column {
        id: textCol
        x: Theme.sp3 + (tile.visible ? 44 : 0)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - controlBox.width - 2 * Theme.sp3
        spacing: 2
        Text {
            width: parent.width; text: row.spec.title || ""; elide: Text.ElideRight
            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.t2; font.weight: Font.Medium
        }
        Text {
            width: parent.width; visible: text.length > 0; text: row.spec.desc || ""
            wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.t1; lineHeight: 1.15
        }
    }

    // whole row toggles (touch target = the row)
    MouseArea {
        id: rowMouse
        anchors.fill: parent; hoverEnabled: true
        enabled: row.type === "toggle"
        onClicked: Cfg.set(row.spec.key, !(row.current === true))
    }

    Item {
        id: controlBox
        anchors.right: parent.right; anchors.rightMargin: Theme.sp3
        anchors.verticalCenter: parent.verticalCenter
        width: loader.item ? loader.item.implicitWidth + (row.type === "slider" ? 64 : 0) : 0
        height: loader.item ? loader.item.implicitHeight : 0

        Loader {
            id: loader
            anchors.right: parent.right
            sourceComponent: row.type === "slider" ? sliderC : row.type === "segmented" ? segC
                : row.type === "action" ? actionC : row.type === "keys" ? keysC
                : row.type === "value" ? valueC : row.type === "swatches" ? swatchC : toggleC
        }
        // fixed-width readout so the slider never moves while the number changes
        Text {
            visible: row.type === "slider"
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            width: 52; horizontalAlignment: Text.AlignRight
            text: loader.item && loader.item.shown !== undefined ? Math.round(loader.item.shown) + (row.spec.unit || "") : ""
            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.t2; font.weight: Font.Medium
        }
    }

    Component { id: toggleC; Toggle { checked: row.current === true; pressed: rowMouse.pressed } }
    Component {
        id: sliderC
        Slider {
            width: 190
            from: row.spec.from; to: row.spec.to; step: row.spec.step || 1
            value: row.current === undefined ? row.spec.from : row.current
            onMoved: v => throttle.push(v)
            onCommitted: v => { throttle.stop(); Cfg.set(row.spec.key, v); }
        }
    }
    Component { id: segC; Segmented { options: row.spec.options; current: row.current; onPicked: v => Cfg.set(row.spec.key, v) } }
    Component {
        id: swatchC
        Row {
            spacing: 8
            Repeater {
                model: row.spec.colors
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool on: String(row.current).toLowerCase() === modelData
                    width: 28; height: 28; radius: 14; color: modelData
                    border.width: on ? 2 : 1; border.color: on ? "#f6f6fa" : Theme.line
                    scale: sw.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    MouseArea { id: sw; anchors.fill: parent; onClicked: Cfg.set(row.spec.key, parent.modelData) }
                }
            }
        }
    }
    Component { id: actionC; ActionButton { label: row.spec.label || "Run"; command: row.spec.command || []; confirm: row.spec.confirm === true } }
    Component { id: keysC; KeyCaps { keys: row.spec.keys || [] } }
    Component {
        id: valueC
        Text {
            text: row.spec.text || ""; color: Theme.textDim
            font.family: Theme.font; font.pixelSize: Theme.t2
            elide: Text.ElideMiddle
        }
    }
    // live preview while dragging, without writing the file on every pixel
    QtObject {
        id: throttle
        property real pending: NaN
        function push(v) { pending = v; if (!tick.running) { Cfg.set(row.spec.key, v); tick.start(); } }
        function stop() { tick.stop(); pending = NaN; }
    }
    Timer {
        id: tick; interval: 110
        onTriggered: if (!isNaN(throttle.pending)) { Cfg.set(row.spec.key, throttle.pending); throttle.pending = NaN; tick.start(); }
    }
}
