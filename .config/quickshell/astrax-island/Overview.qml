import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire

Item {
    id: overview
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.6
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property real batteryScroll: 0
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    property var widgetOrder: ["clock", "batteries", "connections", "screenTime", "system", "files"]   // also: "quick"
    property real screenSeconds: 0
    property bool screenIdle: false
    property var screenHours: []
    property var stats: ({})
    readonly property var widgets: {
        const allowed = ["clock", "batteries", "connections", "quick", "screenTime", "system", "files"];
        const seen = [];
        for (const key of widgetOrder) if (allowed.indexOf(key) >= 0 && seen.indexOf(key) < 0) seen.push(key);
        return seen;
    }
    function duration(seconds) {
        const minutes = Math.floor(seconds / 60);
        return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m";
    }
    property int fileCount: 0
    signal filesRequested()
    property date now: new Date()
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wifiNetwork: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) || null) : null
    readonly property var connectedBluetooth: Bluetooth.devices.values.filter(d => d.connected)
    readonly property bool bluetoothOn: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    readonly property var battery: UPower.displayDevice
    readonly property var devices: {
        const rows = [];
        if (battery.ready && battery.isLaptopBattery)
            rows.push({name: "This PC", glyph: "󰌢", percent: Math.round(battery.percentage * 100), charging: battery.state === UPowerDeviceState.Charging});
        else rows.push({name: "This PC", glyph: "󰌢", percent: -1, charging: false});
        for (const d of Bluetooth.devices.values) {
            if (!d.connected) continue;
            const icon = (d.icon || "").toLowerCase();
            const name = d.name || d.deviceName || "Bluetooth";
            const phone = icon.indexOf("phone") >= 0 || /iphone/i.test(name);
            const audio = /headset|headphone|audio/.test(icon) || /buds|airpods/i.test(name);
            rows.push({name: name, glyph: phone ? "󰏲" : audio ? "󰋋" : "󰂯", percent: d.batteryAvailable ? Math.round(d.battery * 100) : -1, charging: false});
        }
        while (rows.length < 3)
            rows.push({empty: true, name: "Unknown", glyph: "?", percent: 0, charging: false});
        return rows;
    }
    Timer { interval: 1000; repeat: true; running: overview.visible; onTriggered: overview.now = new Date() }
    onVisibleChanged: if (visible) { now = new Date(); scroll.contentY = 0; }


    Process {
        id: statsReader
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/astrax-island/overview-stats.py"]
        stdout: StdioCollector { onStreamFinished: { try { overview.stats = JSON.parse(text); } catch (e) {} } }
    }
    Timer { interval: 30000; repeat: true; running: overview.visible && overview.widgets.indexOf("system") >= 0; triggeredOnStart: true; onTriggered: if (!statsReader.running) statsReader.running = true }
    // ---------------------------------------------------------------- Argon chrome
    readonly property color accent: "#7aa2ff"
    function tint(al) { return Qt.rgba(accent.r, accent.g, accent.b, al); }
    ArgonGlow { accent: overview.accent; reach: 120; strength: 0.9 }
    Flickable {
        id: scroll
        anchors.fill: parent
        contentHeight: sections.height
        clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: sections
            width: scroll.width; spacing: 12
            Repeater {
                model: overview.widgets
                delegate: Loader {
                    id: sectionLoader
                    required property string modelData
                    width: sections.width
                    height: item ? item.implicitHeight : 0
                    sourceComponent: modelData === "clock" ? clockWidget : modelData === "batteries" ? batteryWidget : modelData === "connections" ? connectionsWidget : modelData === "quick" ? quickWidget : modelData === "screenTime" ? screenWidget : modelData === "system" ? systemWidget : filesWidget
                    opacity: 0
                    Component.onCompleted: reveal.start()
                    NumberAnimation { id: reveal; target: sectionLoader; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                }
            }
            Text { visible: !overview.widgets.length; text: "Add widgets in Super+C → Dynamic Island"; color: "#8e8e93"; font.family: overview.textFont; font.pixelSize: 12 }
        }
    }
    Component {
        id: glassCard
        Item {
            id: material
            readonly property point localOrigin: {
                scroll.contentY; sections.height; overview.width; overview.widgets; overview.batteryScroll;
                parent.x; parent.y; parent.parent.x; parent.parent.y;
                return mapToItem(overview, 0, 0);
            }
            Rectangle { anchors.fill: parent; radius: 20; color: "#0c0c0d" }
            ShaderEffect {
                anchors.fill: parent
                visible: overview.glassEnabled && overview.glassTexture !== null && width > 1 && height > 1
                property var src: overview.glassTexture
                property real radius: 20
                property real strength: overview.glassStrength
                property real band: 9
                property vector2d stretch: Qt.vector2d(1, 1)
                property vector2d size: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(overview.glassOrigin.x + material.localOrigin.x,
                    overview.glassOrigin.y + material.localOrigin.y)
                property vector2d screen: overview.glassScreen
                fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
            }
            Rectangle {
                anchors.fill: parent; radius: 20
                gradient: Gradient {
                    GradientStop { position: 0; color: overview.tint(0.05) }
                    GradientStop { position: 0.5; color: overview.tint(0.015) }
                    GradientStop { position: 1; color: overview.tint(0.08) }
                }
                border.width: 1; border.color: overview.tint(0.16)
            }
        }
    }
    Component {
        id: clockWidget
        Item {
            implicitHeight: 72
    Row {
        id: heading
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 72
        Text {
            width: parent.width * 0.56
            text: Qt.formatDateTime(overview.now, "h:mm AP")
            color: "#f5f5f7"
            font.family: overview.textFont; font.pixelSize: 56; font.weight: Font.Medium
            font.letterSpacing: -3
        }
        Column {
            width: parent.width * 0.44
            topPadding: 14; spacing: 4
            Text {
                width: parent.width; horizontalAlignment: Text.AlignRight
                text: overview.now.toLocaleDateString(Qt.locale("en_US"), "dddd").toLocaleUpperCase()
                color: "#8e8e93"; font.family: overview.textFont; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.3
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignRight
                text: overview.now.toLocaleDateString(Qt.locale("en_US"), "d MMMM")
                color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 17; font.weight: Font.Medium
            }
        }
    }

        }
    }
    Component {
        id: batteryWidget
        Item {
            implicitHeight: 134
    Text {
        id: batteryTitle
        y: 0
        text: "Batteries"
        color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 15; font.weight: Font.DemiBold
    }
    Text {
        anchors.right: parent.right; anchors.verticalCenter: batteryTitle.verticalCenter
        visible: overview.widgets.indexOf("files") >= 0
        text: "Files  " + overview.fileCount + "/8  ›"
        color: overview.accent; font.family: overview.textFont; font.pixelSize: 12; font.weight: Font.Medium
        MouseArea { anchors.fill: parent; anchors.margins: -5; cursorShape: Qt.PointingHandCursor; onClicked: overview.filesRequested() }
    }
    ListView {
        id: deviceList
        anchors.top: batteryTitle.bottom; anchors.topMargin: 8
        width: parent.width; height: 108
        orientation: ListView.Horizontal; spacing: 10
        onContentXChanged: overview.batteryScroll = contentX
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: overview.devices
        delegate: Rectangle {
            required property var modelData
            width: (deviceList.width - 20) / 3; height: 108; radius: 20
            color: "transparent"
            Loader { anchors.fill: parent; sourceComponent: glassCard }
            Canvas {
                id: ring
                x: 13; y: 12; width: 38; height: 38
                property real amount: modelData.percent
                property color tint: modelData.empty === true ? "#636366" : amount >= 0 && amount <= 20 ? "#ff453a" : "#30d158"
                onAmountChanged: requestPaint()
                onTintChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset(); ctx.lineWidth = 3; ctx.lineCap = "round";
                    ctx.strokeStyle = "#1f1f22";
                    ctx.beginPath(); ctx.arc(19, 19, 16, 0, 2 * Math.PI); ctx.stroke();
                    if (amount >= 0) {
                        ctx.strokeStyle = tint;
                        ctx.beginPath(); ctx.arc(19, 19, 16, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0, Math.min(1, amount / 100))); ctx.stroke();
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: modelData.glyph; color: modelData.empty === true ? "#8e8e93" : "#f5f5f7"
                    font.family: modelData.empty === true ? overview.textFont : overview.iconFont; font.pixelSize: 20
                }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 13; y: 20
                text: modelData.percent >= 0 ? modelData.percent + "%" : "—"
                color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 18; font.weight: Font.Medium
            }
            Text {
                x: 13; y: 64; width: parent.width - 26
                text: modelData.name; elide: Text.ElideRight
                color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 12; font.weight: Font.Medium
            }
            Text {
                x: 13; y: 82; width: parent.width - 26
                text: modelData.empty === true ? "No device" : modelData.charging ? "Charging" : modelData.percent >= 0 ? "Connected" : "Battery unavailable"
                color: "#8e8e93"; font.family: overview.textFont; font.pixelSize: 10; elide: Text.ElideRight
            }
        }
    }
        }
    }
    Component {
        id: connectionsWidget
        Item {
            implicitHeight: 64
    Row {
        id: connections
        y: 0
        width: parent.width; height: 64; spacing: 10
        Repeater {
            model: [
                {name: "Wi-Fi", glyph: "󰖩", active: overview.wifiDevice !== null && Networking.wifiEnabled,
                 detail: overview.wifiDevice === null ? "Unavailable" : !Networking.wifiEnabled ? "Off" : overview.wifiNetwork ? overview.wifiNetwork.name : "On · not connected"},
                {name: "Bluetooth", glyph: "󰂯", active: overview.bluetoothOn,
                 detail: !Bluetooth.defaultAdapter ? "Unavailable" : !overview.bluetoothOn ? "Off" : overview.connectedBluetooth.length === 1 ? (overview.connectedBluetooth[0].name || "1 device") : overview.connectedBluetooth.length > 1 ? overview.connectedBluetooth.length + " devices connected" : "On · no devices"}
            ]
            delegate: Rectangle {
                required property var modelData
                width: (connections.width - 10) / 2; height: 64; radius: 20
                color: "transparent"
            Loader { anchors.fill: parent; sourceComponent: glassCard }
                Rectangle {
                    id: connectionIcon
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34; radius: 17
                    color: modelData.active ? overview.accent : "#1f1f22"
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.glyph; color: modelData.active ? "#070d1f" : "#f5f5f7"
                        font.family: overview.iconFont; font.pixelSize: 19
                    }
                }
                Column {
                    anchors.left: connectionIcon.right; anchors.leftMargin: 10
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: modelData.name; color: "#f5f5f7"
                        font.family: overview.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: modelData.detail; color: "#8e8e93"
                        font.family: overview.textFont; font.pixelSize: 10
                    }
                }
            }
        }
    }

        }
    }
    // ---- quick actions: toggles (Wi-Fi, Bluetooth, VPN) and the volume / brightness sliders ----
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sinkAudio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property string briScript: Quickshell.env("HOME") + "/.local/share/serpantinum/src/scripts/brightness.sh"
    property real brightness: -1
    property bool vpnUp: false
    readonly property bool wantQuick: visible && widgets.indexOf("quick") >= 0
    Process {
        id: briGet
        command: ["serpantinum-core", "brightness", "get"]
        stdout: StdioCollector { onStreamFinished: { const v = parseInt(text.trim()); if (!isNaN(v)) overview.brightness = v / 100; } }
    }
    Process { id: briSet }
    Timer { id: briThrottle; interval: 90; property real pending: -1
        onTriggered: if (pending >= 0) { briSet.command = ["serpantinum-core", "brightness", "set", String(Math.round(pending * 100))]; briSet.running = true; pending = -1; } }
    function setBrightness(v) { overview.brightness = v; briThrottle.pending = v; if (!briThrottle.running) briThrottle.start(); }
    Process {
        id: vpnProbe
        command: ["sh", "-c", "ls /sys/class/net | grep -qE '^(wg|tun|ppp|proton|mullvad)' && echo up || echo down"]
        stdout: StdioCollector { onStreamFinished: overview.vpnUp = text.trim() === "up" }
    }
    Process { id: vpnToggle; onRunningChanged: if (!running) vpnProbe.running = true }
    Timer { interval: 3000; repeat: true; running: overview.wantQuick; triggeredOnStart: true
        onTriggered: { if (!vpnProbe.running) vpnProbe.running = true; if (!briGet.running && !briThrottle.running) briGet.running = true; } }
    Component {
        id: quickWidget
        Item {
            implicitHeight: 56 + 10 + 96
            Row {
                id: toggles
                width: parent.width; height: 56; spacing: 10
                Repeater {
                    model: [
                        {name: "Wi-Fi", glyph: "󰖩", active: overview.wifiDevice !== null && Networking.wifiEnabled, kind: "wifi"},
                        {name: "Bluetooth", glyph: "󰂯", active: overview.bluetoothOn, kind: "bt"},
                        {name: "VPN", glyph: "󰦝", active: overview.vpnUp, kind: "vpn"}
                    ]
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        width: (toggles.width - 20) / 3; height: 56; radius: 20
                        color: "transparent"
                        scale: tileArea.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Loader { anchors.fill: parent; sourceComponent: glassCard }
                        Rectangle {
                            id: tileIcon
                            x: 11; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 16
                            color: tile.modelData.active ? overview.accent : "#1f1f22"
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Text { anchors.centerIn: parent; text: tile.modelData.glyph; color: tile.modelData.active ? "#070d1f" : "#f5f5f7"; font.family: overview.iconFont; font.pixelSize: 17 }
                        }
                        Column {
                            anchors.left: tileIcon.right; anchors.leftMargin: 8
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { width: parent.width; elide: Text.ElideRight; text: tile.modelData.name; color: "#f5f5f7"
                                   font.family: overview.textFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text { width: parent.width; text: tile.modelData.active ? "On" : "Off"; color: "#8e8e93"
                                   font.family: overview.textFont; font.pixelSize: 10 }
                        }
                        MouseArea {
                            id: tileArea
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (tile.modelData.kind === "wifi") Networking.wifiEnabled = !Networking.wifiEnabled;
                                else if (tile.modelData.kind === "bt") { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled; }
                                else { vpnToggle.command = ["mullvad", overview.vpnUp ? "disconnect" : "connect"]; vpnToggle.running = true; }
                            }
                        }
                    }
                }
            }
            Rectangle {
                y: 66; width: parent.width; height: 96; radius: 20; color: "transparent"
                Loader { anchors.fill: parent; sourceComponent: glassCard }
                Column {
                    anchors.fill: parent; anchors.margins: 14; spacing: 12
                    Repeater {
                        model: [
                            {kind: "vol", glyph: "󰕾"},
                            {kind: "bri", glyph: "󰃠"}
                        ]
                        delegate: Item {
                            id: srow
                            required property var modelData
                            width: parent.width; height: 32
                            readonly property real level: modelData.kind === "vol" ? (overview.sinkAudio ? Math.min(1, overview.sinkAudio.volume) : 0) : Math.max(0, overview.brightness)
                            Text { id: sGlyph; anchors.verticalCenter: parent.verticalCenter; text: srow.modelData.glyph; color: "#f5f5f7"
                                   font.family: overview.iconFont; font.pixelSize: 17; width: 22 }
                            Rectangle {
                                id: track
                                anchors.left: sGlyph.right; anchors.leftMargin: 10; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 20; radius: 10; color: Qt.rgba(1, 1, 1, 0.16); clip: true
                                Rectangle {
                                    height: parent.height; radius: 10; color: "#f5f5f7"
                                    width: Math.max(parent.height, parent.width * srow.level)
                                    Behavior on width { enabled: !sArea.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: sArea
                                    anchors.fill: parent
                                    function apply(mx) {
                                        const v = Math.max(0, Math.min(1, mx / width));
                                        if (srow.modelData.kind === "vol") { if (overview.sinkAudio) { overview.sinkAudio.muted = false; overview.sinkAudio.volume = v; } }
                                        else overview.setBrightness(v);
                                    }
                                    onPressed: m => apply(m.x)
                                    onPositionChanged: m => { if (pressed) apply(m.x); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: screenWidget
        Rectangle {
            implicitHeight: 144; radius: 20; color: "transparent"
            Loader { anchors.fill: parent; sourceComponent: glassCard }
            Text { x: 16; y: 13; text: "Screen Time · Today"; color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { x: 16; y: 36; text: overview.duration(overview.screenSeconds); color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 27; font.weight: Font.Medium }
            Text { anchors.right: parent.right; anchors.rightMargin: 16; y: 48; text: overview.screenIdle ? "Paused · away" : "Active PC use"; color: "#8e8e93"; font.family: overview.textFont; font.pixelSize: 10 }
            Row {
                x: 16; y: 78; width: parent.width-32; height: 31; spacing: 3
                Repeater {
                    model: 24
                    delegate: Item {
                        required property int index
                        width: (parent.width-69)/24; height: 31
                        Rectangle {
                            anchors.bottom: parent.bottom; width: parent.width
                            height: Math.max(3, 31 * Math.min(1, (overview.screenHours[index] || 0)/3600))
                            radius: 2; color: index === overview.now.getHours() ? overview.accent : overview.tint(0.4)
                            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
            Text { x: 16; y: 120; text: "00                                  Hourly activity                                  23"; color: "#8e8e93"; font.family: overview.textFont; font.pixelSize: 9 }
        }
    }
    Component {
        id: systemWidget
        Rectangle {
            implicitHeight: 128; radius: 20; color: "transparent"
            Loader { anchors.fill: parent; sourceComponent: glassCard }
            Column {
                x: 16; y: 14; width: parent.width-32; spacing: 10
                Text { text: "System"; color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { text: "Uptime  " + (overview.stats.uptime !== undefined ? overview.duration(overview.stats.uptime) : "—"); color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 12 }
                Text { text: "Memory  " + (overview.stats.memory || "—") + "     ·     Load  " + (overview.stats.load || "—"); color: "#8e8e93"; font.family: overview.textFont; font.pixelSize: 11 }
                Text { text: "Home storage  " + (overview.stats.storage || "—"); color: "#8e8e93"; font.family: overview.textFont; font.pixelSize: 11 }
            }
        }
    }
    Component {
        id: filesWidget
        Rectangle {
            implicitHeight: 68; radius: 20; color: "transparent"
            Loader { anchors.fill: parent; sourceComponent: glassCard }
            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Files"; color: "#f5f5f7"; font.family: overview.textFont; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: overview.fileCount + "/8   ›"; color: overview.accent; font.family: overview.textFont; font.pixelSize: 13 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: overview.filesRequested() }
        }
    }
}
