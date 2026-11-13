import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history (cliphist) inside the island. Same chrome as the launcher: title, search,
// a scrolling list with a Liquid Glass selector, and a hint line.
Item {
    id: panel
    property bool opened: false
    opacity: 0
    scale: 0.98
    transformOrigin: Item.Top
    ParallelAnimation {
        id: appear
        NumberAnimation { target: panel; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: panel; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.5
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    signal dismissed()

    readonly property string listScript: Quickshell.shellPath("clip-list.sh")
    readonly property int rowHeight: 48
    property var entries: []
    property int selectedIndex: 0
    property bool loaded: false

    readonly property var shown: {
        const q = search.text.trim().toLowerCase();
        if (!q) return entries;
        return entries.filter(e => (e.kind === "image" ? "image " + (e.info || "") : e.text || "").toLowerCase().includes(q));
    }
    readonly property int preferredHeight: 150 + Math.min(6, Math.max(1, shown.length)) * rowHeight
    onShownChanged: selectedIndex = Math.max(0, Math.min(selectedIndex, shown.length - 1))

    function reload() {
        if (listProc.running) { reloadAgain = true; return; }
        listProc.buffer = [];
        listProc.running = true;
    }
    property bool reloadAgain: false

    Process {
        id: listProc
        property var buffer: []
        command: ["sh", panel.listScript, "60"]
        stdout: SplitParser {
            onRead: line => { try { listProc.buffer.push(JSON.parse(line)); } catch (e) {} }
        }
        onRunningChanged: if (!running) {
            panel.entries = listProc.buffer;
            panel.loaded = true;
            if (panel.reloadAgain) { panel.reloadAgain = false; panel.reload(); }
        }
    }
    // pick: put the entry back on the clipboard (the island's copy card confirms it)
    Process { id: pickProc }
    Process { id: editProc; onRunningChanged: if (!running) panel.reload() }
    function pick(entry) {
        if (!entry || pickProc.running) return;
        pickProc.command = ["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", entry.id];
        pickProc.running = true;
        dismissed();
    }
    function remove(entry) {
        if (!entry || editProc.running) return;
        // drop it from the view right away; the reload only confirms it
        panel.entries = panel.entries.filter(e => e.id !== entry.id);
        editProc.command = ["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete", "sh", entry.id];
        editProc.running = true;
    }
    function clearAll() {
        if (editProc.running) return;
        panel.entries = [];
        editProc.command = ["sh", "-c", "cliphist wipe; rm -f \"${XDG_RUNTIME_DIR:-/tmp}\"/astrax-island/cliphist/*"];
        editProc.running = true;
    }

    onOpenedChanged: if (opened) { search.text = ""; selectedIndex = 0; reload(); focusDelay.restart(); }
    Component.onCompleted: { appear.start(); reload(); if (opened) focusDelay.restart(); }
    Timer { id: focusDelay; interval: 80; onTriggered: if (panel.opened) navigation.forceActiveFocus() }

    function move(delta) {
        selectedIndex = Math.max(0, Math.min(shown.length - 1, selectedIndex + delta));
        const top = selectedIndex * rowHeight;
        const bottom = top + rowHeight;
        const currentTarget = rowScroll.running ? rowScroll.to : list.contentY;
        let target = currentTarget;
        if (top < currentTarget) target = top;
        else if (bottom > currentTarget + list.height) target = bottom - list.height;
        target = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), target));
        if (Math.abs(target - currentTarget) > 0.5) {
            rowScroll.stop();
            rowScroll.from = list.contentY;
            rowScroll.to = target;
            rowScroll.start();
        }
    }
    Item {
        id: navigation
        focus: true
        Keys.onPressed: event => panel.key(event)
    }
    function key(event) {
        if (event.key === Qt.Key_Escape) dismissed();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) pick(shown[selectedIndex]);
        else if (event.key === Qt.Key_Delete) remove(shown[selectedIndex]);
        else if (event.key === Qt.Key_Up) move(-1);
        else if (event.key === Qt.Key_Down) move(1);
        else if (event.key === Qt.Key_Tab) move(event.modifiers & Qt.ShiftModifier ? -1 : 1);
        else if (!search.activeFocus && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && event.text.length && event.text >= " ") {
            search.text += event.text;
            search.forceActiveFocus();
            search.cursorPosition = search.text.length;
        }
        else return;
        event.accepted = true;
    }

    // ---------------------------------------------------------------- Argon chrome
    readonly property color accent: "#b48cff"
    function tint(al) { return Qt.rgba(accent.r, accent.g, accent.b, al); }
    ArgonGlow { accent: panel.accent; reach: 130 }
    ArgonHeader {
        id: panelHeader
        glyph: "\uf0ea"; title: "Clipboard"; accent: panel.accent
        textFont: panel.textFont; iconFont: panel.iconFont
        leftGlyph: "\uf1f8"; leftLabel: "Clear all"; leftVisible: panel.entries.length > 0
        onLeftClicked: panel.clearAll()
        onCloseClicked: panel.dismissed()
    }
    ArgonBar {
        id: searchBox
        anchors.bottom: parent.bottom
        width: parent.width; accent: panel.accent
        iconFont: panel.iconFont; textFont: panel.textFont
        focused: search.activeFocus
        TextInput {
            id: search
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter; clip: true
            color: "#f5f5f7"; selectionColor: panel.accent
            cursorDelegate: Rectangle { width: 2; radius: 1; color: panel.accent }
            font.family: panel.textFont; font.pixelSize: 13
            onTextChanged: panel.selectedIndex = 0
            Keys.onPressed: event => panel.key(event)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Search…  ↵ to copy · Del to remove"; color: "#7c7c82"; visible: !search.text; font: search.font }
        }
    }
    ListView {
        id: list
        anchors.top: panelHeader.bottom; anchors.topMargin: 6
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: searchBox.top; anchors.bottomMargin: 8
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: panel.shown
        onDraggingChanged: if (dragging) rowScroll.stop()
        NumberAnimation {
            id: rowScroll
            target: list; property: "contentY"
            duration: 220; easing.type: Easing.OutCubic
        }
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: list.width; height: panel.rowHeight
            scale: rowMouse.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Rectangle {
                id: tile
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32; radius: 10
                color: panel.tint(0.14)
                Text {
                    anchors.centerIn: parent; visible: row.modelData.kind !== "image"
                    text: "󰦨"; color: panel.accent; font.family: panel.iconFont; font.pixelSize: 17
                }
                RoundedImage {
                    anchors.fill: parent; radius: 9
                    visible: row.modelData.kind === "image"
                    source: row.modelData.kind === "image" ? "file://" + row.modelData.thumb : ""
                }
            }
            Text {
                anchors.left: tile.right; anchors.leftMargin: 11
                anchors.right: delButton.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.kind === "image" ? "Image · " + (row.modelData.info || "") : row.modelData.text
                color: "#f5f5f7"; font.family: panel.textFont; font.pixelSize: 12; font.weight: Font.Medium
                elide: Text.ElideRight; maximumLineCount: 1
            }
            Rectangle {
                id: delButton
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                opacity: panel.selectedIndex === row.index || rowMouse.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                color: delArea.containsMouse ? "#55ffffff" : "#2affffff"
                Text { anchors.centerIn: parent; text: "×"; color: "#f5f5f7"; font.pixelSize: 16 }
                MouseArea { id: delArea; anchors.fill: parent; hoverEnabled: true; onClicked: panel.remove(row.modelData) }
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent; hoverEnabled: true
                z: -1
                onEntered: if (!rowScroll.running) panel.selectedIndex = row.index
                onClicked: panel.pick(row.modelData)
            }
        }
        Rectangle {
            id: selectionGlass
            parent: list.contentItem; z: 5
            visible: panel.shown.length > 0
            readonly property real destinationY: panel.selectedIndex * panel.rowHeight + 2
            x: 0
            y: destinationY
            width: list.width; height: panel.rowHeight - 4
            radius: 15; color: "transparent"; border.width: 1; border.color: panel.tint(0.38)
            // Animate within the viewport; let the shared scroll carry the selector at an edge.
            Behavior on y {
                enabled: !rowScroll.running
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            gradient: Gradient {
                GradientStop { position: 0; color: panel.tint(0.16) }
                GradientStop { position: 0.5; color: panel.tint(0.06) }
                GradientStop { position: 1; color: panel.tint(0.14) }
            }
            ShaderEffect {
                anchors.fill: parent
                visible: panel.glassEnabled && panel.glassTexture !== null && width > 1 && height > 1
                property var src: panel.glassTexture
                property real radius: selectionGlass.radius
                property real strength: panel.glassStrength
                property real band: 9
                property vector2d stretch: Qt.vector2d(1, 1)
                property vector2d size: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(panel.glassOrigin.x + list.x + selectionGlass.x,
                    panel.glassOrigin.y + list.y + selectionGlass.y - list.contentY)
                property vector2d screen: panel.glassScreen
                fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
            }
        }
        Text {
            anchors.centerIn: parent; visible: !panel.shown.length
            text: !panel.loaded ? "" : search.text ? "No results" : "Clipboard is empty"
            color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 12
        }
    }
}
