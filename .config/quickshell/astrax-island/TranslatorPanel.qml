import QtQuick
import Quickshell
import Quickshell.Io

// Translator inside the island (Super+T). No AI: translate-shell (`trans`) through translate.py, Google
// first and Bing as backup. Type or paste, pick the target language, the result appears as you type.
// On open it fills the box with the current selection (primary clipboard) when there is one.
// Ctrl+Enter copies the result and closes. Esc closes.
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
    // kept for the host's bindings; solid black, no glass
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.5
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    signal dismissed()

    readonly property color accent: "#4285f4"   // Google Translate blue
    function tint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }

    readonly property var langs: [
        { c: "en", n: "EN" }, { c: "es", n: "ES" }, { c: "fr", n: "FR" }, { c: "de", n: "DE" }, { c: "pt", n: "PT" },
        { c: "it", n: "IT" }, { c: "ja", n: "JA" }, { c: "ko", n: "KO" }, { c: "zh-CN", n: "ZH" }, { c: "ru", n: "RU" }
    ]
    property string target: "en"
    property string result: ""
    property string engine: ""
    property string error: ""
    property bool busy: false

    // The island grows with the result: the box is as tall as the whole translation (up to 300 px, then it scrolls)
    // and the host reads preferredHeight, so the island expands and shrinks with it. 48 = the loader's margins.
    readonly property int inputH: 84
    readonly property int resultMin: 46
    readonly property real resultH: Math.min(300, Math.max(resultMin, resultText.implicitHeight + 24))
    readonly property int preferredHeight: 48 + panelHeader.height + 2 + inputH + 10 + 30 + 10 + Math.round(resultH)

    // ---------------------------------------------------------------- translate
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                panel.busy = false;
                try {
                    const d = JSON.parse(text);
                    if (d.ok) { panel.result = d.text; panel.engine = d.engine; panel.error = ""; }
                    else { panel.result = ""; panel.error = d.error === "empty" ? "" : "Couldn't translate (" + d.error + ")"; }
                } catch (e) { panel.result = ""; panel.error = "Couldn't translate"; }
            }
        }
    }
    function run() {
        const t = input.text.trim();
        if (t === "") { result = ""; error = ""; busy = false; return; }
        if (proc.running) { again = true; return; }
        busy = true;
        proc.command = ["sh", "-c", "printf '%s' \"$1\" | python3 -I \"$2\" \"$3\"", "sh", t, Quickshell.shellPath("translate.py"), target];
        proc.running = true;
    }
    property bool again: false
    Connections { target: proc; function onRunningChanged() { if (!proc.running && panel.again) { panel.again = false; panel.run(); } } }
    Timer { id: debounce; interval: 450; onTriggered: panel.run() }
    onTargetChanged: if (input.text.trim() !== "") { busy = true; debounce.restart(); }

    // ---------------------------------------------------------------- selection prefill
    Process {
        id: selProc
        command: ["sh", "-c", "timeout 1 wl-paste -p -n 2>/dev/null | head -c 600"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t !== "" && input.text === "") { input.text = t; input.selectAll(); }
            }
        }
    }
    function copyResult() {
        if (result === "") return;
        Quickshell.execDetached(["wl-copy", "--", result]);
        dismissed();
    }

    onOpenedChanged: if (opened) { input.text = ""; result = ""; error = ""; busy = false; selProc.running = true; focusDelay.restart(); }
    Component.onCompleted: { appear.start(); if (opened) { selProc.running = true; focusDelay.restart(); } }
    Timer { id: focusDelay; interval: 80; onTriggered: if (panel.opened) input.forceActiveFocus() }
    Keys.onPressed: event => { if (event.key === Qt.Key_Escape) { panel.dismissed(); event.accepted = true; } }

    ArgonGlow { accent: panel.accent; reach: 130 }
    ArgonHeader {
        id: panelHeader
        glyph: ""; title: "Translate"; accent: panel.accent
        subtitle: panel.engine !== "" && panel.result !== "" ? "via " + panel.engine : "Auto-detects the language"
        textFont: panel.textFont; iconFont: panel.iconFont
        leftGlyph: ""; leftLabel: "Clear"; leftVisible: input.text !== ""
        onLeftClicked: { input.text = ""; input.forceActiveFocus(); }
        onCloseClicked: panel.dismissed()
    }

    // ---------------------------------------------------------------- input
    Rectangle {
        id: inputBox
        y: panelHeader.height + 2; width: parent.width; height: panel.inputH; radius: 18
        color: "#0f0f11"
        border.width: 1; border.color: input.activeFocus ? panel.tint(0.32) : "#18ffffff"
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Flickable {
            anchors.fill: parent; anchors.margins: 12
            contentHeight: input.contentHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            TextEdit {
                id: input
                width: parent.width
                wrapMode: TextEdit.Wrap
                color: "#f5f5f7"; selectionColor: panel.accent; selectedTextColor: "#04122e"
                font.family: panel.textFont; font.pixelSize: 14
                onTextChanged: { if (text.trim() === "") { panel.result = ""; panel.error = ""; panel.busy = false; debounce.stop(); } else { panel.busy = true; debounce.restart(); } }
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { panel.copyResult(); event.accepted = true; }
                    else if (event.key === Qt.Key_Escape) { panel.dismissed(); event.accepted = true; }
                }
                Text {
                    visible: input.text === ""
                    text: "Type or paste text…  Ctrl+Enter copies the result"
                    color: "#7c7c82"; font: input.font
                }
            }
        }
    }

    // ---------------------------------------------------------------- target language
    Row {
        id: chips
        y: inputBox.y + inputBox.height + 10; height: 30; spacing: 4
        anchors.horizontalCenter: parent.horizontalCenter
        Repeater {
            model: panel.langs
            Rectangle {
                required property var modelData
                readonly property bool active: panel.target === modelData.c
                height: 28; width: 40; radius: 14
                color: active ? panel.accent : chipArea.containsMouse ? "#1c1c1f" : "transparent"
                border.width: active ? 0 : 1; border.color: "#18ffffff"
                Behavior on color { ColorAnimation { duration: 160 } }
                Text {
                    anchors.centerIn: parent; text: modelData.n
                    color: parent.active ? "#04122e" : "#d1d1d6"
                    font.family: panel.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.target = modelData.c }
            }
        }
    }

    // ---------------------------------------------------------------- result
    Rectangle {
        id: resultBox
        y: chips.y + chips.height + 10; width: parent.width; height: Math.round(panel.resultH); radius: 18
        color: "#0c0c0d"; border.width: 1; border.color: panel.tint(0.16)
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Column {   // skeleton while translating (no spinner)
            visible: panel.busy && panel.result === ""
            x: 14; y: 14; width: parent.width - 28; spacing: 9
            opacity: 0.5
            SequentialAnimation on opacity { running: parent.visible; loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine } }
            Repeater { model: [1, 0.7]
                Rectangle { required property real modelData; width: parent.width * modelData; height: 8; radius: 4; color: panel.tint(0.28) } }
        }
        Flickable {
            visible: !(panel.busy && panel.result === "")
            anchors.fill: parent; anchors.margins: 12; anchors.rightMargin: 44
            contentHeight: resultText.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            Text {
                id: resultText
                width: parent.width
                text: panel.error !== "" ? panel.error : panel.result !== "" ? panel.result : "The translation shows up here"
                wrapMode: Text.Wrap; textFormat: Text.PlainText
                opacity: panel.busy ? 0.55 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }
                color: panel.error !== "" ? "#ff8a80" : panel.result !== "" ? "#f5f5f7" : "#6e6e73"
                font.family: panel.textFont; font.pixelSize: 15; lineHeight: 1.12
            }
        }
        ArgonIconButton {
            anchors.right: parent.right; anchors.rightMargin: 8; y: 8
            visible: panel.result !== ""
            glyph: ""; accent: panel.accent
            iconFont: panel.iconFont; textFont: panel.textFont
            onClicked: panel.copyResult()
        }
    }
}
