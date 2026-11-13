import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "FileIcons.js" as FI

Item {
    id: shelf
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    property bool hoveringDrop: false
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.6
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property var items: []
    property string message: ""
    property var pending: []
    property string removingId: ""
    property var addedIds: []
    property var moveFrom: ({})
    readonly property int visibleRows: count >= 4 ? 2 : 1
    readonly property int preferredHeight: 206 + (visibleRows-1) * 118
    property int dropSlot: -1
    readonly property bool hasRoom: items.length < 8 || items.some(item => item.files.length < 4)
    readonly property bool busy: worker.running || removingId !== ""
    readonly property int count: items.length
    signal draggingOut(bool active)

    function removeAnimated(id) {
        if (shelf.busy || !id) return;
        shelf.removingId = id;
    }
    function request(op, values) {
        const q = pending.slice(); q.push([op].concat(values || [])); pending = q; launch();
    }
    function launch() {
        if (worker.running || !pending.length) return;
        const q = pending.slice(); const args = q.shift(); pending = q;
        worker.operation = args[0];
        worker.command = ["python", Quickshell.shellPath("shelf-store.py")].concat(args);
        worker.running = true;
    }
    function slotAt(x, y) {
        for (let i = 0; i < shelf.visibleRows * 4; ++i) {
            const tile = slots.itemAt(i);
            if (!tile) continue;
            const point = tile.mapFromItem(shelf, x, y);
            if (point.x >= 0 && point.y >= 0 && point.x < tile.width && point.y < tile.height) return i;
        }
        return -1;
    }
    function add(urls, slot) {
        const values = urls.map(u => u.toString());
        if (slot !== undefined && slot >= 0) request("add-to", [String(slot)].concat(values));
        else request("add", values);
    }
    Component.onCompleted: request("list", [])
    Process {
        id: worker
        property string operation: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(this.text);
                    if (r.items) {
                        const known = {};
                        shelf.items.forEach(item => known[item.id] = item.files.map(file => file.id).join(","));
                        shelf.addedIds = (worker.operation === "add" || worker.operation === "add-to")
                            ? r.items.filter(item => known[item.id] !== item.files.map(file => file.id).join(",")).map(item => item.id) : [];
                        const offsets = {};
                        for (const item of r.items) {
                            const previous = shelf.items.find(old => old.id === item.id);
                            if (previous && previous.slot !== item.slot) offsets[item.id] = previous.slot;
                        }
                        shelf.moveFrom = offsets;
                        shelf.items = r.items;
                    }
                    shelf.message = r.error ? r.message : (r.message || "");
                } catch(e) { shelf.message = "Could not read the shelf"; }
            }
        }
        onExited: {
            if (operation === "remove") shelf.removingId = "";
            Qt.callLater(shelf.launch);
        }
    }

    // ---------------------------------------------------------------- NotchPixel-style header
    // "Shelf · N files" on the left; save all to
    // Downloads, copy all as files, and clear on the right.
    readonly property color accent: "#8fe388"
    readonly property var allFiles: { const out = []; for (const it of items) for (const f of it.files) out.push(f); return out; }
    readonly property var allPaths: allFiles.map(f => decodeURIComponent(String(f.uri).replace(/^file:\/\//, "")))
    function colorFor(name, isDir) {
        if (isDir) return "#5ac8fa";
        const e = FI.ext(name);
        if (e === "pdf") return "#ff6b6b";
        if (["png","jpg","jpeg","gif","webp","svg","bmp","heic","avif"].indexOf(e) >= 0) return "#ffd60a";
        if (["mp4","mkv","mov","webm","avi","m4v"].indexOf(e) >= 0) return "#4aa3ff";
        if (["mp3","flac","wav","ogg","m4a","opus","aac"].indexOf(e) >= 0) return "#ff5f8f";
        if (["zip","rar","7z","tar","gz","xz","bz2","zst","iso"].indexOf(e) >= 0) return "#ffb340";
        if (["py","js","ts","qml","rs","c","cpp","h","sh","lua","json","html","css","java","go"].indexOf(e) >= 0) return "#bf8cff";
        if (["doc","docx","odt","txt","md","rtf","pptx","xlsx","csv","ods"].indexOf(e) >= 0) return "#64d2ff";
        return "#d1d1d6";
    }
    property string flash: ""
    Timer { id: flashClear; interval: 2400; onTriggered: shelf.flash = "" }
    function say(t) { flash = t; flashClear.restart(); }
    Process { id: shelfAction; onExited: code => { if (shelfAction.okText) shelf.say(code === 0 ? shelfAction.okText : "Something went wrong"); } property string okText: "" }
    function saveAll() {
        if (!allPaths.length || shelfAction.running) return;
        shelfAction.okText = "Saved to Downloads";
        shelfAction.command = ["sh", "-c", "d=\"$(xdg-user-dir DOWNLOAD 2>/dev/null || echo \"$HOME/Downloads\")\"; shift; cp -rn -- \"$@\" \"$d\"/", "sh", "x"].concat(allPaths);
        shelfAction.running = true;
    }
    function copyAll() {
        if (!allFiles.length || shelfAction.running) return;
        shelfAction.okText = "Copied, paste anywhere";
        shelfAction.command = ["sh", "-c", "printf '%s\\r\\n' \"$@\" | wl-copy -t text/uri-list", "sh"].concat(allFiles.map(f => String(f.uri)));
        shelfAction.running = true;
    }
    function clearAll() { for (const it of items) request("remove", [it.id]); }

    Item {
        id: panelHeader
        width: parent.width; height: 36
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text {
                text: shelf.hoveringDrop ? (shelf.hasRoom ? "Drop to save" : "Shelf full") : "Shelf"
                color: "#f5f5f7"; font.family: shelf.textFont; font.pixelSize: 18; font.weight: Font.DemiBold
            }
            Text {
                anchors.baseline: parent.children[0].baseline
                text: shelf.busy ? "· Saving…" : (shelf.flash || shelf.message)
                      ? "· " + (shelf.flash || shelf.message)
                      : "· " + shelf.allFiles.length + (shelf.allFiles.length === 1 ? " file" : " files")
                color: "#8e8e93"; font.family: shelf.textFont; font.pixelSize: 13
            }
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
                model: [
                    { g: "\uf019", tip: "Save all to Downloads", a: "save" },
                    { g: "\uf0c5", tip: "Copy all", a: "copy" },
                    { g: "\uf1f8", tip: "Clear shelf", a: "clear" }
                ]
                Rectangle {
                    required property var modelData
                    width: 32; height: 32; radius: 16
                    opacity: shelf.allFiles.length ? 1 : 0.4
                    color: actArea.containsMouse ? "#24ffffff" : "transparent"
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Text { anchors.centerIn: parent; text: modelData.g; color: "#e5e5ea"; font.family: shelf.iconFont; font.pixelSize: 14 }
                    MouseArea {
                        id: actArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        enabled: shelf.allFiles.length > 0 && !shelf.busy
                        onClicked: modelData.a === "save" ? shelf.saveAll() : modelData.a === "copy" ? shelf.copyAll() : shelf.clearAll()
                    }
                }
            }
        }
    }
    Grid {
        id: grid
        anchors.top: panelHeader.bottom; anchors.topMargin: 14
        columns: 4; spacing: 10
        Repeater {
            id: slots
            model: shelf.visibleRows * 4
            delegate: Rectangle {
                id: tile
                required property int index
                readonly property var entry: shelf.items.find(item => item.slot === index) || null
                onEntryChanged: {
                    if (entry && shelf.moveFrom[entry.id] !== undefined) {
                        const incomingId = entry.id;
                        const oldSlot = shelf.moveFrom[entry.id];
                        Qt.callLater(() => {
                            if (tile.entry && tile.entry.id === incomingId) {
                                arrivingFile.originShift = Qt.point((oldSlot % 4 - tile.index % 4) * (tile.width+10),
                                    (Math.floor(oldSlot/4)-Math.floor(tile.index/4))*118);
                                relocate.restart();
                            }
                        });
                    }
                    if (entry && shelf.addedIds.indexOf(entry.id) >= 0) {
                        const incomingId = entry.id;
                        Qt.callLater(() => {
                            if (tile.entry && tile.entry.id === incomingId) arrival.restart();
                        });
                    }
                }
                readonly property bool isShelfFile: true
                readonly property bool removing: entry !== null && shelf.removingId === entry.id
                onRemovingChanged: {
                    if (removing) { contentReturn.stop(); removalFade.restart(); }
                    else { removalFade.stop(); contentReturn.restart(); }
                }
                width: (shelf.width - 30) / 4; height: 108; radius: 18
                color: "transparent"
                readonly property int emptyDistance: Math.max(0, index-shelf.count)
                layer.enabled: shelf.visible && tile.entry === null && tile.emptyDistance > 0
                layer.smooth: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 12
                    autoPaddingEnabled: true
                    blur: shelf.hoveringDrop && shelf.dropSlot === tile.index ? 0
                        : tile.emptyDistance === 1 ? 0.2 : tile.emptyDistance === 2 ? 0.45 : 0.75
                    Behavior on blur { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
                readonly property real emptyOpacity: Math.max(0, index-shelf.count) === 0 ? 1 : index-shelf.count === 1 ? 0.42 : index-shelf.count === 2 ? 0.18 : 0.055
                Item {
                    // Material belongs to the slot, not to its empty state.
                    // File content can fade independently while this stays put.
                    anchors.fill: parent
                    opacity: tile.entry !== null ? (shelf.hoveringDrop && shelf.dropSlot === tile.index ? 1 : 0) : tile.emptyOpacity
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.fill: parent; radius: 18
                        color: "#100e0e12"
                    }
                    ShaderEffect {
                        anchors.fill: parent
                        visible: shelf.glassEnabled && shelf.glassTexture !== null && width > 1 && height > 1
                        property var src: shelf.glassTexture
                        property real radius: 18
                        property real strength: shelf.glassStrength
                        property real band: 11
                        property vector2d stretch: Qt.vector2d(1, 1)
                        property vector2d size: Qt.vector2d(width, height)
                        property point localOrigin: {
                            grid.x; grid.y; grid.contentX; grid.contentY; shelf.width; shelf.height; tile.x; tile.y;
                            return tile.mapToItem(shelf, 0, 0);
                        }
                        property vector2d origin: Qt.vector2d(shelf.glassOrigin.x + localOrigin.x,
                            shelf.glassOrigin.y + localOrigin.y)
                        property vector2d screen: shelf.glassScreen
                        fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
                    }
                    Rectangle {
                        anchors.fill: parent; radius: 18
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#25ffffff" }
                            GradientStop { position: 0.46; color: "#08ffffff" }
                            GradientStop { position: 1; color: "#17ffffff" }
                        }
                        border.width: 1; border.color: "#65ffffff"
                    }
                }
                Item {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    visible: tile.entry === null
                    opacity: tile.emptyOpacity
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Rectangle { anchors.centerIn: parent; width: 18; height: 1.5; radius: 0.75; color: "#f5f5f7" }
                    Rectangle { anchors.centerIn: parent; width: 1.5; height: 18; radius: 0.75; color: "#f5f5f7" }
                }
                Item {
                    id: dragProxy
                    width: 1; height: 1
                    readonly property bool isShelfFile: true
                    Drag.active: pick.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.proposedAction: Qt.CopyAction
                    Drag.source: dragProxy
                    Drag.mimeData: tile.entry ? {"text/uri-list": tile.entry.files.map(file => file.uri).join("\r\n") + "\r\n"} : ({})
                    Drag.onDragStarted: {
                        shelf.draggingOut(true);
                    }
                    Drag.onDragFinished: {
                        x = 0; y = 0; shelf.draggingOut(false);
                    }
                }
                MouseArea {
                    id: pick
                    anchors.fill: parent
                    enabled: tile.entry !== null && !shelf.busy
                    drag.target: dragProxy
                    cursorShape: Qt.OpenHandCursor
                    onPressed: tile.grabToImage(result => { dragProxy.Drag.imageSource = result.url; })
                }
                Item {
                    id: fileContent
                    anchors.fill: parent
                    opacity: 1
                    // Standalone animation: its completion commits the removal.
                    // Behavior child animations do not provide that lifecycle.
                    NumberAnimation {
                        id: removalFade
                        target: fileContent; property: "opacity"; to: 0
                        duration: 280; easing.type: Easing.InOutCubic
                        onFinished: {
                            if (tile.removing && tile.entry)
                                shelf.request("remove", [tile.entry.id]);
                        }
                    }
                    NumberAnimation {
                        id: contentReturn
                        target: fileContent; property: "opacity"; to: 1
                        duration: 180; easing.type: Easing.InOutCubic
                    }
                    Item {
                        id: arrivingFile
                        anchors.fill: parent
                        property real progress: 1
                        property real relocation: 1
                        property point originShift: Qt.point(0, 0)
                        SequentialAnimation {
                            id: relocate
                            PropertyAction { target: arrivingFile; property: "relocation"; value: 0 }
                            NumberAnimation { target: arrivingFile; property: "relocation"; to: 1; duration: 280; easing.type: Easing.InOutCubic }
                        }
                        opacity: progress
                        scale: 0.96 + 0.04 * progress
                        transformOrigin: Item.Center
                        transform: Translate {
                            x: (1-arrivingFile.relocation) * arrivingFile.originShift.x
                            y: (1-arrivingFile.progress)*7 + (1-arrivingFile.relocation) * arrivingFile.originShift.y
                        }
                        SequentialAnimation {
                            id: arrival
                            PropertyAction { target: arrivingFile; property: "progress"; value: 0 }
                            NumberAnimation {
                                target: arrivingFile; property: "progress"; to: 1
                                duration: 260; easing.type: Easing.OutCubic
                            }
                        }
                        Image {
                            x: (parent.width - 50) / 2; y: 4; width: 50; height: 50
                            source: tile.entry && !tile.entry.files[0].isDir && /\.(png|jpg|jpeg|webp|gif)$/i.test(tile.entry.name) ? tile.entry.uri : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: tile.entry !== null && tile.entry.files.length === 1 && status === Image.Ready
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 2
                            text: tile.entry ? FI.glyphFor(tile.entry.name, tile.entry.files[0].isDir === true) : ""
                            visible: tile.entry !== null && tile.entry.files.length === 1 && (tile.entry.files[0].isDir === true || !/\.(png|jpg|jpeg|webp|gif)$/i.test(tile.entry.name))
                            color: tile.entry ? shelf.colorFor(tile.entry.name, tile.entry.files[0].isDir === true) : "#48484a"
                            font.family: tile.entry ? shelf.iconFont : shelf.textFont; font.pixelSize: 46
                        }
                        Grid {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8; columns: 2; spacing: 3
                            visible: tile.entry !== null && tile.entry.files.length > 1
                            Repeater {
                                model: tile.entry && tile.entry.files.length > 1 ? tile.entry.files : []
                                delegate: Item {
                                    required property var modelData
                                    width: 25; height: 25
                                    Image {
                                        id: groupThumb
                                        anchors.fill: parent
                                        source: !modelData.isDir && /\.(png|jpg|jpeg|webp|gif)$/i.test(modelData.name) ? modelData.uri : ""
                                        fillMode: Image.PreserveAspectCrop
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: groupThumb.status !== Image.Ready
                                        text: FI.glyphFor(modelData.name, modelData.isDir === true)
                                        color: shelf.colorFor(modelData.name, modelData.isDir === true)
                                        font.family: shelf.iconFont; font.pixelSize: 22
                                    }
                                }
                            }
                        }
                        Text {
                            x: 6; y: 60; width: parent.width - 12
                            text: tile.entry ? tile.entry.name : ""
                            elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter
                            color: tile.entry ? "#f5f5f7" : "#636366"
                            font.family: shelf.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 82
                            text: tile.entry && tile.entry.files.length > 1 ? "Copy " + tile.entry.files.length : tile.entry && tile.entry.files[0].isDir ? "Copy folder" : "Copy"; visible: tile.entry !== null
                            color: shelf.accent; font.family: shelf.textFont; font.pixelSize: 11
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                enabled: !shelf.busy
                                onClicked: shelf.request("copy", [tile.entry.id])
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: -6
                            y: -6; width: 24; height: 24; radius: 12; z: 2
                            visible: tile.entry !== null
                            color: "#ffffff"
                            Rectangle {
                                anchors.centerIn: parent
                                width: 10; height: 2; radius: 1
                                color: "#000000"
                            }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -2
                                cursorShape: Qt.PointingHandCursor
                                enabled: !shelf.busy
                                onClicked: shelf.removeAnimated(tile.entry.id)
                            }
                        }
                    }

                }

            }
        }
    }
}
