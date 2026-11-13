import QtQuick
import Quickshell
import Quickshell.Io

// Hub tab "Widgets": date + next event, focus timer (Pomodoro), weather, world clock. 2 x 2 cards.
Item {
    id: page
    required property var hub
    readonly property int cardH: 86
    readonly property int preferredHeight: cardH * 2 + 8
    height: preferredHeight

    readonly property color card: "#0e0e10"
    readonly property color line: "#16ffffff"
    readonly property color fg: "#f5f5f7"
    readonly property color dim: "#8e8e93"
    readonly property string mono: "Adwaita Mono"

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: page.visible; triggeredOnStart: true; onTriggered: page.now = new Date() }

    // ---- date helpers
    readonly property var es: Qt.locale("en_US")
    function abbr(s) { return s.replace(".", "").toUpperCase().slice(0, 3); }
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y0) / 86400000 + 1) / 7);
    }
    readonly property real dayFrac: (now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400

    // ---- next event (Google Calendar iCal, same backend as the 1-click panel)
    property var nextEvent: null
    property bool calConfigured: false
    Process {
        id: calProc
        command: ["python3", "-I", Quickshell.shellPath("control-calendar.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    page.calConfigured = d.error !== "no-config";
                    page.nextEvent = d.ok && d.events.length ? d.events[0] : null;
                } catch (e) { page.nextEvent = null; }
            }
        }
    }
    Timer { interval: 120000; repeat: true; running: page.visible; triggeredOnStart: true; onTriggered: if (!calProc.running) calProc.running = true }
    function inText(e) {
        const m = Math.round((e.ts * 1000 - now.getTime()) / 60000);
        if (e.allDay) return "today";
        if (m <= 0) return "now";
        if (m < 60) return "in " + m + " min";
        if (m < 1440) return "in " + Math.floor(m / 60) + " h";
        return "in " + Math.floor(m / 1440) + " d";
    }

    // ---- weather
    property var wx: ({})
    Process {
        id: wxProc
        command: ["python3", "-I", Quickshell.shellPath("hub-weather.py")]
        stdout: StdioCollector { onStreamFinished: { try { page.wx = JSON.parse(text); } catch (e) {} } }
    }
    Timer { interval: 900000; repeat: true; running: page.visible; triggeredOnStart: true; onTriggered: if (!wxProc.running) wxProc.running = true }
    function wxInfo(code, day) {
        if (code === undefined) return { g: "\u{f0599}", t: "—" };
        if (code === 0) return { g: day ? "\u{f0599}" : "\u{f0594}", t: "Clear" };
        if (code <= 2) return { g: day ? "\u{f0595}" : "\u{f0f31}", t: "Partly cloudy" };
        if (code === 3) return { g: "\u{f0590}", t: "Cloudy" };
        if (code <= 48) return { g: "\u{f0591}", t: "Fog" };
        if (code <= 57) return { g: "\u{f0597}", t: "Drizzle" };
        if (code <= 67) return { g: "\u{f0597}", t: "Rain" };
        if (code <= 77) return { g: "\u{f0598}", t: "Snow" };
        if (code <= 82) return { g: "\u{f0596}", t: "Showers" };
        return { g: "\u{f0593}", t: "Storm" };
    }
    readonly property var wxNow: wxInfo(wx.code, wx.day !== false)

    // ---- world clock (second city, via TZ)
    readonly property string otherTz: "America/New_York"
    readonly property string otherName: "New York"
    property string otherTime: ""
    Process {
        id: tzProc
        command: ["sh", "-c", "TZ=" + page.otherTz + " date +'%-I:%M %p'"]
        stdout: StdioCollector { onStreamFinished: page.otherTime = text.trim() }
    }
    Timer { interval: 30000; repeat: true; running: page.visible; triggeredOnStart: true; onTriggered: if (!tzProc.running) tzProc.running = true }

    component Card: Rectangle {
        radius: 18; color: page.card
        border.width: 1; border.color: page.line
    }

    Grid {
        columns: 2; spacing: 8
        width: parent.width
        // ------------------------------------------------ date + next event
        Card {
            width: (page.width - 8) / 2; height: page.cardH
            Row {
                x: 14; y: 10; spacing: 8
                Text { text: page.now.getDate(); color: page.fg; font.family: page.hub.textFont; font.pixelSize: 34; font.weight: Font.DemiBold }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: -2
                    Text { text: page.abbr(page.now.toLocaleDateString(page.es, "ddd")); color: page.fg; font.family: page.hub.textFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: page.abbr(page.now.toLocaleDateString(page.es, "MMM")); color: page.dim; font.family: page.hub.textFont; font.pixelSize: 13 }
                }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 14; y: 14
                text: "Week " + page.isoWeek(page.now); color: page.dim
                font.family: page.hub.textFont; font.pixelSize: 12
            }
            Rectangle { x: 14; y: 56; width: 3; height: 14; radius: 1.5; color: "#4a8cff" }
            Text {
                x: 23; y: 54; width: parent.width - 23 - evWhen.width - 22; elide: Text.ElideRight
                text: page.nextEvent ? page.nextEvent.title : (page.calConfigured ? "No events" : "Connect your calendar")
                color: page.nextEvent ? page.fg : page.dim
                font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.Medium
            }
            Text {
                id: evWhen
                anchors.right: parent.right; anchors.rightMargin: 14; y: 55
                text: page.nextEvent ? page.inText(page.nextEvent) : ""
                color: page.dim; font.family: page.mono; font.pixelSize: 11
            }
            Rectangle {   // how much of today is gone
                x: 14; y: 74; width: parent.width - 28; height: 3; radius: 1.5; color: "#1affffff"
                Rectangle { width: parent.width * page.dayFrac; height: parent.height; radius: 1.5; color: "#d1d1d6" }
            }
        }
        // ------------------------------------------------ focus timer
        Card {
            width: (page.width - 8) / 2; height: page.cardH
            Item {
                id: ring
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 64; height: 64
                readonly property real frac: page.hub.focusLeft / page.hub.focusTotal
                onFracChanged: cv.requestPaint()
                Canvas {
                    id: cv
                    anchors.fill: parent
                    onPaint: {
                        const c = getContext("2d"); c.reset();
                        c.lineWidth = 4; c.lineCap = "round";
                        c.strokeStyle = "rgba(255,255,255,0.10)";
                        c.beginPath(); c.arc(32, 32, 28, 0, Math.PI * 2); c.stroke();
                        c.strokeStyle = page.hub.focusPhase === "focus" ? "#ff6b5c" : "#30d158";
                        c.beginPath(); c.arc(32, 32, 28, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ring.frac); c.stroke();
                    }
                    Connections { target: page.hub; function onFocusPhaseChanged() { cv.requestPaint(); } }
                }
                Text {
                    anchors.centerIn: parent
                    text: Math.floor(page.hub.focusLeft / 60) + ":" + String(page.hub.focusLeft % 60).padStart(2, "0")
                    color: page.fg; font.family: page.mono; font.pixelSize: 13; font.weight: Font.DemiBold
                }
            }
            Column {
                anchors.left: ring.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text { text: page.hub.focusPhase === "focus" ? "Focus" : "Break"; color: page.fg; font.family: page.hub.textFont; font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { text: "25 + 5 min"; color: page.dim; font.family: page.hub.textFont; font.pixelSize: 11 }
                Row {
                    topPadding: 6; spacing: 8
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: playArea.pressed ? "#d1d1d6" : "#f5f5f7"
                        Text { anchors.centerIn: parent; text: page.hub.focusRunning ? "" : ""; color: "#0b0b0c"; font.family: page.hub.iconFont; font.pixelSize: 11 }
                        MouseArea { id: playArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.hub.focusToggle() }
                    }
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: resetArea.containsMouse ? "#2a2a2e" : "#1a1a1d"
                        Text { anchors.centerIn: parent; text: ""; color: "#d1d1d6"; font.family: page.hub.iconFont; font.pixelSize: 11 }
                        MouseArea { id: resetArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.hub.focusReset() }
                    }
                }
            }
        }
        // ------------------------------------------------ weather
        Card {
            width: (page.width - 8) / 2; height: page.cardH
            Text {
                x: 14; y: 6
                text: page.wx.temp !== undefined ? page.wx.temp + "°" : "—"
                color: page.fg; font.family: page.hub.textFont; font.pixelSize: 34; font.weight: Font.DemiBold
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 14; y: 12
                text: page.wxNow.g; color: "#ffd60a"
                font.family: page.hub.iconFont; font.pixelSize: 24
            }
            Text {
                x: 14; y: 58; width: parent.width - 28 - hiLo.width - 6; elide: Text.ElideRight
                text: page.wxNow.t + (page.wx.city ? " · " + page.wx.city : "")
                color: page.dim; font.family: page.hub.textFont; font.pixelSize: 12
            }
            Text {
                id: hiLo
                anchors.right: parent.right; anchors.rightMargin: 14; y: 58
                text: page.wx.max !== undefined ? "H " + page.wx.max + "°  L " + page.wx.min + "°" : ""
                color: page.dim; font.family: page.hub.textFont; font.pixelSize: 11
            }
        }
        // ------------------------------------------------ world clock
        Card {
            width: (page.width - 8) / 2; height: page.cardH
            Row {
                x: 14; y: 6; spacing: 4
                Text {
                    text: Qt.formatTime(page.now, "h:mm")
                    color: page.fg; font.family: page.hub.textFont; font.pixelSize: 34; font.weight: Font.DemiBold
                }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: page.now.getHours() < 12 ? "AM" : "PM"
                    color: page.dim; font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.Medium
                }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 14; y: 14
                text: page.abbr(page.now.toLocaleDateString(page.es, "ddd"))
                color: page.fg; font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
            }
            Row {
                x: 14; y: 58; spacing: 6
                Text { text: "\uf0ac"; color: page.dim; font.family: page.hub.iconFont; font.pixelSize: 12 }
                Text { text: page.otherName; color: page.dim; font.family: page.hub.textFont; font.pixelSize: 12 }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 14; y: 58
                text: page.otherTime
                color: page.fg; font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
            }
        }
    }
}
