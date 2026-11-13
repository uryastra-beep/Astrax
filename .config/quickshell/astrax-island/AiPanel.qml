import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// AI monitor inside the island (Super+M): what Claude and Codex are doing right now + their usage.
// Data comes from ai-monitor.py, which only runs while this panel is open (nothing runs when closed).
// States: Thinking… / Working… / Creating… / Needs input / Done. Esc closes.
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

    readonly property int rowH: 42
    readonly property int maxRows: 5
    readonly property int cardH: 136
    readonly property int preferredHeight: 226 + Math.max(1, rows.length) * rowH + 48 + 6

    property var snap: ({})
    property bool loaded: false
    property real nowS: Date.now() / 1000

    readonly property var claude: snap.claude || ({})
    readonly property var codex: snap.codex || ({})
    // both tools in one list: needs-input first, then busy, then by recency
    readonly property var rows: {
        const prio = { attention: 5, limit: 4, creating: 3, thinking: 3, working: 3, idle: 1 };
        const all = [];
        (claude.sessions || []).forEach(s => all.push({ tool: "Claude", s: s }));
        (codex.sessions || []).forEach(s => all.push({ tool: "Codex", s: s }));
        all.sort((a, b) => (prio[b.s.kind] || 0) - (prio[a.s.kind] || 0) || b.s.ts - a.s.ts);
        return all.slice(0, maxRows);
    }

    function kindColor(k) {
        switch (k) {
        case "attention": return "#ff9f0a";
        case "creating": return "#30d158";
        case "thinking": return "#bf5af2";
        case "working": return "#4aa3ff";
        case "limit": return "#ff453a";
        default: return "#8e8e93";
        }
    }
    function busy(k) { return k === "attention" || k === "creating" || k === "thinking" || k === "working"; }
    function ago(ts) {
        const s = Math.max(0, nowS - ts);
        if (s < 10) return "now";
        if (s < 60) return Math.floor(s) + " s";
        if (s < 3600) return Math.floor(s / 60) + " min";
        if (s < 86400) return Math.floor(s / 3600) + " h";
        return Math.floor(s / 86400) + " d";
    }
    function tok(n) {
        n = Number(n) || 0;
        if (n >= 1e6) return (n / 1e6).toFixed(1) + " M";
        if (n >= 1e3) return Math.round(n / 1e3) + " k";
        return String(n);
    }
    function resetIn(ts) {
        const s = ts - nowS;
        if (s <= 0) return "";
        if (s < 3600) return "in " + Math.ceil(s / 60) + " min";
        if (s < 86400) return "in " + Math.floor(s / 3600) + " h " + Math.floor((s % 3600) / 60) + " min";
        return "in " + Math.floor(s / 86400) + " d " + Math.floor((s % 86400) / 3600) + " h";
    }

    Process {
        id: proc
        running: panel.opened
        command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.env("HOME") + "/.config/quickshell/astrax-island/ai-monitor.py"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const d = JSON.parse(data);
                    if (d.error) return;
                    panel.snap = d;
                    panel.loaded = true;
                } catch (e) { }
            }
        }
    }
    Timer { interval: 1000; repeat: true; running: panel.opened; onTriggered: panel.nowS = Date.now() / 1000 }

    Component.onCompleted: { appear.start(); if (opened) focusDelay.restart(); }
    onOpenedChanged: if (opened) focusDelay.restart()
    Timer { id: focusDelay; interval: 80; onTriggered: if (panel.opened) nav.forceActiveFocus() }
    Item {
        id: nav
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { panel.dismissed(); event.accepted = true; }
        }
    }

    // Status text that crossfades with a short blur when it changes.
    component StateLabel: Item {
        id: sl
        property string text: ""
        property color tint: "#f5f5f7"
        property int px: 20
        property string shown: ""
        implicitHeight: px + 6
        clip: false
        onTextChanged: {
            if (shown === "") { shown = text; front.opacity = 1; return; }
            if (text === shown) return;
            back.text = front.text; back.opacity = 1; back.fx = 0;
            front.text = text; shown = text; front.opacity = 0; front.fx = 1;
            swap.restart();
        }
        Text {
            id: back
            property real fx: 0
            width: parent.width; elide: Text.ElideRight
            color: sl.tint; opacity: 0
            font.family: panel.textFont; font.pixelSize: sl.px; font.weight: Font.DemiBold
            layer.enabled: swap.running
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: back.fx }
        }
        Text {
            id: front
            property real fx: 0
            width: parent.width; elide: Text.ElideRight
            text: sl.text; color: sl.tint
            font.family: panel.textFont; font.pixelSize: sl.px; font.weight: Font.DemiBold
            Behavior on color { ColorAnimation { duration: 200 } }
            layer.enabled: swap.running
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 24; blur: front.fx }
        }
        ParallelAnimation {
            id: swap
            NumberAnimation { target: front; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: front; property: "fx"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: back; property: "opacity"; to: 0; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: back; property: "fx"; to: 1; duration: 160; easing.type: Easing.OutCubic }
        }
    }

    // Pulsing status dot (static when idle).
    component StatusDot: Rectangle {
        id: dot
        property string kind: "idle"
        width: 8; height: 8; radius: 4
        color: panel.kindColor(kind)
        Behavior on color { ColorAnimation { duration: 200 } }
        SequentialAnimation on opacity {
            running: panel.opened && panel.busy(dot.kind)
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
        onKindChanged: if (!panel.busy(kind)) opacity = 1
    }

    component UsageBar: Item {
        id: ub
        property string name: ""
        property real pct: 0
        property string note: ""
        property color tint: "#4aa3ff"
        width: parent ? parent.width : 100; height: 16
        Text { id: ubn; text: ub.name; color: "#8e8e93"; width: 34; font.family: panel.textFont; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
            id: track
            anchors.left: ubn.right; anchors.right: ubp.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            height: 4; radius: 2; color: "#1affffff"
            Rectangle {
                height: parent.height; radius: 2
                width: parent.width * Math.max(0, Math.min(1, ub.pct / 100))
                color: ub.pct >= 90 ? "#ff453a" : ub.pct >= 75 ? "#ff9f0a" : ub.tint
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }
        Text { id: ubp; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 62; horizontalAlignment: Text.AlignRight
               text: ub.note !== "" ? ub.note : Math.round(ub.pct) + "%"; color: "#d1d1d6"; font.family: panel.textFont; font.pixelSize: 11 }
    }

    // ---------------------------------------------------------------- Argon chrome
    readonly property color accent: "#ff8a5c"
    function tint(al) { return Qt.rgba(accent.r, accent.g, accent.b, al); }
    ArgonGlow { accent: panel.accent; reach: 140 }
    readonly property string iconDir: Qt.resolvedUrl("control-icons/")
    ArgonHeader {
        id: panelHeader
        glyph: "\u{f06a9}"; title: "AI Monitor"; accent: panel.accent
        textFont: panel.textFont; iconFont: panel.iconFont
        onCloseClicked: panel.dismissed()
    }
    // ------------------------------------------------------------ the two cards
    Row {
        id: cards
        y: panelHeader.height + 8; width: parent.width; spacing: 10
        Repeater {
            model: [
                { name: "Claude", d: panel.claude },
                { name: "Codex", d: panel.codex }
            ]
            Rectangle {
                id: card
                required property var modelData
                readonly property var d: modelData.d
                readonly property bool isCodex: modelData.name === "Codex"
                readonly property bool needs: d.kind === "attention"
                width: (cards.width - cards.spacing) / 2; height: panel.cardH; radius: 16
                readonly property color brand: isCodex ? "#8b9bff" : "#d97757"
                color: "#0c0c0d"
                border.width: 1; border.color: needs ? "#66ff9f0a" : Qt.rgba(brand.r, brand.g, brand.b, 0.16)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#0c0c0d" }
                    GradientStop { position: 0.55; color: "#0e0e0f" }
                    GradientStop { position: 1.0; color: card.needs ? "#33ff9f0a" : Qt.rgba(card.brand.r, card.brand.g, card.brand.b, 0.16) }
                }
                Behavior on color { ColorAnimation { duration: 220 } }
                Behavior on border.color { ColorAnimation { duration: 220 } }

                Row {
                    x: 14; y: 12; spacing: 7
                    Image {
                        width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                        source: panel.iconDir + (card.isCodex ? "codex.png" : "claude-spark.svg")
                        sourceSize: Qt.size(32, 32); smooth: true; mipmap: true
                    }
                    Text { text: card.modelData.name; color: card.brand; font.family: panel.textFont; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.4; anchors.verticalCenter: parent.verticalCenter }
                    StatusDot { kind: card.d.kind || "idle"; anchors.verticalCenter: parent.verticalCenter; visible: panel.loaded }
                }
                // skeleton while the first snapshot arrives (no spinner)
                Column {
                    visible: !panel.loaded
                    x: 14; y: 40; spacing: 10
                    Repeater {
                        model: [96, 140, 110]
                        Rectangle {
                            required property int modelData
                            width: modelData; height: 10; radius: 5; color: "#1affffff"
                            SequentialAnimation on opacity {
                                running: panel.opened && !panel.loaded; loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
                Column {
                    visible: panel.loaded
                    x: 14; y: 34; width: parent.width - 28; spacing: 3
                    StateLabel { width: parent.width; text: card.d.label || ""; tint: panel.kindColor(card.d.kind) }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: {
                            const s = card.d.sessions || [];
                            if (!s.length) return card.isCodex ? "Nothing open" : "No open sessions";
                            const extra = (card.d.count || s.length) - 1;
                            return s[0].name + (extra > 0 ? "  +" + extra : "");
                        }
                        color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 12
                    }
                }
                Column {
                    visible: panel.loaded
                    x: 14; y: 84; width: parent.width - 28; spacing: 4
                    // Codex: real plan limits (5 h / weekly). Claude: tokens used today (no local plan limit).
                    UsageBar { visible: card.isCodex && !!card.d.five; name: "5 h"; pct: card.d.five ? card.d.five.pct : 0
                               note: card.d.five && card.d.five.stale ? "reset" : "" }
                    UsageBar { visible: card.isCodex && !!card.d.week; name: "Week"; pct: card.d.week ? card.d.week.pct : 0 }
                    Text {
                        visible: card.isCodex && !!card.d.week && card.d.week.reset > 0
                        text: "Weekly resets " + panel.resetIn(card.d.week ? card.d.week.reset : 0)
                        color: "#6e6e73"; font.family: panel.textFont; font.pixelSize: 10
                    }
                    Text {
                        visible: !card.isCodex && !!card.d.tokens
                        text: card.d.tokens ? "Today  " + panel.tok(card.d.tokens.out) + " out" : ""
                        color: "#d1d1d6"; font.family: panel.textFont; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        visible: !card.isCodex && !!card.d.tokens
                        text: card.d.tokens ? panel.tok(card.d.tokens["in"]) + " in  ·  " + card.d.tokens.msgs + " replies" : ""
                        color: "#6e6e73"; font.family: panel.textFont; font.pixelSize: 10
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ sessions
    Text {
        id: listTitle
        y: cards.y + panel.cardH + 14
        text: "SESSIONS"; color: panel.tint(0.7)
        font.family: panel.textFont; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6
    }
    Item {
        id: listBox
        y: listTitle.y + 20; width: parent.width
        height: Math.max(1, panel.rows.length) * panel.rowH
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Text {
            visible: panel.loaded && panel.rows.length === 0
            anchors.centerIn: parent
            text: "No active sessions"; color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 13
        }
        Repeater {
            model: panel.rows
            Rectangle {
                required property var modelData
                required property int index
                y: index * panel.rowH; width: listBox.width; height: panel.rowH - 4; radius: 14
                color: modelData.s.kind === "attention" ? "#1fff9f0a" : "transparent"
                Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 200 } }
                StatusDot { x: 12; anchors.verticalCenter: parent.verticalCenter; kind: modelData.s.kind }
                Text {
                    id: rowName
                    anchors.left: parent.left; anchors.leftMargin: 30
                    anchors.right: rowTool.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight; text: modelData.s.name
                    color: "#f5f5f7"; font.family: panel.textFont; font.pixelSize: 13; font.weight: Font.Medium
                }
                Rectangle {
                    id: rowTool
                    anchors.right: rowState.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11; color: "#16ffffff"
                    Image {
                        anchors.centerIn: parent; width: 13; height: 13
                        source: panel.iconDir + (modelData.tool === "Codex" ? "codex.png" : "claude-spark.svg")
                        sourceSize: Qt.size(26, 26); smooth: true; mipmap: true
                    }
                }
                Column {
                    id: rowState
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 96; spacing: 1
                    Text { width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; text: modelData.s.label
                           color: panel.kindColor(modelData.s.kind); font.family: panel.textFont; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Text { width: parent.width; horizontalAlignment: Text.AlignRight; text: panel.ago(modelData.s.ts)
                           color: "#6e6e73"; font.family: panel.textFont; font.pixelSize: 10 }
                }
            }
        }
    }
}
