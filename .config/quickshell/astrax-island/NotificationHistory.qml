import QtQuick
import Quickshell

// Notification history inside the island. Same chrome as the clipboard panel (Super+V): title, search,
// a scrolling list with a Liquid Glass selector, and a hint line. The host owns the data and the actions.
Item {
    id: panel
    property bool opened: false
    property var items: []
    property var timeAgo: ts => ""
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.5
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    // Argon look: black body, flat near-black surfaces, one soft accent
    readonly property color accent: "#ff7a7a"
    signal dismissed()
    signal activated(var item)
    signal removed(var item)
    signal clearRequested()

    opacity: 0
    scale: 0.98
    transformOrigin: Item.Top
    ParallelAnimation {
        id: appear
        NumberAnimation { target: panel; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: panel; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }

    readonly property int rowHeight: 52
    property int selectedIndex: 0
    readonly property var shown: {
        const q = search.text.trim().toLowerCase();
        if (!q) return items;
        return items.filter(e => ((e.summary || "") + " " + (e.body || "") + " " + (e.app || "")).toLowerCase().includes(q));
    }
    onShownChanged: selectedIndex = Math.max(0, Math.min(selectedIndex, shown.length - 1))

    onOpenedChanged: if (opened) { search.text = ""; selectedIndex = 0; focusDelay.restart(); }
    Component.onCompleted: { appear.start(); if (opened) focusDelay.restart(); }
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
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (shown[selectedIndex]) activated(shown[selectedIndex]); }
        else if (event.key === Qt.Key_Delete) { if (shown[selectedIndex]) removed(shown[selectedIndex]); }
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
    function tint(al) { return Qt.rgba(accent.r, accent.g, accent.b, al); }
    ArgonGlow { accent: panel.accent; reach: 130 }
    ArgonHeader {
        id: panelHeader
        glyph: "\uf0f3"; title: "Notifications"; accent: panel.accent
        textFont: panel.textFont; iconFont: panel.iconFont
        leftGlyph: "\uf1f8"; leftLabel: "Clear all"; leftVisible: panel.items.length > 0
        onLeftClicked: panel.clearRequested()
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
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Search…  ↵ to open · Del to remove"; color: "#7c7c82"; visible: !search.text; font: search.font }
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
        remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 140 } }
        displaced: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool isEv: modelData.kind === "event"
            width: list.width; height: panel.rowHeight
            scale: rowMouse.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Item {
                id: tile
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34
                AppIcon {
                    anchors.fill: parent
                    visible: !row.isEv
                    size: 34
                    app: row.modelData.app || ""
                    entry: row.modelData.entry || ""
                    icon: row.modelData.icon || ""
                    image: row.modelData.image || ""
                }
                Rectangle {
                    anchors.fill: parent
                    visible: row.isEv
                    radius: 17
                    color: Qt.rgba(Qt.color(row.modelData.accent || "#ffffff").r, Qt.color(row.modelData.accent || "#ffffff").g,
                                   Qt.color(row.modelData.accent || "#ffffff").b, 0.2)
                    Text {
                        anchors.centerIn: parent
                        visible: !row.modelData.thumb
                        text: row.modelData.glyph || ""
                        color: row.modelData.accent || "#ffffff"
                        font.family: panel.iconFont; font.pixelSize: 17
                    }
                    RoundedImage {
                        anchors.fill: parent; radius: 10
                        visible: row.modelData.thumb ? true : false
                        source: row.modelData.thumb || ""
                    }
                }
            }
            Rectangle {   // unread dot
                visible: !row.isEv && row.modelData.read === false
                x: tile.x + tile.width - 7; y: tile.y - 3
                width: 9; height: 9; radius: 4.5; color: panel.accent
                border.width: 2; border.color: "#000000"
            }
            Column {
                anchors.left: tile.right; anchors.leftMargin: 11
                anchors.right: stamp.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.summary || row.modelData.app
                    color: "#f5f5f7"; font.family: panel.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: (row.modelData.body || row.modelData.app || "").replace(/<[^>]*>/g, "").replace(/\n/g, " ")
                    color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 11
                }
            }
            // time on the right; on hover it hands the spot to the remove button
            Item {
                id: stamp
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 22
                readonly property bool hot: panel.selectedIndex === row.index || rowMouse.containsMouse
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: panel.timeAgo(row.modelData.ts)
                    color: "#98989d"; font.family: panel.textFont; font.pixelSize: 11; font.weight: Font.Medium
                    opacity: stamp.hot ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11
                    opacity: stamp.hot ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    color: delArea.containsMouse ? "#55ffffff" : "#2affffff"
                    Text { anchors.centerIn: parent; text: "×"; color: "#f5f5f7"; font.pixelSize: 16 }
                    MouseArea { id: delArea; anchors.fill: parent; hoverEnabled: true; onClicked: panel.removed(row.modelData) }
                }
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent; hoverEnabled: true
                z: -1
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: if (!rowScroll.running) panel.selectedIndex = row.index
                onClicked: m => { if (m.button === Qt.RightButton) panel.removed(row.modelData); else panel.activated(row.modelData); }
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
            text: search.text ? "No results" : "Nothing here"
            color: "#98989d"; font.family: panel.textFont; font.pixelSize: 12
        }
    }
}
