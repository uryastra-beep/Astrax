import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower

// Small status strip shown inside the island while it is idle (nothing playing, no event).
// `items` is the ordered list picked in Super+C > Dynamic Island: clock, wifi, bluetooth, batteries, apps.
Item {
    id: strip
    property var items: []
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    readonly property real contentWidth: row.implicitWidth
    readonly property color fg: "#f5f5f7"
    readonly property color dim: "#7c7c82"
    readonly property int maxBatteries: 4
    readonly property int maxApps: 6
    implicitHeight: row.implicitHeight
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // ---- privacy dots + VPN (idle-status.py) and weather (weather.py, Open-Meteo) ----
    property var privacy: ({mic: false, cam: false, screen: false, vpn: false})
    readonly property bool wantStatus: items.indexOf("vpn") >= 0   // the privacy dots live at the island's corner (shell.qml)
    Process {
        running: strip.wantStatus
        command: ["setpriv", "--pdeathsig", "TERM", "python3", Quickshell.shellPath("idle-status.py")]
        stdout: SplitParser { onRead: line => { try { strip.privacy = JSON.parse(line); } catch (e) {} } }
    }
    property var weather: null
    Process {
        id: weatherProc
        command: ["python3", Quickshell.shellPath("weather.py")]
        stdout: StdioCollector { onStreamFinished: { try { strip.weather = JSON.parse(text); } catch (e) {} } }
    }
    Timer {
        interval: 1200000; repeat: true; triggeredOnStart: true
        running: strip.items.indexOf("weather") >= 0
        onTriggered: if (!weatherProc.running) weatherProc.running = true
    }
    function weatherGlyph(w) {
        if (!w) return "";
        const c = w.code;
        if (c === 0) return w.day ? "󰖙" : "󰖔";
        if (c <= 2) return w.day ? "󰖕" : "󰼱";
        if (c === 3) return "󰖐";
        if (c === 45 || c === 48) return "󰖑";
        if (c >= 95) return "󰖓";
        if (c >= 71 && c <= 77 || c === 85 || c === 86) return "󰖘";
        if (c === 65 || c === 82 || c === 67) return "󰖖";
        return "󰖗";
    }

    property date now: new Date()
    Timer { interval: 10000; repeat: true; running: strip.visible && strip.items.indexOf("clock") >= 0; triggeredOnStart: true; onTriggered: strip.now = new Date() }

    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property bool wifiLinked: wifiDevice !== null && wifiDevice.networks.values.some(n => n.connected)
    readonly property bool btOn: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    readonly property int btCount: Bluetooth.devices.values.filter(d => d.connected).length

    // "pcBattery" = this PC only (the iOS-style battery); "batteries" = the connected devices (rings), up to 4
    readonly property var pcBattery: {
        const b = UPower.displayDevice;
        return b.ready && b.isLaptopBattery
            ? [{pill: true, glyph: "󰌢", percent: Math.round(b.percentage * 100), charging: b.state === UPowerDeviceState.Charging}] : [];
    }
    readonly property var batteries: {
        const rows = [];
        for (const d of Bluetooth.devices.values) {
            if (!d.connected || !d.batteryAvailable) continue;
            const icon = (d.icon || "").toLowerCase();
            const name = d.name || d.deviceName || "";
            const phone = icon.indexOf("phone") >= 0 || /iphone/i.test(name);
            const audio = /headset|headphone|audio/.test(icon) || /buds|airpods/i.test(name);
            rows.push({pill: false, glyph: phone ? "󰏲" : audio ? "󰋋" : "󰂯", percent: Math.round(d.battery * 100), charging: false});
        }
        return rows.slice(0, maxBatteries);
    }

    readonly property var ignoredApps: ["widget-clock", "widget-clock-ghost", "widget-lavat", "widget4-unimatrix", "widget4-lavat", "widget5-unimatrix", "widget5-lavat"]
    readonly property var openApps: {
        const seen = [], rows = [];
        for (const tl of Hyprland.toplevels.values) {
            const cls = tl.wayland ? tl.wayland.appId || "" : "";
            if (cls === "" || seen.indexOf(cls) >= 0 || ignoredApps.indexOf(cls) >= 0) continue;
            seen.push(cls);
            const entry = DesktopEntries.heuristicLookup(cls);
            rows.push({cls: cls, icon: entry ? entry.icon : cls});
        }
        return rows.slice(0, maxApps);
    }

    Row {
        id: row
        // first item on the left, the rest follow to the right (not centered)
        anchors.left: parent.left; anchors.leftMargin: 17
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Repeater {
            model: strip.items
            delegate: Loader {
                required property string modelData
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                sourceComponent: modelData === "clock" ? clockC : modelData === "wifi" ? wifiC : modelData === "bluetooth" ? btC
                    : modelData === "vpn" ? vpnC : modelData === "weather" ? wxC : modelData === "pcBattery" ? pcC : modelData === "batteries" ? batC : modelData === "apps" ? appsC : null
                visible: item !== null && item.implicitWidth > 0
            }
        }
    }

    // iOS privacy dots: orange = microphone, green = camera, purple = screen recording; nothing while idle of them
    Component { id: privC; Row {
        spacing: 5
        Repeater {
            model: [
                {on: strip.privacy.mic, color: "#ff9f0a"},
                {on: strip.privacy.cam, color: "#30d158"},
                {on: strip.privacy.screen, color: "#bf5af2"}
            ]
            delegate: Rectangle {
                required property var modelData
                visible: modelData.on
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: modelData.color
                SequentialAnimation on opacity {
                    running: parent.visible; loops: Animation.Infinite
                    NumberAnimation { to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                }
            }
        }
    } }
    Component { id: vpnC; Text {
        visible: strip.privacy.vpn
        text: strip.privacy.vpn ? "󰦝" : ""
        color: "#30d158"; font.family: strip.iconFont; font.pixelSize: 14
    } }
    Component { id: wxC; Row {
        spacing: strip.weather ? 4 : 0
        Text { text: strip.weatherGlyph(strip.weather); color: strip.fg; font.family: strip.iconFont; font.pixelSize: 14 }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: strip.weather ? strip.weather.temp + "°" : ""
            color: strip.fg; font.family: strip.textFont; font.pixelSize: 11; font.weight: Font.DemiBold
        }
    } }
    Component { id: clockC; Text {
        text: Qt.formatTime(strip.now, "h:mm AP")
        color: strip.fg; font.family: strip.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
    } }
    Component { id: wifiC; Text {
        text: !strip.wifiOn ? "󰖪" : strip.wifiLinked ? "󰖩" : "󰤯"
        color: strip.wifiOn && strip.wifiLinked ? strip.fg : strip.dim
        font.family: strip.iconFont; font.pixelSize: 15
    } }
    Component { id: btC; Row {
        spacing: 3
        Text {
            text: strip.btOn ? "󰂯" : "󰂲"
            color: strip.btOn ? (strip.btCount > 0 ? "#4aa3ff" : strip.fg) : strip.dim
            font.family: strip.iconFont; font.pixelSize: 15
        }
        Text {
            visible: strip.btOn && strip.btCount > 0
            text: strip.btCount
            anchors.verticalCenter: parent.verticalCenter
            color: strip.fg; font.family: strip.textFont; font.pixelSize: 10; font.weight: Font.DemiBold
        }
    } }
    // Apple style: the PC is the iOS battery (percentage inside), every other device is a ring that fills
    // with its charge and has the device's glyph in the middle.
    Component { id: pcC; Row {
        Repeater {
            model: strip.pcBattery
            delegate: Loader {
                required property var modelData
                sourceComponent: pillC
                onLoaded: item.info = modelData
            }
        }
    } }
    Component { id: batC; Row {
        spacing: 10
        Repeater {
            model: strip.batteries
            delegate: Loader {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: modelData.pill ? pillC : ringC
                onLoaded: item.info = modelData
            }
        }
    } }
    Component { id: pillC; Item {
        id: bp
        property var info: ({percent: 0, charging: false})
        readonly property real frac: Math.max(0, Math.min(1, info.percent / 100))
        readonly property color fill: info.charging ? "#30d158" : info.percent <= 20 ? "#ff453a" : "#f5f5f7"
        implicitWidth: 28; implicitHeight: 14
        Rectangle {   // body
            width: 28; height: 14; radius: 4.5
            color: Qt.rgba(1, 1, 1, 0.16)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.34)
            Rectangle {   // charge
                x: 1.5; y: 1.5; height: parent.height - 3; radius: 3
                width: Math.max(0, (parent.width - 3) * bp.frac)
                color: bp.fill
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
            Text {   // percentage, white over the empty part and black over the charge
                id: pctText
                anchors.centerIn: parent
                text: bp.info.percent
                color: "#ffffff"; font.family: strip.textFont; font.pixelSize: 9; font.weight: Font.Bold
            }
            Item {
                x: 1.5; y: 1.5; height: parent.height - 3
                width: Math.max(0, (parent.width - 3) * bp.frac)
                clip: true
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Text {
                    x: pctText.x - 1.5; y: pctText.y - 1.5
                    text: pctText.text
                    color: "#000000"; font: pctText.font
                }
            }
        }
    } }
    Component { id: ringC; Item {
        id: rg
        property var info: ({percent: 0, charging: false, glyph: ""})
        readonly property real frac: Math.max(0, Math.min(1, info.percent / 100))
        readonly property color tone: info.charging ? "#30d158" : info.percent <= 15 ? "#ff453a" : "#f5f5f7"
        implicitWidth: 20; implicitHeight: 20
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.22); strokeWidth: 2.2; fillColor: "transparent"
                PathAngleArc { centerX: 10; centerY: 10; radiusX: 8.6; radiusY: 8.6; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: rg.tone; strokeWidth: 2.2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 10; centerY: 10; radiusX: 8.6; radiusY: 8.6; startAngle: -90
                    sweepAngle: Math.max(1, 360 * rg.frac)
                    Behavior on sweepAngle { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            text: rg.info.glyph; color: strip.fg
            font.family: strip.iconFont; font.pixelSize: 10
        }
    } }
    Component { id: appsC; Row {
        spacing: 5
        Repeater {
            model: strip.openApps
            delegate: AppIcon {
                required property var modelData
                appleStyle: true; size: 16; app: modelData.cls; icon: modelData.icon
            }
        }
    } }
}
