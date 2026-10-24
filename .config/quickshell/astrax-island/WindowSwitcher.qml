import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: switcher
    property bool opened: false
    property string monitorName: ""
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.5
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property string textFont: "Rubik"
    property var groups: []
    property int selectedIndex: 0
    property bool selectionReady: false
    property int lastSelection: 0
    property bool stretchHorizontal: false
    property bool stretchVertical: false
    onSelectedIndexChanged: {
        if (opened && selectionReady && selectedIndex !== lastSelection) {
            stretchHorizontal = selectedIndex % columns !== lastSelection % columns;
            stretchVertical = Math.floor(selectedIndex/columns) !== Math.floor(lastSelection/columns);
            stretchEnd.restart();
        }
        lastSelection = selectedIndex;
    }
    Timer { id: stretchReady; interval: 0; onTriggered: { switcher.lastSelection = switcher.selectedIndex; switcher.selectionReady = true; } }
    Timer { id: stretchEnd; interval: 260; onTriggered: { switcher.stretchHorizontal = false; switcher.stretchVertical = false; } }
    signal dismissed()
    readonly property var ignored: ["widget-clock", "widget-clock-ghost", "widget-lavat", "widget4-unimatrix", "widget4-lavat", "widget5-unimatrix", "widget5-lavat"]
    readonly property var rawGroups: {
        if (!opened) return [];
        const result = [];
        const workspaces = Hyprland.workspaces.values.filter(ws => ws.monitor && ws.monitor.name === monitorName);
        const first = workspaces.length ? Math.min(...workspaces.map(ws => ws.id)) : 0;
        for (const ws of workspaces) {
            if (!ws.toplevels || !ws.toplevels.values) continue;
            const windows = [];
            for (const tl of ws.toplevels.values) {
                const cls = tl.wayland ? tl.wayland.appId || "" : "";
                if (ignored.indexOf(cls) >= 0) continue;
                const entry = DesktopEntries.heuristicLookup(cls);
                windows.push({address: tl.address, toplevel: tl, cls: cls, title: tl.title || cls,
                              icon: entry ? entry.icon : cls, active: !!tl.activated});
            }
            if (windows.length) result.push({wsId: ws.id, localWs: ws.id-first+1,
                address: (windows.find(w => w.active) || windows[0]).address, windows: windows,
                title: windows.length === 1 ? windows[0].title : windows.length + " windows"});
        }
        return result;
    }
    readonly property var filtered: groups.filter(g => !search.text || g.windows.some(w =>
        (w.title+" "+w.cls).toLowerCase().indexOf(search.text.toLowerCase()) >= 0))
    onRawGroupsChanged: settle.restart()
    onFilteredChanged: selectedIndex = Math.min(selectedIndex, Math.max(0, filtered.length-1))
    onOpenedChanged: {
        if (opened) { selectionReady = false; stretchHorizontal = false; stretchVertical = false; search.text = ""; selectedIndex = 0; stretchReady.restart(); settle.restart(); focusDelay.restart(); }
        else { settle.stop(); groups = []; }
    }
    Component.onCompleted: { stretchReady.restart(); if (opened) focusDelay.restart(); }
    Timer { id: settle; interval: 100; onTriggered: switcher.groups = switcher.rawGroups }
    Timer { id: focusDelay; interval: 80; onTriggered: if (switcher.opened) search.forceActiveFocus() }
    function move(delta) {
        selectedIndex = Math.max(0, Math.min(filtered.length-1, selectedIndex+delta));
        // Reveal the next row with one interruptible scroll, rather than an instant jump.
        const top = Math.floor(selectedIndex / columns) * cards.cellHeight;
        const bottom = top + cards.cellHeight;
        const currentTarget = rowScroll.running ? rowScroll.to : cards.contentY;
        let target = currentTarget;
        if (top < currentTarget) target = top;
        else if (bottom > currentTarget + cards.height) target = bottom - cards.height;
        target = Math.max(0, Math.min(Math.max(0, cards.contentHeight - cards.height), target));
        if (Math.abs(target - currentTarget) > 0.5) {
            rowScroll.stop();
            rowScroll.from = cards.contentY;
            rowScroll.to = target;
            rowScroll.start();
        }
    }
    function address(value) { return "0x" + String(value).replace(/^0x/, ""); }
    function activate(group, window) {
        if (!group) return;
        const target = window || group.windows.find(w => w.address === group.address) || group.windows[0];
        Hyprland.dispatch('hl.dsp.focus({ workspace = '+group.wsId+' })');
        Hyprland.dispatch('hl.dsp.focus({ window = "address:'+address(target.address)+'" })');
        dismissed();
    }
    function closeWindow(window) {
        if (!window) return;
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:'+address(window.address)+'" })');
        focusDelay.restart();
    }
    function key(event) {
        if (event.key === Qt.Key_Escape) dismissed();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activate(filtered[selectedIndex]);
        else if (event.key === Qt.Key_Left && !search.text) move(-1);
        else if (event.key === Qt.Key_Right && !search.text) move(1);
        else if (event.key === Qt.Key_Up) move(-switcher.columns);
        else if (event.key === Qt.Key_Down) move(switcher.columns);
        else if (event.key === Qt.Key_Tab) move(event.modifiers & Qt.ShiftModifier ? -1 : 1);
        else return;
        event.accepted = true;
    }
    Text {
        text: "Windows"; color: "#f5f5f7"
        font.family: switcher.textFont; font.pixelSize: 21; font.weight: Font.DemiBold
    }
    Rectangle {
        anchors.right: parent.right; width: 25; height: 25; radius: 12.5
        color: closeArea.containsMouse ? "#444448" : "#29292c"
        Text { anchors.centerIn: parent; text: "×"; color: "#d1d1d6"; font.pixelSize: 19 }
        MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: switcher.dismissed() }
    }
    Rectangle {
        id: searchBox
        y: 39; width: parent.width; height: 32; radius: 11
        color: "#20ffffff"; border.width: 1; border.color: "#14ffffff"
        TextInput {
            id: search
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter; clip: true
            color: "#f5f5f7"; selectionColor: "#0a84ff"
            font.family: switcher.textFont; font.pixelSize: 12
            onTextChanged: switcher.selectedIndex = 0
            Keys.onPressed: event => switcher.key(event)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Search windows…"; color: "#98989d"; visible: !search.text; font: search.font }
        }
    }
    GridView {
        id: cards
        anchors.top: searchBox.bottom; anchors.topMargin: 12
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: footer.top; anchors.bottomMargin: 8
        clip: true; cellWidth: width/switcher.columns; cellHeight: 116
        boundsBehavior: Flickable.StopAtBounds
        model: switcher.filtered
        onDraggingChanged: if (dragging) rowScroll.stop()
        NumberAnimation {
            id: rowScroll
            target: cards; property: "contentY"
            duration: 220; easing.type: Easing.OutCubic
        }
        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool selected: index === switcher.selectedIndex
            width: cards.cellWidth; height: cards.cellHeight
            Rectangle {
                anchors.fill: parent; anchors.margins: 4; radius: 16
                color: card.selected ? "#14303034" : "#1c1c1e"
                border.width: 1
                border.color: "#18ffffff"
                Behavior on color { ColorAnimation { duration: 130 } }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: if (!rowScroll.running) switcher.selectedIndex = card.index
                    onClicked: switcher.activate(card.modelData)
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 12; spacing: 7
                    opacity: card.selected ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                    Repeater {
                        model: card.modelData.windows.slice(0,4)
                        delegate: AppIcon {
                            appleStyle: true
                            required property var modelData
                            size: 31; app: modelData.cls; icon: modelData.icon
                        }
                    }
                }
                Grid {
                    x: 9; y: 8; width: parent.width-18; height: 60
                    columns: Math.min(2,card.modelData.windows.length); spacing: 4
                    opacity: card.selected ? 1 : 0
                    scale: card.selected ? 1 : 0.97
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Repeater {
                        model: card.selected && switcher.opened ? card.modelData.windows.slice(0,4) : []
                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width-(parent.columns-1)*4)/parent.columns
                            height: card.modelData.windows.length > 2 ? 28 : 60
                            radius: 6; color: "#101012"; clip: true
                            ScreencopyView {
                                id: preview
                                anchors.fill: parent
                                captureSource: switcher.opened && card.selected && modelData.toplevel ? modelData.toplevel.wayland : null
                                live: switcher.opened && card.selected; paintCursor: false
                            }
                            AppIcon { appleStyle: true; anchors.centerIn: parent; size: 22; app: modelData.cls; icon: modelData.icon; visible: !preview.hasContent }
                            MouseArea { anchors.fill: parent; onClicked: switcher.activate(card.modelData, modelData) }
                            Rectangle {
                                anchors.right: parent.right; width: 17; height: 17; radius: 8.5; color: "#cc303034"
                                Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 13 }
                                MouseArea { anchors.fill: parent; onClicked: switcher.closeWindow(modelData) }
                            }
                        }
                    }
                }
                Text {
                    x: 10; y: 73; width: parent.width-20
                    text: card.modelData.title; elide: Text.ElideRight
                    color: "#f5f5f7"; font.family: switcher.textFont; font.pixelSize: 11; font.weight: Font.Medium
                }
                Text {
                    x: 10; y: 89; text: "Desktop " + card.modelData.localWs
                    color: "#98989d"; font.family: switcher.textFont; font.pixelSize: 10
                }
            }
        }
        // One shared outline travels between slots rather than being rebuilt
        // on each delegate. Motion retargets immediately during quick key repeats.
        Rectangle {
            id: selectionGlass
            parent: cards.contentItem; z: 5
            visible: switcher.filtered.length > 0
            readonly property real destinationX: (switcher.selectedIndex % switcher.columns)*cards.cellWidth+4
            readonly property real destinationY: Math.floor(switcher.selectedIndex/switcher.columns)*cards.cellHeight+4
            x: destinationX
            y: destinationY
            // Stretch follows the existing positional animation; at rest it is exactly 1.
            property real elasticX: 1 + (switcher.stretchHorizontal && selectorMoveX.running ? Math.min(0.24, Math.abs(destinationX-x) / Math.max(1, width) * 0.26) : 0)
            property real elasticY: 1 + (switcher.stretchVertical && selectorMoveY.running ? Math.min(0.24, Math.abs(destinationY-y) / Math.max(1, height) * 0.26) : 0)
            Behavior on elasticX { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on elasticY { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            transform: Scale {
                origin.x: selectionGlass.width/2; origin.y: selectionGlass.height/2
                xScale: selectionGlass.elasticX; yScale: selectionGlass.elasticY
            }
            width: Math.max(0, cards.cellWidth-8); height: cards.cellHeight-8
            radius: 16; color: "transparent"; border.width: 1; border.color: "#70ffffff"
            Behavior on x { NumberAnimation { id: selectorMoveX; duration: 200; easing.type: Easing.OutCubic } }
            // Animate within the viewport; let the shared scroll carry the selector at an edge.
            Behavior on y {
                enabled: !rowScroll.running
                NumberAnimation { id: selectorMoveY; duration: 220; easing.type: Easing.OutCubic }
            }
            gradient: Gradient {
                GradientStop { position: 0; color: "#28ffffff" }
                GradientStop { position: 0.45; color: "#08ffffff" }
                GradientStop { position: 1; color: "#16ffffff" }
            }
            ShaderEffect {
                anchors.fill: parent
                visible: switcher.glassEnabled && switcher.glassTexture !== null && width > 1 && height > 1
                property var src: switcher.glassTexture
                property real radius: selectionGlass.radius
                property real strength: switcher.glassStrength
                property real band: 9
                property vector2d stretch: Qt.vector2d(selectionGlass.elasticX, selectionGlass.elasticY)
                property vector2d size: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(switcher.glassOrigin.x + cards.x + selectionGlass.x,
                    switcher.glassOrigin.y + cards.y + selectionGlass.y - cards.contentY)
                property vector2d screen: switcher.glassScreen
                fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
            }
            // Follow the animated panel geometry directly: a second width tween starts as a thin sliver.
        }
        Text {
            anchors.centerIn: parent
            visible: switcher.filtered.length === 0
            text: search.text ? "No results" : "No windows on this display"
            color: "#98989d"; font.family: switcher.textFont; font.pixelSize: 12
        }
    }
    Text {
        id: footer
        anchors.bottom: parent.bottom
        text: "↑↓ Select · ↵ Open · esc Close"
        color: "#98989d"; font.family: switcher.textFont; font.pixelSize: 10
    }
}
