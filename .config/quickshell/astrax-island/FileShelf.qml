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
    readonly property int preferredHeight: 224 + (visibleRows-1) * 118
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

    Text {
        id: title
        text: shelf.hoveringDrop ? (shelf.hasRoom ? "Drop to save" : "Shelf full") : "Files"
        color: "#f5f5f7"; font.family: shelf.textFont; font.pixelSize: 22; font.weight: Font.DemiBold
    }
    Text {
        anchors.right: parent.right; anchors.verticalCenter: title.verticalCenter
        text: shelf.count + " / 8 groups"
        color: "#98989d"; font.family: shelf.textFont; font.pixelSize: 13; font.weight: Font.Medium
    }
    Text {
        id: subtitle
        anchors.top: title.bottom; anchors.topMargin: 6
        width: parent.width; elide: Text.ElideRight
        text: shelf.busy ? "Saving…" : shelf.message || (shelf.hoveringDrop ? "Your files, ready for later" : "Drag to take · copy to paste")
        color: "#98989d"; font.family: shelf.textFont; font.pixelSize: 12
    }
    Grid {
        id: grid
        anchors.top: subtitle.bottom; anchors.topMargin: 20
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
                Timer {
                    interval: 250
                    running: tile.removing
                    onTriggered: shelf.request("remove", [shelf.removingId])
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
                    anchors.fill: parent
                    visible: tile.entry === null
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
                    anchors.fill: parent
                    opacity: tile.removing ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation { duration: tile.removing ? 220 : 100; easing.type: Easing.OutCubic }
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
                            NumberAnimation { target: arrivingFile; property: "relocation"; to: 1; duration: 240; easing.type: Easing.OutCubic }
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
                            x: (parent.width - 32) / 2; y: 13; width: 32; height: 32
                            source: tile.entry && /\.(png|jpg|jpeg|webp|gif)$/i.test(tile.entry.name) ? tile.entry.uri : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: tile.entry !== null && tile.entry.files.length === 1 && status === Image.Ready
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 12
                            text: tile.entry ? FI.glyphFor(tile.entry.name, false) : ""
                            visible: tile.entry !== null && tile.entry.files.length === 1 && !/\.(png|jpg|jpeg|webp|gif)$/i.test(tile.entry.name)
                            color: tile.entry ? "#f5f5f7" : "#48484a"
                            font.family: tile.entry ? shelf.iconFont : shelf.textFont; font.pixelSize: 31
                        }
                        Grid {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8; columns: 2; spacing: 3
                            visible: tile.entry !== null && tile.entry.files.length > 1
                            Repeater {
                                model: tile.entry && tile.entry.files.length > 1 ? tile.entry.files : []
                                delegate: Item {
                                    required property var modelData
                                    width: 19; height: 19
                                    Image {
                                        id: groupThumb
                                        anchors.fill: parent
                                        source: /\.(png|jpg|jpeg|webp|gif)$/i.test(modelData.name) ? modelData.uri : ""
                                        fillMode: Image.PreserveAspectCrop
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: groupThumb.status !== Image.Ready
                                        text: FI.glyphFor(modelData.name, false)
                                        color: "#f5f5f7"
                                        font.family: shelf.iconFont; font.pixelSize: 18
                                    }
                                }
                            }
                        }
                        Text {
                            x: 8; y: 52; width: parent.width - 16
                            text: tile.entry ? tile.entry.name : ""
                            elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter
                            color: tile.entry ? "#f5f5f7" : "#636366"
                            font.family: shelf.textFont; font.pixelSize: 11; font.weight: Font.Medium
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 78
                            text: tile.entry && tile.entry.files.length > 1 ? "Copy " + tile.entry.files.length : "Copy"; visible: tile.entry !== null
                            color: "#0a84ff"; font.family: shelf.textFont; font.pixelSize: 11
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
