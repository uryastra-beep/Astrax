import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire

// Quick Actions, Control Center style. The main page has Wi-Fi / Bluetooth / VPN tiles and the
// volume + brightness sliders. The tile's round button switches the radio, the rest of the tile
// opens its list (networks to join, devices to connect).
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

    // "main" | "wifi" | "bt"
    property string page: "main"
    readonly property int rowH: 48
    readonly property int listMax: 6
    readonly property real listBodyH: Math.min(listMax * rowH, Math.max(rowH * 2, activeList.contentHeight))
    readonly property int preferredHeight: 70 + (page === "main" ? 40 + 64 + 12 + 56 + 4 : 40 + 12 + listBodyH + 6)

    // ---- radios -------------------------------------------------------------------------
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property bool wifiOn: wifiDevice !== null && Networking.wifiEnabled
    readonly property var wifiNow: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) || null) : null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter !== null && adapter.enabled
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)
    property bool vpnUp: false

    function setWifi(on) { Networking.wifiEnabled = on; }
    function setBt(on) { if (adapter) adapter.enabled = on; }

    // ---- Wi-Fi list -----------------------------------------------------------------------
    // The model is a list of SSIDs that only changes when the set or order changes, so the rows
    // (and an open password field) are not rebuilt on every signal update.
    readonly property var wifiSorted: {
        if (!wifiDevice) return [];
        const best = {};
        for (const n of wifiDevice.networks.values) {
            if (!n.name) continue;
            const p = best[n.name];
            if (!p || n.connected || (!p.connected && n.signalStrength > p.signalStrength)) best[n.name] = n;
        }
        const bucket = n => Math.round(n.signalStrength * 3);
        return Object.values(best).sort((a, b) => (b.connected - a.connected) || (b.known - a.known)
            || (bucket(b) - bucket(a)) || a.name.localeCompare(b.name));
    }
    readonly property var wifiMap: { const m = {}; for (const n of wifiSorted) m[n.name] = n; return m; }
    readonly property string wifiKey: wifiSorted.map(n => n.name).join("\n")
    property var wifiNames: []
    onWifiKeyChanged: wifiNames = wifiKey ? wifiKey.split("\n") : []
    property string askName: ""        // network whose password field is open
    property string wifiError: ""

    // ---- Bluetooth list -------------------------------------------------------------------
    readonly property var btSorted: {
        const out = Bluetooth.devices.values.filter(d => d.name && d.name.length && !/^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(d.name));
        return out.sort((a, b) => (b.connected - a.connected) || ((b.paired || b.bonded) - (a.paired || a.bonded)) || a.name.localeCompare(b.name));
    }
    readonly property var btMap: { const m = {}; for (const d of btSorted) m[d.address] = d; return m; }
    readonly property string btKey: btSorted.map(d => d.address).join("\n")
    property var btAddrs: []
    onBtKeyChanged: btAddrs = btKey ? btKey.split("\n") : []
    property string btBusy: ""
    property var pairTarget: null
    property int pairTicks: 0
    Timer { id: busyClear; interval: 9000; onTriggered: panel.btBusy = "" }
    Timer {
        id: pairTimer; interval: 1000; repeat: true; running: panel.pairTarget !== null
        onTriggered: {
            const d = panel.pairTarget;
            if (!d) return;
            panel.pairTicks++;
            if (d.paired || d.bonded) { d.trusted = true; d.connect(); panel.pairTarget = null; panel.pairTicks = 0; }
            else if (panel.pairTicks > 25) { panel.pairTarget = null; panel.pairTicks = 0; panel.btBusy = ""; }
        }
    }
    function btTap(d) {
        if (!d) return;
        if (d.connected) { d.disconnect(); return; }
        btBusy = d.address; busyClear.restart();
        if (d.paired || d.bonded) d.connect();
        else { d.pair(); pairTicks = 0; pairTarget = d; }
    }
    function btGlyph(d) {
        const i = (d.icon || "").toLowerCase();
        if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return "󰋋";
        if (i.indexOf("keyboard") >= 0) return "󰌌";
        if (i.indexOf("mouse") >= 0) return "󰍽";
        if (i.indexOf("phone") >= 0) return "󰏲";
        if (i.indexOf("speaker") >= 0 || i.indexOf("audio") >= 0) return "󰓃";
        if (i.indexOf("computer") >= 0 || i.indexOf("laptop") >= 0) return "󰌢";
        if (i.indexOf("gaming") >= 0 || i.indexOf("joystick") >= 0) return "󰖺";
        return "󰂯";
    }

    // scan only while the matching page is open
    onPageChanged: {
        askName = ""; wifiError = "";
        if (wifiDevice) wifiDevice.scannerEnabled = (page === "wifi");
        if (adapter && adapter.enabled) adapter.discovering = (page === "bt");
    }
    onBtOnChanged: if (btOn && page === "bt" && adapter) adapter.discovering = true
    Component.onDestruction: {
        if (wifiDevice) wifiDevice.scannerEnabled = false;
        if (adapter) adapter.discovering = false;
    }

    // ---- VPN, volume, brightness ----------------------------------------------------------
    Process {
        id: vpnProbe
        command: ["sh", "-c", "ls /sys/class/net | grep -qE '^(wg|tun|ppp|proton|mullvad)' && echo up || echo down"]
        stdout: StdioCollector { onStreamFinished: panel.vpnUp = text.trim() === "up" }
    }
    Process { id: vpnToggle; onRunningChanged: if (!running) vpnProbe.running = true }
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sinkAudio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property string briScript: Quickshell.env("HOME") + "/.local/share/serpantinum/src/scripts/brightness.sh"
    property real brightness: -1
    Process {
        id: briGet
        command: ["serpantinum-core", "brightness", "get"]
        stdout: StdioCollector { onStreamFinished: { const v = parseInt(text.trim()); if (!isNaN(v)) panel.brightness = v / 100; } }
    }
    Process { id: briSet }
    Timer {
        id: briThrottle; interval: 90; property real pending: -1
        onTriggered: if (pending >= 0) { briSet.command = ["serpantinum-core", "brightness", "set", String(Math.round(pending * 100))]; briSet.running = true; pending = -1; }
    }
    function setBrightness(v) { brightness = v; briThrottle.pending = v; if (!briThrottle.running) briThrottle.start(); }
    Timer {
        interval: 3000; repeat: true; running: panel.opened; triggeredOnStart: true
        onTriggered: { if (!vpnProbe.running) vpnProbe.running = true; if (!briGet.running && !briThrottle.running) briGet.running = true; }
    }

    onOpenedChanged: if (opened) { page = "main"; focusDelay.restart(); }
    Component.onCompleted: { appear.start(); if (opened) focusDelay.restart(); }
    Timer { id: focusDelay; interval: 80; onTriggered: if (panel.opened) navigation.forceActiveFocus() }
    Item {
        id: navigation
        focus: true
        Keys.onPressed: event => panel.key(event)
    }
    function key(event) {
        if (event.key === Qt.Key_Escape) {
            if (askName !== "") askName = "";
            else if (page !== "main") page = "main";
            else dismissed();
        } else return;
        event.accepted = true;
    }

    // ---- shared pieces --------------------------------------------------------------------
    component Card: Item {
        id: card
        property real cardRadius: 22
        readonly property point lo: { panel.width; panel.height; x; y; parent.x; parent.y; return mapToItem(panel, 0, 0); }
        Rectangle { anchors.fill: parent; radius: card.cardRadius; color: "#0c0c0d" }
        ShaderEffect {
            anchors.fill: parent
            visible: panel.glassEnabled && panel.glassTexture !== null && width > 1 && height > 1
            property var src: panel.glassTexture
            property real radius: card.cardRadius
            property real strength: panel.glassStrength
            property real band: 9
            property vector2d stretch: Qt.vector2d(1, 1)
            property vector2d size: Qt.vector2d(width, height)
            property vector2d origin: Qt.vector2d(panel.glassOrigin.x + card.lo.x, panel.glassOrigin.y + card.lo.y)
            property vector2d screen: panel.glassScreen
            fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
        }
        Rectangle {
            anchors.fill: parent; radius: card.cardRadius
            gradient: Gradient {
                GradientStop { position: 0; color: panel.tint(0.05) }
                GradientStop { position: 0.5; color: panel.tint(0.015) }
                GradientStop { position: 1; color: panel.tint(0.08) }
            }
            border.width: 1; border.color: panel.tint(0.16)
        }
    }
    component Switch: Rectangle {
        id: sw
        property bool on: false
        signal toggled()
        width: 46; height: 28; radius: 14
        color: on ? "#30d158" : "#48484a"
        Behavior on color { ColorAnimation { duration: 180 } }
        Rectangle {
            y: 2; width: 24; height: 24; radius: 12; color: "#ffffff"
            x: sw.on ? sw.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    // ---------------------------------------------------------------- Argon chrome
    readonly property color accent: "#64d2ff"
    function tint(al) { return Qt.rgba(accent.r, accent.g, accent.b, al); }
    ArgonGlow { accent: panel.accent; reach: 130 }
    ArgonHeader {
        id: panelHeader
        glyph: panel.page === "wifi" ? "\uf1eb" : panel.page === "bt" ? "\uf293" : "\uf0e7"
        title: panel.page === "wifi" ? "Wi-Fi" : panel.page === "bt" ? "Bluetooth" : "Quick Actions"
        accent: panel.accent
        textFont: panel.textFont; iconFont: panel.iconFont
        closable: panel.page === "main"
        leftGlyph: "\uf053"; leftVisible: panel.page !== "main"
        onLeftClicked: panel.page = "main"
        onCloseClicked: panel.dismissed()
    }
    Switch {
        anchors.right: parent.right; y: 2
        visible: panel.page !== "main"
        on: panel.page === "wifi" ? panel.wifiOn : panel.btOn
        onToggled: { if (panel.page === "wifi") panel.setWifi(!panel.wifiOn); else panel.setBt(!panel.btOn); }
    }

    // ---- main page ------------------------------------------------------------------------
    Item {
        id: mainPage
        anchors.left: parent.left; anchors.right: parent.right
        y: panelHeader.height + 8; height: parent.height - panelHeader.height - 8
        opacity: panel.page === "main" ? 1 : 0; visible: opacity > 0.01
        scale: panel.page === "main" ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        transformOrigin: Item.Top

        Row {
            id: tiles
            width: parent.width; height: 64; spacing: 10
            Repeater {
                model: [
                    { kind: "wifi", name: "Wi-Fi", glyph: "󰖩" },
                    { kind: "bt", name: "Bluetooth", glyph: "󰂯" },
                    { kind: "vpn", name: "VPN", glyph: "󰦝" }
                ]
                delegate: Item {
                    id: tile
                    required property var modelData
                    readonly property bool active: modelData.kind === "wifi" ? panel.wifiOn : modelData.kind === "bt" ? panel.btOn : panel.vpnUp
                    readonly property string detail: {
                        if (modelData.kind === "wifi") return !panel.wifiDevice ? "Unavailable" : !panel.wifiOn ? "Off" : panel.wifiNow ? panel.wifiNow.name : "Not connected";
                        if (modelData.kind === "bt") return !panel.adapter ? "Unavailable" : !panel.btOn ? "Off"
                            : panel.btConnected.length === 1 ? (panel.btConnected[0].name || "1 device") : panel.btConnected.length > 1 ? panel.btConnected.length + " devices" : "On";
                        return panel.vpnUp ? "Connected" : "Off";
                    }
                    width: (tiles.width - 20) / 3; height: 64
                    scale: tileArea.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Card { anchors.fill: parent }
                    MouseArea {
                        id: tileArea
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tile.modelData.kind === "vpn") { vpnToggle.command = ["mullvad", panel.vpnUp ? "disconnect" : "connect"]; vpnToggle.running = true; }
                            else panel.page = tile.modelData.kind;
                        }
                    }
                    Rectangle {
                        id: round
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 38; height: 38; radius: 19
                        color: tile.active ? panel.accent : "#1f1f22"
                        Behavior on color { ColorAnimation { duration: 180 } }
                        scale: roundArea.pressed ? 0.92 : 1
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Text { anchors.centerIn: parent; text: tile.modelData.glyph; color: tile.active ? "#06131a" : "#f5f5f7"; font.family: panel.iconFont; font.pixelSize: 19; Behavior on color { ColorAnimation { duration: 180 } } }
                        MouseArea {
                            id: roundArea
                            anchors.fill: parent; anchors.margins: -2; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (tile.modelData.kind === "wifi") panel.setWifi(!panel.wifiOn);
                                else if (tile.modelData.kind === "bt") panel.setBt(!panel.btOn);
                                else { vpnToggle.command = ["mullvad", panel.vpnUp ? "disconnect" : "connect"]; vpnToggle.running = true; }
                            }
                        }
                    }
                    Column {
                        anchors.left: round.right; anchors.leftMargin: 9
                        anchors.right: chevron.left; anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { width: parent.width; elide: Text.ElideRight; text: tile.modelData.name; color: "#f5f5f7"
                               font.family: panel.textFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { width: parent.width; elide: Text.ElideRight; text: tile.detail; color: "#8e8e93"
                               font.family: panel.textFont; font.pixelSize: 11 }
                    }
                    Text {
                        id: chevron
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        visible: tile.modelData.kind !== "vpn"
                        width: visible ? 10 : 0
                        text: "›"; color: "#8e8e93"; font.pixelSize: 20
                    }
                }
            }
        }
        Row {
            y: 64 + 12; width: parent.width; height: 56; spacing: 10
            Repeater {
                model: [ { kind: "vol", glyph: "󰕾", mute: "󰝟" }, { kind: "bri", glyph: "󰃠" } ]
                delegate: Item {
                    id: slider
                    required property var modelData
                    width: (parent.width - 10) / 2; height: 56
                    readonly property real level: modelData.kind === "vol"
                        ? (panel.sinkAudio ? (panel.sinkAudio.muted ? 0 : Math.min(1, panel.sinkAudio.volume)) : 0)
                        : Math.max(0, panel.brightness)
                    Card { anchors.fill: parent }
                    Item {
                        anchors.fill: parent; anchors.margins: 1
                        clip: true
                        layer.enabled: true
                        Rectangle {
                            height: parent.height; radius: 21
                            width: Math.max(parent.height, parent.width * slider.level)
                            color: panel.accent
                            Behavior on width { enabled: !sArea.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                    }
                    Text {
                        x: 18; anchors.verticalCenter: parent.verticalCenter
                        text: slider.modelData.kind === "vol" && slider.level === 0 ? slider.modelData.mute : slider.modelData.glyph
                        color: slider.level > 0.1 ? "#06131a" : "#f5f5f7"
                        font.family: panel.iconFont; font.pixelSize: 21
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    MouseArea {
                        id: sArea
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        function apply(mx) {
                            const v = Math.max(0, Math.min(1, mx / width));
                            if (slider.modelData.kind === "vol") { if (panel.sinkAudio) { panel.sinkAudio.muted = false; panel.sinkAudio.volume = v; } }
                            else panel.setBrightness(v);
                        }
                        onPressed: m => apply(m.x)
                        onPositionChanged: m => { if (pressed) apply(m.x); }
                    }
                }
            }
        }
    }

    // ---- list page (Wi-Fi networks / Bluetooth devices) ------------------------------------
    readonly property var activeList: page === "bt" ? btList : wifiList
    Item {
        id: listPage
        anchors.left: parent.left; anchors.right: parent.right
        y: panelHeader.height + 8; height: parent.height - panelHeader.height - 8
        opacity: panel.page === "main" ? 0 : 1; visible: opacity > 0.01
        scale: panel.page === "main" ? 1.03 : 1
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        transformOrigin: Item.Top

        Item {
            id: listCard
            y: 12; width: parent.width; height: panel.listBodyH
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Card { anchors.fill: parent; cardRadius: 20 }

            // Wi-Fi
            ListView {
                id: wifiList
                anchors.fill: parent; anchors.margins: 1
                visible: panel.page === "wifi"
                clip: true; boundsBehavior: Flickable.StopAtBounds
                model: panel.wifiNames
                delegate: Item {
                    id: wrow
                    required property string modelData
                    readonly property var net: panel.wifiMap[modelData] || null
                    readonly property bool asking: panel.askName === modelData
                    readonly property bool secured: net !== null && net.security !== WifiSecurityType.Open
                    readonly property bool busy: net !== null && net.state === ConnectionState.Connecting
                    width: wifiList.width; height: panel.rowH + (asking ? 46 : 0)
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    clip: true
                    Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 17; color: "#18ffffff"; opacity: wArea.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } } }
                    MouseArea {
                        id: wArea
                        width: parent.width; height: panel.rowH; hoverEnabled: true
                        onClicked: {
                            const n = wrow.net;
                            if (!n) return;
                            panel.wifiError = "";
                            if (n.connected) n.disconnect();
                            else if (n.known || !wrow.secured) n.connect();
                            else { panel.askName = wrow.asking ? "" : wrow.modelData; pass.text = ""; pass.forceActiveFocus(); }
                        }
                    }
                    Text {
                        x: 16; y: (panel.rowH - height) / 2
                        text: !wrow.net ? "󰤯" : wrow.net.signalStrength > 0.75 ? "󰤨" : wrow.net.signalStrength > 0.5 ? "󰤥" : wrow.net.signalStrength > 0.25 ? "󰤢" : "󰤟"
                        color: "#f5f5f7"; font.family: panel.iconFont; font.pixelSize: 19
                    }
                    Column {
                        x: 50; y: 0; height: panel.rowH
                        width: parent.width - 50 - 56
                        spacing: 1
                        topPadding: (panel.rowH - (nameText.implicitHeight + subText.implicitHeight + 1)) / 2
                        Text { id: nameText; width: parent.width; elide: Text.ElideRight; text: wrow.modelData; color: "#f5f5f7"
                               font.family: panel.textFont; font.pixelSize: 13; font.weight: Font.Medium }
                        Text { id: subText; width: parent.width; elide: Text.ElideRight
                               text: wrow.busy ? "Connecting…" : wrow.net && wrow.net.connected ? "Connected" : wrow.asking && panel.wifiError ? panel.wifiError : wrow.net && wrow.net.known ? "Saved" : wrow.secured ? "Secured" : "Open"
                               color: wrow.net && wrow.net.connected ? panel.accent : "#8e8e93"
                               font.family: panel.textFont; font.pixelSize: 11 }
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 16; y: (panel.rowH - height) / 2
                        text: wrow.net && wrow.net.connected ? "󰄬" : wrow.secured ? "󰌾" : ""
                        color: wrow.net && wrow.net.connected ? panel.accent : "#8e8e93"
                        font.family: panel.iconFont; font.pixelSize: 15
                    }
                    // password row
                    Rectangle {
                        x: 50; y: panel.rowH - 2; width: parent.width - 50 - 16; height: 34; radius: 12
                        visible: wrow.asking
                        color: "#0f0f11"; border.width: 1; border.color: "#18ffffff"
                        TextInput {
                            id: pass
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 62
                            verticalAlignment: TextInput.AlignVCenter; clip: true
                            echoMode: TextInput.Password; passwordCharacter: "•"
                            color: "#f5f5f7"; selectionColor: panel.accent
                            font.family: panel.textFont; font.pixelSize: 12
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { join.go(); event.accepted = true; }
                                else panel.key(event);
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Password"; color: "#8e8e93"; visible: !pass.text; font: pass.font }
                        }
                        Rectangle {
                            id: join
                            anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                            width: 54; height: 26; radius: 13
                            color: pass.text.length >= 8 ? panel.accent : "#3a3a3c"
                            function go() {
                                if (pass.text.length < 8 || !wrow.net) return;
                                panel.wifiError = "";
                                wrow.net.connectWithPsk(pass.text);
                                panel.askName = "";
                            }
                            Text { anchors.centerIn: parent; text: "Join"; color: pass.text.length >= 8 ? "#06131a" : "#f5f5f7"; font.family: panel.textFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: join.go() }
                        }
                    }
                    Connections {
                        target: wrow.net
                        function onConnectionFailed() { panel.wifiError = "Could not connect"; panel.askName = wrow.modelData; }
                    }
                }
                Text {
                    anchors.centerIn: parent; visible: wifiList.count === 0
                    text: !panel.wifiDevice ? "No Wi-Fi adapter" : !panel.wifiOn ? "Wi-Fi is off" : "Searching for networks…"
                    color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 12
                }
            }

            // Bluetooth
            ListView {
                id: btList
                anchors.fill: parent; anchors.margins: 1
                visible: panel.page === "bt"
                clip: true; boundsBehavior: Flickable.StopAtBounds
                model: panel.btAddrs
                delegate: Item {
                    id: brow
                    required property string modelData
                    readonly property var dev: panel.btMap[modelData] || null
                    readonly property bool known: dev !== null && (dev.paired || dev.bonded)
                    readonly property bool busy: panel.btBusy === modelData && dev !== null && !dev.connected
                    width: btList.width; height: panel.rowH
                    Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 17; color: "#18ffffff"; opacity: bArea.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } } }
                    MouseArea { id: bArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.btTap(brow.dev) }
                    Rectangle {
                        id: bIcon
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 30; radius: 15
                        color: brow.dev && brow.dev.connected ? panel.accent : "#3a3a3c"
                        Behavior on color { ColorAnimation { duration: 180 } }
                        Text { anchors.centerIn: parent; text: brow.dev ? panel.btGlyph(brow.dev) : "󰂯"; color: "#f5f5f7"; font.family: panel.iconFont; font.pixelSize: 16 }
                    }
                    Column {
                        anchors.left: bIcon.right; anchors.leftMargin: 11
                        anchors.right: bRight.left; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter; spacing: 1
                        Text { width: parent.width; elide: Text.ElideRight; text: brow.dev ? brow.dev.name : ""; color: "#f5f5f7"
                               font.family: panel.textFont; font.pixelSize: 13; font.weight: Font.Medium }
                        Text { width: parent.width; elide: Text.ElideRight
                               text: brow.busy ? (brow.known ? "Connecting…" : "Pairing…")
                                   : brow.dev && brow.dev.connected ? "Connected" : brow.known ? "Not connected" : "Tap to pair"
                               color: brow.dev && brow.dev.connected ? panel.accent : "#8e8e93"
                               font.family: panel.textFont; font.pixelSize: 11 }
                    }
                    Text {
                        id: bRight
                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                        visible: brow.dev !== null && brow.dev.connected && brow.dev.batteryAvailable
                        text: brow.dev && brow.dev.batteryAvailable ? Math.round(brow.dev.battery * (brow.dev.battery <= 1 ? 100 : 1)) + "%" : ""
                        color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 12
                    }
                }
                Text {
                    anchors.centerIn: parent; visible: btList.count === 0
                    text: !panel.adapter ? "No Bluetooth adapter" : !panel.btOn ? "Bluetooth is off" : "Searching for devices…"
                    color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 12
                }
            }
        }
    }
}
