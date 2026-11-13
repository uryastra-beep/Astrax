import QtQuick
import Quickshell
import Quickshell.Io

// Hub tab "Web": your favourite sites one click away. Each opens in its own Brave app window
// (`brave --app`), so it keeps your sessions. Quickshell can't embed a browser here, so this is a drawer
// of launchers, not pages inside the island. "+" adds a site, right click removes it.
// Saved in ~/.local/state/astrax-island/hub-sites.json.
Item {
    id: page
    required property var hub
    readonly property int tileW: 78
    readonly property int tileH: 80
    readonly property int perRow: Math.max(1, Math.floor((width + 8) / (tileW + 8)))
    readonly property int rows: Math.max(1, Math.ceil((sites.length + 1) / perRow))
    readonly property int preferredHeight: Math.min(2, rows) * (tileH + 8) - 8 + (adding ? 46 : 0)
    height: preferredHeight

    readonly property color fg: "#f5f5f7"
    readonly property color dim: "#8e8e93"
    readonly property var defaults: [
        { name: "YouTube", url: "https://www.youtube.com" },
        { name: "GitHub", url: "https://github.com" },
        { name: "Claude", url: "https://claude.ai" },
        { name: "Gmail", url: "https://mail.google.com" },
        { name: "WhatsApp", url: "https://web.whatsapp.com" }
    ]
    property var sites: defaults
    property bool adding: false

    readonly property string store: Quickshell.env("HOME") + "/.local/state/astrax-island/hub-sites.json"
    FileView {
        id: file
        path: page.store
        printErrors: false
        onLoaded: { try { const j = JSON.parse(text()); if (Array.isArray(j)) page.sites = j; } catch (e) {} }
    }
    Process { id: saver }
    function save() {
        saver.command = ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "sh", store, JSON.stringify(sites)];
        saver.running = true;
    }
    function open(s) {
        Quickshell.execDetached(["brave", "--app=" + s.url]);
        hub.dismissed();
    }
    function add(text) {
        let t = text.trim();
        if (!t) { adding = false; return; }
        if (!/^https?:\/\//i.test(t)) t = "https://" + t;
        let host = t.replace(/^https?:\/\//i, "").split("/")[0].replace(/^www\./, "");
        let name = host.split(".")[0];
        name = name.charAt(0).toUpperCase() + name.slice(1);
        sites = sites.concat([{ name: name, url: t }]);
        save();
        adding = false;
    }
    function remove(s) { sites = sites.filter(x => x.url !== s.url); save(); }
    function hue(s) {
        let h = 0;
        for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
        return Qt.hsla(h / 360, 0.55, 0.55, 1);
    }

    Flickable {
        width: parent.width; height: Math.min(2, page.rows) * (page.tileH + 8) - 8
        contentHeight: grid.height; clip: true; boundsBehavior: Flickable.StopAtBounds
        Grid {
            id: grid
            columns: page.perRow; spacing: 8
            Repeater {
                model: page.sites
                Item {
                    id: tile
                    required property var modelData
                    width: page.tileW; height: page.tileH
                    readonly property color tone: page.hue(modelData.name)
                    scale: tArea.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 4
                        width: 48; height: 48; radius: 14
                        color: Qt.rgba(tile.tone.r, tile.tone.g, tile.tone.b, tArea.containsMouse ? 0.32 : 0.22)
                        border.width: 1; border.color: Qt.rgba(tile.tone.r, tile.tone.g, tile.tone.b, 0.35)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            anchors.centerIn: parent
                            text: tile.modelData.name.charAt(0).toUpperCase()
                            color: tile.tone; font.family: page.hub.textFont; font.pixelSize: 20; font.weight: Font.Bold
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 58
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: tile.modelData.name; color: page.fg
                        font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    MouseArea {
                        id: tArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: m => { if (m.button === Qt.RightButton) page.remove(tile.modelData); else page.open(tile.modelData); }
                    }
                }
            }
            Item {   // add
                width: page.tileW; height: page.tileH
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 4
                    width: 48; height: 48; radius: 14
                    color: addArea.containsMouse ? "#1c1c1f" : "#0e0e10"
                    border.width: 1; border.color: "#2affffff"
                    Text { anchors.centerIn: parent; text: "+"; color: page.dim; font.family: page.hub.textFont; font.pixelSize: 22 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 58
                    text: "Add"; color: page.dim; font.family: page.hub.textFont; font.pixelSize: 12
                }
                MouseArea { id: addArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { page.adding = true; field.forceActiveFocus(); } }
            }
        }
    }
    ArgonBar {
        visible: page.adding
        anchors.bottom: parent.bottom
        width: parent.width; height: 38
        accent: "#4aa3ff"; glyph: ""
        iconFont: page.hub.iconFont; textFont: page.hub.textFont
        trailingGlyph: ""; trailingLive: field.text.trim() !== ""
        onTrailingClicked: page.add(field.text)
        focused: field.activeFocus
        TextInput {
            id: field
            anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter; clip: true
            color: page.fg; selectionColor: "#4aa3ff"
            font.family: page.hub.textFont; font.pixelSize: 13
            Keys.onReturnPressed: page.add(text)
            Keys.onEnterPressed: page.add(text)
            Keys.onEscapePressed: { text = ""; page.adding = false; }
            Text { anchors.verticalCenter: parent.verticalCenter; visible: !field.text; text: "Type an address, e.g. notion.so"; color: "#7c7c82"; font: field.font }
        }
    }
}
