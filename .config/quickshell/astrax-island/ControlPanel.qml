import QtQuick
import Quickshell
import Quickshell.Io

// One-click island panel, Argon style: pure black body that drops from the notch, the assistant's
// logo and "Ask …" centered, a warm glow rising from the bottom and an input bar (+ attach, send).
// Tap the logo (or Tab) to switch between Claude and Codex. Esc closes. Backend: control-ask.sh who "question" [files…].
Item {
    id: panel
    property bool opened: false
    opacity: 0
    scale: 0.97
    transformOrigin: Item.Top
    ParallelAnimation {
        id: appear
        NumberAnimation { target: panel; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: panel; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutQuart }
    }
    // kept for the host's bindings; this panel is solid black, no glass
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.5
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    signal dismissed()
    // true while the file picker is open: the host keeps the panel open and lets the picker take the keyboard
    property bool picking: false
    property real glowRadius: 28   // the island body's corner radius, so the glow follows its rounded bottom

    readonly property string iconDir: Qt.resolvedUrl("control-icons/")

    // ---------------------------------------------------------------- assistant
    property string who: "claude"
    readonly property bool isClaude: who === "claude"
    readonly property var assistants: ["claude", "codex"]
    readonly property color accent: who === "claude" ? "#d97757" : "#8b9bff"
    readonly property string whoName: who === "claude" ? "Claude" : "Codex"
    function tint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }
    function toggleWho() { who = assistants[(assistants.indexOf(who) + 1) % assistants.length]; askField.forceActiveFocus(); }

    // ---------------------------------------------------------------- geometry
    readonly property int heroH: 92
    readonly property int barH: 46
    readonly property int answerMax: 150
    readonly property int chipsH: files.length ? 34 : 0
    property real answerH: (answer !== "" || busy) ? Math.min(answerMax, Math.max(busy ? 46 : 0, answerText.implicitHeight + 22)) + 10 : 0
    Behavior on answerH { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    readonly property int preferredHeight: 48 + heroH + Math.round(answerH) + chipsH + barH

    // ---------------------------------------------------------------- ask
    property string answer: ""
    property bool busy: false
    property var files: []
    Process {
        id: askProc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                panel.answer = t !== "" ? t : "No answer.";
            }
        }
        onExited: code => { if (panel.answer === "") panel.answer = code === 124 ? "Took too long." : "Couldn't answer (error " + code + ")."; panel.busy = false; }
    }
    function ask(q) {
        q = q.trim();
        if (q === "" || panel.busy) return;
        panel.busy = true;
        panel.answer = "";
        askProc.command = ["sh", Quickshell.shellPath("control-ask.sh"), panel.who, q].concat(panel.files);
        askProc.running = true;
        askField.text = "";
        panel.files = [];
    }

    // ---------------------------------------------------------------- attach (+)
    Process {
        id: pickProc
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Attach to " + panel.whoName]
        stdout: StdioCollector {
            onStreamFinished: {
                const add = text.split("\n").map(s => s.trim()).filter(s => s !== "");
                const all = panel.files.slice();
                for (const f of add) if (all.indexOf(f) < 0) all.push(f);
                panel.files = all.slice(0, 6);
            }
        }
        onExited: { panel.picking = false; focusDelay.restart(); }
    }
    function pick() { if (!pickProc.running && !busy) { panel.picking = true; pickProc.running = true; } }
    // Ctrl+V: a file or image on the clipboard is attached for real; plain text pastes as usual.
    Process {
        id: pasteProc
        command: ["sh", Quickshell.shellPath("clip-attach.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const add = text.split("\n").map(s => s.trim()).filter(s => s !== "");
                if (add.length === 0) { askField.paste(); return; }
                const all = panel.files.slice();
                for (const f of add) if (all.indexOf(f) < 0) all.push(f);
                panel.files = all.slice(0, 6);
            }
        }
    }
    function pasteClip() { if (!pasteProc.running && !busy) pasteProc.running = true; else if (busy) askField.paste(); }
    function removeFile(f) { panel.files = panel.files.filter(x => x !== f); }
    function baseName(p) { return p.split("/").pop(); }

    onOpenedChanged: if (opened) focusDelay.restart()
    Component.onCompleted: { appear.start(); if (opened) focusDelay.restart(); }
    Timer { id: focusDelay; interval: 80; onTriggered: if (panel.opened) askField.forceActiveFocus() }
    Keys.onPressed: event => { if (event.key === Qt.Key_Escape) { panel.dismissed(); event.accepted = true; } }

    // ================================================================ warm glow from the bottom edge
    // Reaches past the loader margins to the island's edges (the island body clips it to its outline).
    Rectangle {
        id: glow
        x: -24; width: panel.width + 48
        y: bar.y - 96; height: panel.height - y + 24
        bottomLeftRadius: panel.glowRadius; bottomRightRadius: panel.glowRadius
        gradient: Gradient {
            GradientStop { position: 0.0; color: panel.tint(0) }
            GradientStop { position: 0.45; color: panel.tint(0.07) }
            GradientStop { position: 0.8; color: panel.tint(0.2) }
            GradientStop { position: 1.0; color: panel.tint(0.32) }
        }
    }

    // ================================================================ hero: logo + title
    Item {
        id: hero
        width: parent.width; height: panel.heroH
        Item {
            id: logo
            width: 34; height: 34
            anchors.horizontalCenter: parent.horizontalCenter; y: 12
            scale: logoArea.pressed ? 0.88 : (logoArea.containsMouse ? 1.08 : 1)
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Image {
                anchors.fill: parent
                source: panel.iconDir + "claude-spark.svg"; sourceSize: Qt.size(68, 68); smooth: true
                opacity: panel.isClaude ? 1 : 0
                rotation: panel.isClaude ? 0 : -60
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            }
            Image {
                anchors.fill: parent; anchors.margins: 1
                source: panel.iconDir + "codex.png"; sourceSize: Qt.size(68, 68); smooth: true; mipmap: true
                opacity: panel.who === "codex" ? 1 : 0
                rotation: panel.who === "codex" ? 0 : 60
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: logoArea
                anchors.fill: parent; anchors.margins: -8
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: panel.toggleWho()
            }
        }
        Text {
            id: title
            anchors.horizontalCenter: parent.horizontalCenter; y: 56
            text: panel.busy ? panel.whoName + " is thinking" : "Ask " + panel.whoName
            color: panel.accent
            font.family: panel.textFont; font.pixelSize: 17; font.weight: Font.DemiBold
            Behavior on color { ColorAnimation { duration: 220 } }
        }
    }

    // ================================================================ answer (skeleton while waiting)
    Item {
        id: answerBox
        y: hero.height; width: parent.width
        height: Math.max(0, Math.round(panel.answerH) - 10); clip: true
        opacity: panel.answerH > 12 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Rectangle {
            anchors.fill: parent; radius: 16
            color: "#0c0c0d"; border.width: 1; border.color: panel.tint(0.14)
        }
        // Working line, Claude Code style: a twinkling star, a rotating verb and the seconds waited
        Item {
            id: working
            visible: panel.busy
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
            readonly property var verbs: ["Thinking", "Cooking", "Scheming", "Pondering", "Reasoning", "Spinning ideas",
                "Deciphering", "Mulling", "Connecting dots", "Tuning", "Distilling", "Assembling", "Exploring",
                "Calculating", "Digging in", "Polishing", "Imagining", "Deducing", "Doodling", "Brewing"]
            readonly property var stars: ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
            property int verb: 0
            property int star: 0
            property int secs: 0
            function pickVerb() {
                let n = Math.floor(Math.random() * verbs.length);
                if (n === verb) n = (n + 1) % verbs.length;
                verb = n;
            }
            onVisibleChanged: if (visible) { secs = 0; pickVerb(); verbText.text = verbs[verb] + "…"; }
            Timer { interval: 110; repeat: true; running: working.visible; onTriggered: working.star = (working.star + 1) % working.stars.length }
            Timer { interval: 1000; repeat: true; running: working.visible; onTriggered: working.secs++ }
            Timer { interval: 2600; repeat: true; running: working.visible; onTriggered: { working.pickVerb(); verbSwap.restart(); } }
            Text {
                id: starText
                anchors.verticalCenter: parent.verticalCenter
                width: 16; horizontalAlignment: Text.AlignHCenter
                text: working.stars[working.star]
                color: panel.accent
                font.pixelSize: 16; font.weight: Font.Bold
            }
            Text {
                id: verbText
                anchors.left: starText.right; anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: panel.accent
                font.family: panel.textFont; font.pixelSize: 14; font.weight: Font.Medium
                // soft breathing shimmer
                SequentialAnimation on opacity { running: working.visible && !verbSwap.running; loops: Animation.Infinite
                    NumberAnimation { to: 0.6; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine } }
            }
            SequentialAnimation {
                id: verbSwap
                NumberAnimation { target: verbText; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
                ScriptAction { script: verbText.text = working.verbs[working.verb] + "…" }
                NumberAnimation { target: verbText; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
            Text {
                anchors.left: verbText.right; anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "(" + working.secs + " s)"
                color: "#6e6e73"
                font.family: panel.textFont; font.pixelSize: 11
            }
        }
        Flickable {
            visible: !panel.busy && panel.answer !== ""
            anchors.fill: parent; anchors.margins: 11
            contentHeight: answerText.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            Text {
                id: answerText
                width: parent.width
                text: panel.answer; wrapMode: Text.Wrap; textFormat: Text.PlainText
                color: "#ececf0"; font.family: panel.textFont; font.pixelSize: 13; lineHeight: 1.15
            }
        }
    }

    // ================================================================ attached files
    Flow {
        id: chips
        y: hero.height + Math.round(panel.answerH); width: parent.width
        height: panel.chipsH; spacing: 6; clip: true
        Repeater {
            model: panel.files
            Rectangle {
                required property var modelData
                height: 26; radius: 13
                width: Math.min(170, chipText.implicitWidth + 40)
                color: panel.tint(0.12); border.width: 1; border.color: panel.tint(0.2)
                Text {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    text: ""; color: panel.accent; font.family: panel.iconFont; font.pixelSize: 11
                }
                Text {
                    id: chipText
                    x: 24; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter
                    text: panel.baseName(modelData); elide: Text.ElideMiddle
                    color: "#d8d8dc"; font.family: panel.textFont; font.pixelSize: 11; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter
                    text: "×"; color: chipX.containsMouse ? "#ffffff" : "#8e8e93"; font.pixelSize: 15
                    MouseArea { id: chipX; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.removeFile(modelData) }
                }
            }
        }
    }

    // ================================================================ input bar: + | field | send
    Rectangle {
        id: bar
        anchors.bottom: parent.bottom
        width: parent.width; height: panel.barH; radius: height / 2
        color: "#101012"
        border.width: 1; border.color: askField.activeFocus ? panel.tint(0.3) : panel.tint(0.14)
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Rectangle {   // warm wash over the bar, like the glow it sits in
            anchors.fill: parent; radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: panel.tint(0.10) }
                GradientStop { position: 0.5; color: panel.tint(0.17) }
                GradientStop { position: 1.0; color: panel.tint(0.10) }
            }
        }

        Rectangle {
            id: plusBtn
            x: 7; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 16
            color: plusArea.pressed ? "#33ffffff" : (plusArea.containsMouse ? "#24ffffff" : "#16ffffff")
            Behavior on color { ColorAnimation { duration: 140 } }
            Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: "+"; color: "#ececf0"; font.family: panel.textFont; font.pixelSize: 20; font.weight: Font.Medium }
            MouseArea { id: plusArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.pick() }
        }
        TextInput {
            id: askField
            anchors.left: plusBtn.right; anchors.leftMargin: 10
            anchors.right: sendBtn.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: "#f2f2f5"; selectionColor: panel.accent; clip: true
            cursorDelegate: Rectangle { width: 2; color: panel.accent; radius: 1 }
            font.family: panel.textFont; font.pixelSize: 14
            Keys.onReturnPressed: panel.ask(text)
            Keys.onEnterPressed: panel.ask(text)
            Keys.onEscapePressed: panel.dismissed()
            Keys.onTabPressed: panel.toggleWho()
            Keys.onPressed: event => { if ((event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) { panel.pasteClip(); event.accepted = true; } }
            Text {
                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                visible: askField.text === ""
                text: "Ask " + panel.whoName + "…"
                color: "#7c7c82"; font.family: panel.textFont; font.pixelSize: 14
            }
        }
        Rectangle {
            id: sendBtn
            anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 16
            readonly property bool live: askField.text.trim() !== "" && !panel.busy
            color: live ? (sendArea.pressed ? Qt.darker(panel.accent, 1.2) : panel.accent) : panel.tint(0.22)
            scale: sendArea.pressed && live ? 0.92 : 1
            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Text {
                anchors.centerIn: parent
                text: ""; font.family: panel.iconFont; font.pixelSize: 13
                color: sendBtn.live ? "#140a06" : panel.accent
                Behavior on color { ColorAnimation { duration: 160 } }
            }
            MouseArea { id: sendArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.ask(askField.text) }
        }
    }
}
