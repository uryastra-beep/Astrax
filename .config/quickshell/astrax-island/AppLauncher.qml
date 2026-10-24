import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: launcher
    property bool opened: false
    opacity: 0
    scale: 0.98
    transformOrigin: Item.Top
    ParallelAnimation {
        id: appear
        NumberAnimation { target: launcher; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: launcher; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.5
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property string textFont: "Rubik"
    property var pinned: []
    property var usage: ({})
    property var dockPins: []
    property string dockMenuApp: ""
    property point dockMenuPosition: Qt.point(0, 0)
    FileView {
        path: Quickshell.env("HOME") + "/.config/serpantinum/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { const data = JSON.parse(text()); launcher.dockPins = (data.macDock || {}).apps || []; }
            catch(e) {}
        }
    }
    Process { id: dockAdder; command: [] }
    function addMenuAppToDock() {
        const appId = dockMenuApp;
        dockMenuApp = "";
        if (!appId || dockAdder.running) return;
        dockAdder.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/astrax-mac-dock/control.py", "add", appId];
        dockAdder.running = true;
    }

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
    Timer { id: stretchReady; interval: 0; onTriggered: { launcher.lastSelection = launcher.selectedIndex; launcher.selectionReady = true; } }
    Timer { id: stretchEnd; interval: 260; onTriggered: { launcher.stretchHorizontal = false; launcher.stretchVertical = false; } }
    signal dismissed()
    signal launchRequested(string appId)
    signal pinRequested(string appId)
    readonly property int columns: Math.min(5, Math.max(1, apps.length))
    readonly property int preferredHeight: 150 + Math.min(3, Math.max(1, Math.ceil(apps.length / columns))) * 82
    readonly property var apps: {
        const query = search.text.trim().toLowerCase();
        const result = DesktopEntries.applications.values.filter(app => app && !app.noDisplay
            && (!query || ((app.name || "")+" "+(app.genericName || "")+" "+(app.comment || "")).toLowerCase().includes(query)));
        const rank = app => { const i = pinned.indexOf(app.id); return i < 0 ? 1e9 : i; };
        result.sort((a,b) => rank(a)-rank(b) || (usage[b.id] || 0)-(usage[a.id] || 0) || (a.name || "").localeCompare(b.name || ""));
        return result;
    }
    onAppsChanged: selectedIndex = Math.max(0, Math.min(selectedIndex, apps.length-1))
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/astrax-launcher/pinned.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { launcher.pinned = JSON.parse(text()); } catch(e) {} }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/astrax-launcher/usage.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { launcher.usage = JSON.parse(text()); } catch(e) {} }
    }
    onOpenedChanged: { dockMenuApp = ""; if (opened) { selectionReady = false; stretchHorizontal = false; stretchVertical = false; search.text = ""; selectedIndex = 0; stretchReady.restart(); focusDelay.restart(); } }
    Component.onCompleted: { appear.start(); stretchReady.restart(); if (opened) focusDelay.restart(); }
    Timer { id: focusDelay; interval: 80; onTriggered: if (launcher.opened) navigation.forceActiveFocus() }
    function move(delta) {
        selectedIndex = Math.max(0, Math.min(apps.length-1, selectedIndex+delta));
        // Reveal the next row with one interruptible scroll, rather than an instant jump.
        const top = Math.floor(selectedIndex / columns) * grid.cellHeight;
        const bottom = top + grid.cellHeight;
        const currentTarget = rowScroll.running ? rowScroll.to : grid.contentY;
        let target = currentTarget;
        if (top < currentTarget) target = top;
        else if (bottom > currentTarget + grid.height) target = bottom - grid.height;
        target = Math.max(0, Math.min(Math.max(0, grid.contentHeight - grid.height), target));
        if (Math.abs(target - currentTarget) > 0.5) {
            rowScroll.stop();
            rowScroll.from = grid.contentY;
            rowScroll.to = target;
            rowScroll.start();
        }
    }
    Item {
        id: navigation
        focus: true
        Keys.onPressed: event => launcher.key(event)
    }
    function key(event) {
        if (dockMenuApp !== "") {
            dockMenuApp = "";
            if (event.key === Qt.Key_Escape) { event.accepted = true; return; }
        }
        const navigating = !search.activeFocus;
        const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
        if (navigating && plain && (event.key === Qt.Key_W || event.key === Qt.Key_A || event.key === Qt.Key_S || event.key === Qt.Key_D)) {
            move(event.key === Qt.Key_W ? -columns : event.key === Qt.Key_S ? columns : event.key === Qt.Key_A ? -1 : 1);
            event.accepted = true;
            return;
        }
        if (navigating && event.key === Qt.Key_Shift) {
            if (!event.isAutoRepeat && apps[selectedIndex]) launchRequested(apps[selectedIndex].id);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
            search.forceActiveFocus(); search.selectAll(); event.accepted = true; return;
        }
        if (event.key === Qt.Key_Escape && search.activeFocus) { navigation.forceActiveFocus(); event.accepted = true; return; }
        if (event.key === Qt.Key_Escape) dismissed();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (apps[selectedIndex]) launchRequested(apps[selectedIndex].id); }
        else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) { if (apps[selectedIndex]) pinRequested(apps[selectedIndex].id); }
        else if (event.key === Qt.Key_Left && !search.text) move(-1);
        else if (event.key === Qt.Key_Right && !search.text) move(1);
        else if (event.key === Qt.Key_Up) move(-columns);
        else if (event.key === Qt.Key_Down) move(columns);
        else if (event.key === Qt.Key_Tab) move(event.modifiers & Qt.ShiftModifier ? -1 : 1);
        else if (navigating && plain && event.text.length && event.text >= " ") {
            search.text += event.text;
            search.forceActiveFocus();
            search.cursorPosition = search.text.length;
        }
        else return;
        event.accepted = true;
    }
    Text { text: "Apps"; color: "#f5f5f7"; font.family: launcher.textFont; font.pixelSize: 21; font.weight: Font.DemiBold }
    Rectangle {
        anchors.right: parent.right; width: 25; height: 25; radius: 12.5; color: "#29292c"
        Text { anchors.centerIn: parent; text: "×"; color: "#d1d1d6"; font.pixelSize: 19 }
        MouseArea { anchors.fill: parent; onClicked: launcher.dismissed() }
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
            font.family: launcher.textFont; font.pixelSize: 12
            onTextChanged: { launcher.selectedIndex = 0; launcher.dockMenuApp = ""; }
            Keys.onPressed: event => launcher.key(event)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Search apps…"; color: "#98989d"; visible: !search.text; font: search.font }
        }
    }
    GridView {
        id: grid
        anchors.top: searchBox.bottom; anchors.topMargin: 12
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: footer.top; anchors.bottomMargin: 8
        cellWidth: width/launcher.columns; cellHeight: 82
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: launcher.apps
        onDraggingChanged: if (dragging) rowScroll.stop()
        NumberAnimation {
            id: rowScroll
            target: grid; property: "contentY"
            duration: 220; easing.type: Easing.OutCubic
        }
        delegate: Item {
            id: tile
            required property var modelData
            required property int index
            width: grid.cellWidth; height: grid.cellHeight
            scale: tileMouse.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            AppIcon { appleStyle: true; anchors.horizontalCenter: parent.horizontalCenter; y: 9; size: 34; app: tile.modelData.name; entry: tile.modelData.id; icon: tile.modelData.icon }
            Text {
                x: 6; y: 48; width: parent.width-12
                text: tile.modelData.name || ""
                color: "#f5f5f7"; font.family: launcher.textFont; font.pixelSize: 11; font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            Rectangle { anchors.right: parent.right; anchors.rightMargin: 12; y: 11; width: 5; height: 5; radius: 2.5; color: "#0a84ff"; visible: launcher.pinned.indexOf(tile.modelData.id) >= 0 }
            MouseArea {
                id: tileMouse
                anchors.fill: parent; hoverEnabled: true
                onEntered: if (!rowScroll.running) launcher.selectedIndex = tile.index
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        const point = tile.mapToItem(launcher, mouse.x, mouse.y);
                        launcher.dockMenuPosition = Qt.point(Math.max(0, Math.min(launcher.width - 180, point.x)),
                            Math.max(0, Math.min(launcher.height - 44, point.y)));
                        launcher.dockMenuApp = tile.modelData.id;
                    } else launcher.launchRequested(tile.modelData.id);
                }
            }
        }
        Rectangle {
            id: selectionGlass
            parent: grid.contentItem; z: 5
            visible: launcher.apps.length > 0
            readonly property real destinationX: (launcher.selectedIndex % launcher.columns)*grid.cellWidth+4
            readonly property real destinationY: Math.floor(launcher.selectedIndex/launcher.columns)*grid.cellHeight+4
            x: destinationX
            y: destinationY
            // Stretch follows the existing positional animation; at rest it is exactly 1.
            property real elasticX: 1 + (launcher.stretchHorizontal && selectorMoveX.running ? Math.min(0.24, Math.abs(destinationX-x) / Math.max(1, width) * 0.26) : 0)
            property real elasticY: 1 + (launcher.stretchVertical && selectorMoveY.running ? Math.min(0.24, Math.abs(destinationY-y) / Math.max(1, height) * 0.26) : 0)
            Behavior on elasticX { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on elasticY { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            transform: Scale {
                origin.x: selectionGlass.width/2; origin.y: selectionGlass.height/2
                xScale: selectionGlass.elasticX; yScale: selectionGlass.elasticY
            }
            width: Math.max(0, grid.cellWidth-8); height: grid.cellHeight-8
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
                visible: launcher.glassEnabled && launcher.glassTexture !== null && width > 1 && height > 1
                property var src: launcher.glassTexture
                property real radius: selectionGlass.radius
                property real strength: launcher.glassStrength
                property real band: 9
                property vector2d stretch: Qt.vector2d(selectionGlass.elasticX, selectionGlass.elasticY)
                property vector2d size: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(launcher.glassOrigin.x + grid.x + selectionGlass.x,
                    launcher.glassOrigin.y + grid.y + selectionGlass.y - grid.contentY)
                property vector2d screen: launcher.glassScreen
                fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
            }
            // Follow the animated panel geometry directly: a second width tween starts as a thin sliver.
        }
        Text { anchors.centerIn: parent; visible: !launcher.apps.length; text: "No apps found"; color: "#98989d"; font.family: launcher.textFont; font.pixelSize: 12 }
    }
    MouseArea {
        anchors.fill: parent; z: 90
        visible: launcher.dockMenuApp !== ""
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: launcher.dockMenuApp = ""
    }
    Rectangle {
        id: dockMenu
        z: 100
        x: launcher.dockMenuPosition.x; y: launcher.dockMenuPosition.y
        width: 180; height: 40; radius: 12
        opacity: launcher.dockMenuApp !== "" ? 1 : 0
        visible: opacity > 0
        scale: 0.96 + opacity * 0.04
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        color: launcher.glassEnabled ? "#b32a2a30" : "#f02a2a30"
        border.width: 1; border.color: "#50ffffff"
        readonly property bool alreadyPinned: launcher.dockPins.indexOf(launcher.dockMenuApp) >= 0
        ShaderEffect {
            anchors.fill: parent
            visible: launcher.glassEnabled && launcher.glassTexture !== null
            property var src: launcher.glassTexture
            property real radius: dockMenu.radius
            property real strength: launcher.glassStrength
            property real band: 9
            property vector2d stretch: Qt.vector2d(1, 1)
            property vector2d size: Qt.vector2d(width, height)
            property vector2d origin: Qt.vector2d(launcher.glassOrigin.x + dockMenu.x, launcher.glassOrigin.y + dockMenu.y)
            property vector2d screen: launcher.glassScreen
            fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: 4; radius: 8
            color: dockMenuMouse.containsMouse && !dockMenu.alreadyPinned ? "#0a84ff" : "transparent"
            Text {
                anchors.centerIn: parent
                text: dockMenu.alreadyPinned ? "Already in Dock" : "Add to Dock"
                color: dockMenu.alreadyPinned ? "#98989d" : "#f5f5f7"
                font.family: launcher.textFont; font.pixelSize: 12
            }
            MouseArea {
                id: dockMenuMouse
                anchors.fill: parent; hoverEnabled: true
                onClicked: { if (dockMenu.alreadyPinned) launcher.dockMenuApp = ""; else launcher.addMenuAppToDock(); }
            }
        }
    }
    Text { id: footer; anchors.bottom: parent.bottom; text: "WASD / Arrows Move · Shift / ↵ Open · Ctrl+L Search"; color: "#98989d"; font.family: launcher.textFont; font.pixelSize: 10 }
}
