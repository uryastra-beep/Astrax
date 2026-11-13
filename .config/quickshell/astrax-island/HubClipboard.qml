import QtQuick
import Quickshell
import Quickshell.Io

// Hub tab "Clipboard": filter chips (All / Text / Links / Code / Images) and a horizontal row
// of cards, each with a coloured header for its kind (link, color, code, text, image).
// Click copies the entry back; right click deletes it. The grid button opens the full clipboard (Super+V).
Item {
    id: page
    required property var hub
    readonly property int cardW: 156
    readonly property int cardH: 128
    readonly property int preferredHeight: 30 + 10 + cardH
    height: preferredHeight

    readonly property color fg: "#f5f5f7"
    readonly property color dim: "#8e8e93"

    property var entries: []
    property bool loaded: false
    property string filter: "all"
    property string copiedId: ""

    function kindOf(e) {
        if (e.kind === "image") return "image";
        const t = (e.text || "").trim();
        if (/^(https?:\/\/|www\.)\S+$/i.test(t) || /^[\w-]+(\.[\w-]+)+(\/\S*)?$/.test(t)) return "link";
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t) || /^rgba?\(/i.test(t) || /^hsla?\(/i.test(t)) return "color";
        if (/[;{}]\s*$|=>|\b(const|let|var|function|def|class|import|return|fn|pub)\b|^\s*[$#>] |\(\)|\w+\(.*\);?$/m.test(t)) return "code";
        return "text";
    }
    readonly property var kinds: ({
        link: { t: "Link", g: "", c: "#4aa3ff" },
        color: { t: "Color", g: "", c: "#ff6a8a" },
        code: { t: "Code", g: "", c: "#bf8cff" },
        text: { t: "Text", g: "", c: "#a1a1a6" },
        image: { t: "Image", g: "", c: "#30d158" }
    })
    readonly property var shown: {
        const out = [];
        for (const e of entries) {
            const k = kindOf(e);
            if (filter === "all" || filter === k || (filter === "text" && k === "color")) out.push({ e: e, k: k });
        }
        return out;
    }

    Process {
        id: listProc
        property var buffer: []
        command: ["sh", Quickshell.shellPath("clip-list.sh"), "40"]
        stdout: SplitParser { onRead: line => { try { listProc.buffer.push(JSON.parse(line)); } catch (e) {} } }
        onRunningChanged: if (!running) { page.entries = listProc.buffer; page.loaded = true; }
    }
    function reload() { if (!listProc.running) { listProc.buffer = []; listProc.running = true; } }
    Component.onCompleted: reload()
    Process { id: pickProc }
    Process { id: editProc; onRunningChanged: if (!running) page.reload() }
    function pick(e) {
        pickProc.command = ["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", e.id];
        pickProc.running = true;
        copiedId = e.id; copiedReset.restart();
    }
    Timer { id: copiedReset; interval: 1400; onTriggered: page.copiedId = "" }
    function remove(e) {
        entries = entries.filter(x => x.id !== e.id);
        editProc.command = ["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete", "sh", e.id];
        editProc.running = true;
    }
    function clearAll() {
        entries = [];
        editProc.command = ["sh", "-c", "cliphist wipe; rm -f \"${XDG_RUNTIME_DIR:-/tmp}\"/astrax-island/cliphist/*"];
        editProc.running = true;
    }

    // ================================================================ chips
    Row {
        id: chips
        height: 30; spacing: 4
        Repeater {
            model: [
                { id: "all", t: "All" }, { id: "text", t: "Text" }, { id: "link", t: "Links" },
                { id: "code", t: "Code" }, { id: "image", t: "Images" }
            ]
            Rectangle {
                required property var modelData
                readonly property bool active: page.filter === modelData.id
                height: 28; width: chipText.implicitWidth + 24; radius: 14
                color: active ? "#f2f2f5" : chipArea.containsMouse ? "#1c1c1f" : "transparent"
                Behavior on color { ColorAnimation { duration: 160 } }
                Text {
                    id: chipText; anchors.centerIn: parent
                    text: modelData.t
                    color: parent.active ? "#0b0b0c" : page.fg
                    font.family: page.hub.textFont; font.pixelSize: 13; font.weight: Font.Medium
                }
                MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { page.filter = modelData.id; strip.contentX = 0; } }
            }
        }
    }
    Row {
        anchors.right: parent.right; height: 30; spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear"; color: clearArea.containsMouse ? page.fg : page.dim
            visible: page.entries.length > 0
            font.family: page.hub.textFont; font.pixelSize: 13; font.weight: Font.Medium
            MouseArea { id: clearArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.clearAll() }
        }
        Item {
            width: 28; height: 28; anchors.verticalCenter: parent.verticalCenter
            Text { anchors.centerIn: parent; text: ""; color: gridArea.containsMouse ? page.fg : page.dim; font.family: page.hub.iconFont; font.pixelSize: 14 }
            MouseArea { id: gridArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.hub.openClipboardPanel() }
        }
    }

    // ================================================================ cards
    ListView {
        id: strip
        y: 40; width: parent.width; height: page.cardH
        orientation: ListView.Horizontal; spacing: 10; clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: page.shown
        Behavior on contentX { enabled: !strip.moving; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        delegate: Rectangle {
            id: cardItem
            required property var modelData
            readonly property var e: modelData.e
            readonly property var k: page.kinds[modelData.k]
            readonly property bool isColor: modelData.k === "color"
            readonly property bool copied: page.copiedId === e.id
            width: page.cardW; height: page.cardH; radius: 16
            color: "#0e0e10"
            border.width: cardArea.containsMouse || copied ? 1.5 : 1
            border.color: copied ? "#30d158" : cardArea.containsMouse ? "#d8d8dc" : "#16ffffff"
            Behavior on border.color { ColorAnimation { duration: 140 } }
            clip: true
            scale: cardArea.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            // header band
            Rectangle {
                width: parent.width; height: 28
                topLeftRadius: 16; topRightRadius: 16
                color: Qt.rgba(cardItem.k.c.r, cardItem.k.c.g, cardItem.k.c.b, 0.2)
                Row {
                    x: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Text { text: cardItem.k.g; color: cardItem.k.c; font.family: page.hub.iconFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: cardItem.copied ? "Copied" : cardItem.k.t; color: cardItem.k.c; font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                }
            }
            // body
            Rectangle {   // colour swatch
                visible: cardItem.isColor
                x: 0; y: 28; width: parent.width; height: parent.height - 28 - 24
                color: cardItem.isColor && /^#/.test((cardItem.e.text || "").trim()) ? (cardItem.e.text || "").trim() : "#2a2a2e"
                Text {
                    x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                    text: (cardItem.e.text || "").trim().toUpperCase()
                    color: "#ffffff"; style: Text.Raised; styleColor: "#40000000"
                    font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }
            RoundedImage {
                visible: cardItem.modelData.k === "image"
                x: 6; y: 34; width: parent.width - 12; height: parent.height - 34 - 28; radius: 10
                source: cardItem.modelData.k === "image" ? "file://" + cardItem.e.thumb : ""
            }
            Text {
                visible: !cardItem.isColor && cardItem.modelData.k !== "image"
                x: 10; y: 36; width: parent.width - 20; height: parent.height - 36 - 26
                text: (cardItem.e.text || "").replace(/^https?:\/\//, "")
                wrapMode: Text.WrapAnywhere; elide: Text.ElideRight; maximumLineCount: cardItem.modelData.k === "link" ? 3 : 4
                textFormat: Text.PlainText
                color: page.fg
                font.family: cardItem.modelData.k === "code" ? "Adwaita Mono" : page.hub.textFont
                font.pixelSize: cardItem.modelData.k === "link" ? 14 : 12
                font.weight: cardItem.modelData.k === "link" ? Font.DemiBold : Font.Normal
            }
            Text {
                x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                width: parent.width - 20; elide: Text.ElideRight
                text: cardItem.modelData.k === "image" ? (cardItem.e.info || "")
                    : cardItem.modelData.k === "link" ? (cardItem.e.text || "").replace(/^https?:\/\//, "").split("/")[0]
                    : (cardItem.e.text || "").length + " chars"
                color: "#6e6e73"; font.family: page.hub.textFont; font.pixelSize: 11
            }
            MouseArea {
                id: cardArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: m => { if (m.button === Qt.RightButton) page.remove(cardItem.e); else page.pick(cardItem.e); }
            }
        }
        Text {
            anchors.centerIn: parent; visible: page.loaded && !page.shown.length
            text: page.entries.length ? "Nothing of this kind" : "Clipboard is empty"
            color: page.dim; font.family: page.hub.textFont; font.pixelSize: 13
        }
    }
    // scroll arrow
    Rectangle {
        visible: strip.contentWidth > strip.width
        opacity: strip.atXEnd ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 160 } }
        anchors.right: parent.right; anchors.rightMargin: 4
        y: strip.y + (strip.height - height) / 2
        width: 30; height: 30; radius: 15
        color: arrowArea.containsMouse ? "#2a2a2e" : "#1a1a1d"; border.width: 1; border.color: "#24ffffff"
        Text { anchors.centerIn: parent; text: ""; color: page.fg; font.family: page.hub.iconFont; font.pixelSize: 11 }
        MouseArea {
            id: arrowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: strip.contentX = Math.min(strip.contentWidth - strip.width, strip.contentX + (page.cardW + 10) * 2)
        }
    }
}
