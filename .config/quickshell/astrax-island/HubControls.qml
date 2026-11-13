import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Hub tab "Controls": brightness + volume (tall sliders), Wi-Fi / Bluetooth / Night light /
// Do not disturb / Mute / Battery tiles, and the power profile (powerprofilesctl).
Item {
    id: page
    required property var hub
    readonly property int sliderH: 172
    readonly property int preferredHeight: sliderH + 8 + 36
    height: preferredHeight

    readonly property color fg: "#f5f5f7"
    readonly property color dim: "#8e8e93"
    readonly property color card: "#0e0e10"

    // ---- radios
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property bool wifiOn: wifiDevice !== null && Networking.wifiEnabled
    readonly property var wifiNow: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) || null) : null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter !== null && adapter.enabled
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    // ---- audio
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [page.sink] }
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property real volume: sink && sink.audio ? Math.min(1, sink.audio.volume) : 0

    // ---- brightness (same backend as Quick Actions)
    property real brightness: -1
    Process {
        id: briGet
        command: ["serpantinum-core", "brightness", "get"]
        stdout: StdioCollector { onStreamFinished: { const v = parseInt(text.trim()); if (!isNaN(v)) page.brightness = v / 100; } }
    }
    Process { id: briSet }
    Timer {
        id: briThrottle
        interval: 60; property real pending: -1
        onTriggered: if (pending >= 0) { briSet.command = ["serpantinum-core", "brightness", "set", String(Math.round(pending * 100))]; briSet.running = true; pending = -1; }
    }
    function setBrightness(v) { brightness = v; briThrottle.pending = v; if (!briThrottle.running) briThrottle.start(); }

    // ---- night light (Serpantinum's own gamma script)
    readonly property string blScript: Quickshell.env("HOME") + "/.local/share/serpantinum/src/scripts/blue_light_filter.sh"
    property bool night: false
    Process {
        id: nightGet
        command: ["bash", page.blScript, "status"]
        stdout: StdioCollector { onStreamFinished: page.night = text.trim() === "running" }
    }
    Process { id: nightSet; onExited: nightGet.running = true }
    function toggleNight() {
        night = !night;
        nightSet.command = night ? ["bash", blScript, "set", "4000", "", "manual"] : ["bash", blScript, "reset"];
        nightSet.running = true;
    }

    // ---- do not disturb (Serpantinum notifications.dnd, toggled through its IPC)
    property bool dnd: false
    FileView {
        path: Quickshell.env("HOME") + "/.config/serpantinum/settings.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { const j = JSON.parse(text()); page.dnd = !!(j.notifications && j.notifications.dnd); } catch (e) {} }
    }
    function toggleDnd() {
        dnd = !dnd;
        if (hub.srpShell) Quickshell.execDetached(["quickshell", "ipc", "-p", hub.srpShell, "call", "dnd", "toggle"]);
    }

    // ---- power profile
    property string profile: ""
    Process {
        id: profGet
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector { onStreamFinished: page.profile = text.trim() }
    }
    Process { id: profSet; onExited: profGet.running = true }
    function setProfile(p) { profile = p; profSet.command = ["powerprofilesctl", "set", p]; profSet.running = true; }

    // ---- battery
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.ready && battery.isLaptopBattery
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)

    Component.onCompleted: { briGet.running = true; nightGet.running = true; profGet.running = true; }

    // ================================================================ sliders
    component TallSlider: Rectangle {
        id: ts
        property real level: 0
        property string glyph: ""
        signal moved(real v)
        width: 68; height: page.sliderH; radius: 20
        color: page.card; border.width: 1; border.color: "#16ffffff"
        clip: true
        Rectangle {
            anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: 1
            radius: 19
            height: Math.max(0, (parent.height - 2) * ts.level)
            color: "#f2f2f5"
            Behavior on height { enabled: !tsArea.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 12
            text: Math.round(ts.level * 100) + "%"
            color: ts.level > 0.86 ? "#0b0b0c" : page.fg
            font.family: page.hub.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 14
            text: ts.glyph
            color: ts.level > 0.14 ? "#0b0b0c" : page.fg
            font.family: page.hub.iconFont; font.pixelSize: 18
        }
        MouseArea {
            id: tsArea
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            // Only a real drag moves the value. No wheel handler: a touchpad's inertial scrolling sends hundreds of
            // events after the fingers lift and each one used to nudge the value, so brightness/volume kept
            // drifting by themselves (and the volume HUD kept popping up).
            property bool dragging: false
            function apply(my) { ts.moved(Math.max(0, Math.min(1, 1 - my / height))); }
            onPressed: m => { dragging = true; apply(m.y); }
            onReleased: dragging = false
            onCanceled: dragging = false
            onPositionChanged: m => { if (dragging && pressed) apply(m.y); }
            preventStealing: true
        }
    }
    Row {
        id: sliders
        spacing: 8
        TallSlider {
            level: Math.max(0, page.brightness)
            glyph: "\u{f00e0}"
            onMoved: v => page.setBrightness(v)
        }
        TallSlider {
            level: page.muted ? 0 : page.volume
            glyph: page.muted || page.volume === 0 ? "\u{f075f}" : "\u{f057e}"
            onMoved: v => { if (page.sink && page.sink.audio) { page.sink.audio.muted = false; page.sink.audio.volume = v; } }
        }
    }

    // ================================================================ tiles
    component Tile: Rectangle {
        id: tile
        property string glyph: ""
        property string name: ""
        property string detail: ""
        property bool on: false
        property color tint: "#0a84ff"
        property bool clickable: true
        signal toggled()
        radius: 18
        color: on ? Qt.rgba(tint.r, tint.g, tint.b, 0.24) : page.card
        border.width: 1; border.color: on ? Qt.rgba(tint.r, tint.g, tint.b, 0.3) : "#16ffffff"
        Behavior on color { ColorAnimation { duration: 180 } }
        scale: tArea.pressed && clickable ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Rectangle {
            id: tileIcon
            x: 12; y: 12; width: 28; height: 28; radius: 14
            color: tile.on ? tile.tint : "#1f1f22"
            Behavior on color { ColorAnimation { duration: 180 } }
            Text { anchors.centerIn: parent; text: tile.glyph; color: tile.on ? "#ffffff" : "#d1d1d6"; font.family: page.hub.iconFont; font.pixelSize: 14 }
        }
        Column {
            x: 12; anchors.top: tileIcon.bottom; anchors.topMargin: 10
            width: parent.width - 24; spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; text: tile.name; color: page.fg; font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.DemiBold }
            Text { width: parent.width; elide: Text.ElideRight; text: tile.detail; color: tile.on ? "#c7c7cc" : page.dim; font.family: page.hub.textFont; font.pixelSize: 11 }
        }
        MouseArea { id: tArea; anchors.fill: parent; enabled: tile.clickable; cursorShape: Qt.PointingHandCursor; onClicked: tile.toggled() }
    }
    Grid {
        id: tiles
        anchors.left: sliders.right; anchors.leftMargin: 8; anchors.right: parent.right
        columns: 3; spacing: 8
        readonly property real tw: (width - 16) / 3
        readonly property real th: (page.sliderH - 8) / 2
        Tile {
            width: tiles.tw; height: tiles.th
            glyph: ""; name: "Wi-Fi"; on: page.wifiOn
            detail: !page.wifiDevice ? "Unavailable" : !page.wifiOn ? "Off" : page.wifiNow ? page.wifiNow.name : "On"
            onToggled: Networking.wifiEnabled = !page.wifiOn
        }
        Tile {
            width: tiles.tw; height: tiles.th
            glyph: ""; name: "Bluetooth"; on: page.btOn
            detail: !page.adapter ? "Unavailable" : !page.btOn ? "Off"
                  : page.btConnected.length === 1 ? (page.btConnected[0].name || "1 device") : page.btConnected.length > 1 ? page.btConnected.length + " devices" : "On"
            onToggled: if (page.adapter) page.adapter.enabled = !page.btOn
        }
        Tile {
            width: tiles.tw; height: tiles.th
            glyph: ""; name: "Night light"; on: page.night; tint: "#ff9f0a"
            detail: page.night ? "On" : "Off"
            onToggled: page.toggleNight()
        }
        Tile {
            width: tiles.tw; height: tiles.th
            glyph: "\u{f009b}"; name: "Do not disturb"; on: page.dnd; tint: "#8e6bff"
            detail: page.dnd ? "On" : "Off"
            onToggled: page.toggleDnd()
        }
        Tile {
            width: tiles.tw; height: tiles.th
            glyph: page.muted ? "\u{f075f}" : "\u{f057e}"; name: "Mute"; on: page.muted; tint: "#ff453a"
            detail: page.muted ? "Sound off" : "Sound on"
            onToggled: if (page.sink && page.sink.audio) page.sink.audio.muted = !page.muted
        }
        Tile {
            width: tiles.tw; height: tiles.th
            clickable: false
            glyph: page.charging ? "\u{f0084}" : "\u{f0079}"
            name: page.hasBattery ? Math.round(page.battery.percentage * 100) + "%" : "Battery"
            detail: !page.hasBattery ? "No battery" : page.charging ? "Charging" : "On battery"
            on: page.charging; tint: "#30d158"
        }
    }

    // ================================================================ power profile
    Rectangle {
        id: prof
        anchors.bottom: parent.bottom
        width: parent.width; height: 36; radius: 18
        color: page.card; border.width: 1; border.color: "#16ffffff"
        readonly property var opts: [
            { id: "power-saver", t: "Saver" },
            { id: "balanced", t: "Balanced" },
            { id: "performance", t: "Performance" }
        ]
        readonly property int sel: Math.max(0, opts.findIndex(o => o.id === page.profile))
        Rectangle {
            visible: page.profile !== ""
            x: 3 + prof.sel * (prof.width - 6) / 3; y: 3
            width: (prof.width - 6) / 3; height: prof.height - 6; radius: height / 2
            color: "#f2f2f5"
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
        Row {
            x: 3; y: 3
            Repeater {
                model: prof.opts
                Item {
                    required property var modelData
                    required property int index
                    width: (prof.width - 6) / 3; height: prof.height - 6
                    Text {
                        anchors.centerIn: parent
                        text: modelData.t
                        color: index === prof.sel && page.profile !== "" ? "#0b0b0c" : page.dim
                        Behavior on color { ColorAnimation { duration: 180 } }
                        font.family: page.hub.textFont; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.setProfile(modelData.id) }
                }
            }
        }
    }
}
