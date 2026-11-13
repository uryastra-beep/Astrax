import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Hub tab "Llamada": a big mic button (mute / unmute the default input), how long the mic has been in
// use and by which app, the output and input devices (pick one, test it) and a quick camera check.
Item {
    id: page
    required property var hub
    readonly property int preferredHeight: 158
    height: preferredHeight

    readonly property color fg: "#f5f5f7"
    readonly property color dim: "#8e8e93"
    readonly property color green: "#30d158"
    readonly property color red: "#ff453a"

    // ---- devices
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [page.sink, page.source] }
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream && !/\.monitor$/.test(n.name || ""))
    function label(n) { return n ? (n.nickname || n.description || n.name || "—") : "—"; }
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false
    function toggleMic() { if (source && source.audio) source.audio.muted = !source.audio.muted; }

    // ---- who is using the mic, and since when
    property var users: []
    property real since: 0
    property real nowMs: Date.now()
    readonly property bool live: users.length > 0
    Process {
        id: usersProc
        command: ["sh", "-c", "pactl -f json list source-outputs 2>/dev/null || echo []"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text).map(o => (o.properties || {})["application.name"] || "")
                        .filter(a => a && !/pavucontrol|cava|peak|quickshell|astrax/i.test(a));
                } catch (e) {}
                if (list.length && !page.users.length) page.since = Date.now();
                if (!list.length) page.since = 0;
                page.users = list;
            }
        }
    }
    Timer { interval: 2000; repeat: true; running: page.visible; triggeredOnStart: true; onTriggered: if (!usersProc.running) usersProc.running = true }
    Timer { interval: 1000; repeat: true; running: page.visible && page.live; onTriggered: page.nowMs = Date.now() }
    readonly property int secs: live && since > 0 ? Math.max(0, Math.floor((nowMs - since) / 1000)) : 0
    function clock(s) {
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0");
    }

    // ---- tests
    property string testing: ""          // "" | "out" | "rec" | "play"
    Process {
        id: testProc
        onExited: page.testing = ""
    }
    function testOut() {
        if (testProc.running) return;
        testing = "out";
        testProc.command = ["sh", "-c", "pw-play --target \"$1\" /usr/share/sounds/freedesktop/stereo/complete.oga || pw-play /usr/share/sounds/freedesktop/stereo/complete.oga", "sh", sink ? sink.name : ""];
        testProc.running = true;
    }
    function testIn() {
        if (testProc.running) return;
        testing = "rec";
        testProc.command = ["sh", "-c",
            "f=\"${XDG_RUNTIME_DIR:-/tmp}/astrax-mic-test.wav\"; timeout 3 pw-record --target \"$1\" \"$f\"; printf play; pw-play \"$f\"; rm -f \"$f\"",
            "sh", source ? source.name : ""];
        testProc.running = true;
        playFlip.restart();
    }
    Timer { id: playFlip; interval: 3100; onTriggered: if (page.testing === "rec") page.testing = "play" }
    Process { id: camProc }
    function camera() {
        if (camProc.running) { camProc.running = false; return; }
        camProc.command = ["ffplay", "-loglevel", "quiet", "-f", "v4l2", "-window_title", "Camera", "-x", "640", "-y", "360", "/dev/video0"];
        camProc.running = true;
    }

    // ================================================================ big mic button
    Item {
        id: micSide
        width: 150; height: parent.height
        Rectangle {
            id: micBtn
            anchors.horizontalCenter: parent.horizontalCenter; y: 6
            width: 84; height: 84; radius: 42
            readonly property color tone: page.micMuted ? page.red : page.live ? page.green : "#3a3a3e"
            color: page.micMuted ? page.red : "transparent"
            border.width: page.micMuted ? 0 : 3
            border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.85)
            Behavior on color { ColorAnimation { duration: 200 } }
            Rectangle {   // soft halo while hearing you
                anchors.centerIn: parent
                width: parent.width + 14; height: width; radius: width / 2
                color: "transparent"; border.width: 6
                border.color: Qt.rgba(page.green.r, page.green.g, page.green.b, 0.18)
                visible: page.live && !page.micMuted
                SequentialAnimation on opacity { running: page.live && !page.micMuted && page.visible; loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine } }
            }
            Text {
                anchors.centerIn: parent
                text: page.micMuted ? "" : ""
                color: "#ffffff"; font.family: page.hub.iconFont; font.pixelSize: 28
            }
            scale: micArea.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            MouseArea { id: micArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.toggleMic() }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: micBtn.bottom; anchors.topMargin: 10
            spacing: 1
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.micMuted ? "Muted" : page.live ? "Hearing you" : "Mic is free"
                color: page.micMuted ? page.red : page.live ? page.green : page.dim
                font.family: page.hub.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.micMuted ? "Click to talk" : "Click to mute"
                color: page.dim; font.family: page.hub.textFont; font.pixelSize: 11
            }
        }
    }

    // ================================================================ right side
    Item {
        anchors.left: micSide.right; anchors.leftMargin: 8; anchors.right: parent.right
        height: parent.height
        Row {
            id: head
            spacing: 10
            Text {
                text: page.clock(page.secs)
                color: page.fg; font.family: "Adwaita Mono"; font.pixelSize: 28; font.weight: Font.Bold
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                height: 22; width: badge.implicitWidth + 24; radius: 11
                readonly property color tone: page.micMuted ? page.red : page.live ? page.green : "#8e8e93"
                color: Qt.rgba(tone.r, tone.g, tone.b, 0.16)
                Rectangle { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: parent.tone }
                Text {
                    id: badge; x: 19; anchors.verticalCenter: parent.verticalCenter
                    text: page.micMuted ? "Muted" : page.live ? "Live" : "No call"
                    color: parent.tone; font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }
        }
        Text {
            anchors.top: head.bottom
            width: parent.width; elide: Text.ElideRight
            text: page.live ? page.users.join(", ") : "No app is using the mic"
            color: page.dim; font.family: page.hub.textFont; font.pixelSize: 12
        }

        component DeviceRow: Item {
            id: dr
            property string glyph: ""
            property string kind: ""            // "Speaker" | "Microphone"
            property var nodes: []
            property var current: null
            property string testLabel: "Test"
            property bool testing: false
            signal picked(var node)
            signal test()
            width: parent ? parent.width : 0; height: 32
            Rectangle {
                id: pickBtn
                height: 30; radius: 15
                width: Math.min(parent.width - testBtn.width - 8, pickRow.implicitWidth + 24)
                color: pickArea.containsMouse || menu.visible ? "#1c1c1f" : "#121214"
                border.width: 1; border.color: "#16ffffff"
                Behavior on color { ColorAnimation { duration: 140 } }
                Row {
                    id: pickRow
                    x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                    Text { text: dr.glyph; color: page.fg; font.family: page.hub.iconFont; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        width: Math.min(implicitWidth, pickBtn.parent.width - testBtn.width - 70); elide: Text.ElideRight
                        text: page.label(dr.current); color: page.fg
                        font.family: page.hub.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text { text: ""; color: page.dim; font.family: page.hub.iconFont; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: pickArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: menu.visible = !menu.visible }
            }
            Rectangle {
                id: testBtn
                anchors.right: parent.right; anchors.verticalCenter: pickBtn.verticalCenter
                height: 28; width: tl.implicitWidth + 24; radius: 14
                color: dr.testing ? "#2c3a2f" : testArea.containsMouse ? "#2a2a2e" : "#1a1a1d"
                Behavior on color { ColorAnimation { duration: 140 } }
                Text { id: tl; anchors.centerIn: parent; text: dr.testLabel; color: dr.testing ? page.green : page.fg; font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                MouseArea { id: testArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dr.test() }
            }
            Rectangle {   // device menu
                id: menu
                visible: false
                z: 50
                y: -height - 4
                width: Math.max(pickBtn.width, 220); radius: 12
                height: Math.min(4, dr.nodes.length) * 30 + 8
                color: "#f0161618"; border.width: 1; border.color: "#2affffff"
                ListView {
                    anchors.fill: parent; anchors.margins: 4; clip: true
                    model: dr.nodes
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width; height: 30; radius: 8
                        color: mArea.containsMouse ? "#2a2a2e" : "transparent"
                        Text {
                            x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 30; elide: Text.ElideRight
                            text: page.label(modelData); color: page.fg; font.family: page.hub.textFont; font.pixelSize: 12
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            visible: dr.current === modelData; text: ""; color: page.green; font.family: page.hub.iconFont; font.pixelSize: 11
                        }
                        MouseArea { id: mArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dr.picked(modelData); menu.visible = false; } }
                    }
                }
            }
        }
        Column {
            anchors.bottom: parent.bottom; width: parent.width; spacing: 6
            DeviceRow {
                z: 3
                glyph: ""; kind: "Speaker"
                nodes: page.sinks; current: page.sink
                testing: page.testing === "out"; testLabel: page.testing === "out" ? "Playing…" : "Test"
                onPicked: n => Pipewire.preferredDefaultAudioSink = n
                onTest: page.testOut()
            }
            DeviceRow {
                z: 2
                glyph: page.micMuted ? "" : ""; kind: "Microphone"
                nodes: page.sources; current: page.source
                testing: page.testing === "rec" || page.testing === "play"
                testLabel: page.testing === "rec" ? "Speak…" : page.testing === "play" ? "Listening…" : "Test"
                onPicked: n => Pipewire.preferredDefaultAudioSource = n
                onTest: page.testIn()
            }
            Rectangle {
                height: 30; width: camRow.implicitWidth + 24; radius: 15
                color: camArea.containsMouse ? "#1c1c1f" : "#121214"; border.width: 1; border.color: "#16ffffff"
                Row {
                    id: camRow; x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Text { text: ""; color: page.fg; font.family: page.hub.iconFont; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: camProc.running ? "Close camera" : "Check camera"; color: page.fg; font.family: page.hub.textFont; font.pixelSize: 13; font.weight: Font.DemiBold }
                }
                MouseArea { id: camArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.camera() }
            }
        }
    }
}
