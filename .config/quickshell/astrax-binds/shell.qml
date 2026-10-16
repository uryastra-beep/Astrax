pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Bind search (SUPER + I). Data lives in binds.json (same folder).
ShellRoot {
    id: root
    property bool open: false
    property string query: ""
    property var all: []
    property var results: []
    property int sel: 0
    // session filter: Serpantinum (default) / Caelestia / All
    readonly property var shells: ["Serpantinum", "Caelestia", "All"]
    property string shellFilter: "Serpantinum"
    onShellFilterChanged: refresh()
    function cycleShell(d) {
        const i = root.shells.indexOf(root.shellFilter);
        root.shellFilter = root.shells[(i + d + root.shells.length) % root.shells.length];
    }

    function move(d) { root.sel = Math.max(0, Math.min(root.results.length - 1, root.sel + d)); }

    function norm(s) { return (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, ""); }
    function refresh() {
        const words = norm(query).split(/\s+/).filter(w => w.length);
        root.results = root.all.filter(b => {
            if (root.shellFilter !== "All" && b.session !== root.shellFilter) return false;
            const hay = norm(b.keys + " " + b.desc + " " + b.group + " " + b.session);
            return words.every(w => hay.indexOf(w) >= 0);
        });
        root.sel = 0;
    }
    onQueryChanged: refresh()
    onAllChanged: refresh()
    onOpenChanged: if (open) { query = ""; search.text = ""; shellFilter = "Serpantinum"; }


    // theme: Serpantinum's REAL tokens, same block as astrax-launcher
    // (Catppuccin defaults, overridden by matugen or by the static preset in
    // ~/.config/serpantinum/settings.json > theme)
    QtObject {
        id: theme
        property color base: "#1e1e2e"
        property color mantle: "#181825"
        property color crust: "#11111b"
        property color text: "#cdd6f4"
        property color subtext0: "#a6adc8"
        property color subtext1: "#bac2de"
        property color surface0: "#313244"
        property color surface1: "#45475a"
        property color surface2: "#585b70"
        property color mauve: "#cba6f7"
        property real borderRadius: 8
        readonly property real cornerRadius: borderRadius <= 16
            ? borderRadius * 2
            : Math.min(32, 32 - 16 * Math.exp(-(borderRadius - 16) / 12))
        property string fontFamily: "Adwaita Mono"
    }

    function applySerpColors(c) {
        if (!c) return;
        const set = (k, v) => {
            if (!v) return;
            theme[k] = Qt.color(v.startsWith("#") ? v : "#" + v);
        };
        for (const k of ["base", "mantle", "crust", "text", "subtext0", "subtext1",
                         "surface0", "surface1", "surface2", "mauve"])
            set(k, c[k]);
    }

    property bool matugenMode: true

    FileView {
        path: `${Quickshell.env("HOME")}/.config/serpantinum/settings.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = JSON.parse(text()).theme || {};
                if (t.fontFamily) theme.fontFamily = t.fontFamily;
                if (t.borderRadius !== undefined) theme.borderRadius = t.borderRadius;
                root.matugenMode = t.matugen !== false;
                if (!root.matugenMode && t.colors) root.applySerpColors(t.colors);
            } catch (e) {}
        }
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/serpantinum/qs_matugen_colors.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (!root.matugenMode) return;
            try {
                const c = JSON.parse(text());
                root.applySerpColors(c && c.colors ? c.colors : c);
            } catch (e) {}
        }
    }

    FileView {
        path: Qt.resolvedUrl("binds.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.all = JSON.parse(text()); } catch (e) { root.all = []; } }
    }

    IpcHandler {
        target: "binds"
        function toggle(): void { root.open = !root.open; }
        function show(): void { root.open = true; }
        function hide(): void { root.open = false; }
        // open with a prefilled query (e.g. qs ipc -c astrax-binds call binds find "color")
        function find(q: string): void { root.open = true; search.text = q; }
    }

    // same card/bubble/animations as astrax-launcher, but centered
    PanelWindow {
        id: win
        visible: root.open || win.openProg > 0.001
        color: "transparent"
        exclusiveZone: 0
        anchors { left: true; right: true; top: true; bottom: true }
        WlrLayershell.namespace: "astrax-binds"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        property real openProg: root.open ? 1 : 0
        Behavior on openProg {
            NumberAnimation {
                duration: root.open ? 340 : 150
                easing.type: root.open ? Easing.OutBack : Easing.InQuad
                easing.overshoot: root.open ? 1.28 : 1.0
            }
        }

        onVisibleChanged: if (visible) { keyHandler.forceActiveFocus(); grabTimer.restart(); }

        Timer {
            id: grabTimer
            interval: 60
            onTriggered: grab.active = Qt.binding(() => root.open)
        }
        HyprlandFocusGrab {
            id: grab
            windows: [win]
            onCleared: root.open = false
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }

        Item {
            id: keyHandler
            anchors.fill: parent
            focus: true
            Keys.onTabPressed: root.cycleShell(1)
            Keys.onBacktabPressed: root.cycleShell(-1)
            Keys.onEscapePressed: root.open = false
            Keys.onUpPressed: root.move(-1)
            Keys.onDownPressed: root.move(1)
            Keys.onReturnPressed: root.open = false
            Keys.onEnterPressed: root.open = false
            Keys.onPressed: event => {
                if (event.text.length === 1 && event.text >= " " && !search.activeFocus) {
                    search.text += event.text;
                    search.forceActiveFocus();
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 40)
            // height follows the result count (52px rows + 2px spacing), centered;
            // capped at the max size, scrolls beyond that
            readonly property int rowsH: Math.max(1, root.results.length) * 54 - 2
            height: Math.min(Math.min(540, parent.height - 40), 10 + 38 + 8 + rowsH + 10)
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            radius: theme.cornerRadius
            color: theme.base
            border.width: 1
            border.color: Qt.alpha(theme.surface2, 0.6)

            // entrance: slight rise + fade, with the same jelly wobble
            // as the launcher (pivot at the center instead of the left edge)
            opacity: win.openProg
            transform: [
                Translate { y: (1 - win.openProg) * 40 },
                Scale {
                    id: jelly
                    origin.x: card.width / 2
                    origin.y: card.height / 2
                    xScale: 1
                    yScale: 1
                }
            ]
            Connections {
                target: root
                function onOpenChanged(): void { jellyAnim.restart(); }
            }
            SequentialAnimation {
                id: jellyAnim
                ParallelAnimation {
                    NumberAnimation { target: jelly; property: "yScale"; to: root.open ? 1.08 : 0.94; duration: 90; easing.type: Easing.OutQuad }
                    NumberAnimation { target: jelly; property: "xScale"; to: root.open ? 0.94 : 1.06; duration: 90; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: jelly; property: "yScale"; to: 1.0; duration: 420; easing.type: Easing.OutElastic; easing.amplitude: 1.0; easing.period: 0.42 }
                    NumberAnimation { target: jelly; property: "xScale"; to: 1.0; duration: 420; easing.type: Easing.OutElastic; easing.amplitude: 1.0; easing.period: 0.42 }
                }
            }

            MouseArea { anchors.fill: parent }

            WheelHandler {
                target: null
                onWheel: event => {
                    if (event.angleDelta.y > 0) root.move(-1);
                    else if (event.angleDelta.y < 0) root.move(1);
                    event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: search
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    placeholderText: "Search binds…"
                    color: theme.text
                    placeholderTextColor: theme.subtext0
                    font.family: theme.fontFamily
                    font.pixelSize: 14
                    leftPadding: 14
                    rightPadding: 14
                    background: Rectangle {
                        radius: theme.borderRadius
                        color: search.activeFocus ? Qt.darker(theme.surface0, 1.14) : theme.surface0
                        Behavior on color { ColorAnimation { duration: 180 } }
                        border.width: search.activeFocus ? 1 : 0
                        border.color: theme.mauve
                    }
                    onTextChanged: root.query = text
                    Keys.onTabPressed: root.cycleShell(1)
                    Keys.onBacktabPressed: root.cycleShell(-1)
                    Keys.onEscapePressed: root.open = false
                    Keys.onUpPressed: root.move(-1)
                    Keys.onDownPressed: root.move(1)
                    Keys.onReturnPressed: root.open = false
                    Keys.onEnterPressed: root.open = false
                }

                // shell selector (top-right corner); Tab/Shift+Tab or click
                Rectangle {
                    id: shellSwitch
                    Layout.preferredHeight: 38
                    Layout.preferredWidth: shellRow.implicitWidth + 8
                    radius: theme.borderRadius
                    color: theme.surface0

                    Rectangle {
                        id: shellPill
                        readonly property Item target: shellRep.count ? shellRep.itemAt(root.shells.indexOf(root.shellFilter)) : null
                        y: 4
                        height: parent.height - 8
                        x: target ? target.x + shellRow.x : 4
                        width: target ? target.width : 0
                        radius: Math.max(4, theme.borderRadius - 2)
                        color: theme.mauve
                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }

                    Row {
                        id: shellRow
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            id: shellRep
                            model: root.shells
                            delegate: Item {
                                id: shellOpt
                                required property string modelData
                                readonly property bool active: root.shellFilter === modelData
                                width: optText.implicitWidth + 20
                                height: 30
                                Text {
                                    id: optText
                                    anchors.centerIn: parent
                                    text: shellOpt.modelData
                                    color: shellOpt.active ? theme.crust : theme.subtext0
                                    font.family: theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: shellOpt.active ? Font.Bold : Font.Medium
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                TapHandler { onTapped: root.shellFilter = shellOpt.modelData }
                            }
                        }
                    }
                }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        id: bubble
                        z: 0
                        visible: !!list.currentItem
                        width: list.width
                        height: list.currentItem ? list.currentItem.height : 52
                        radius: theme.borderRadius
                        color: theme.mauve
                        readonly property real rawY: list.currentItem ? (list.currentItem.y - list.contentY) : 0
                        readonly property bool atEdge: rawY < 0 || rawY > (list.height - height)
                        y: Math.max(0, Math.min(list.height - height, rawY))
                        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        transform: Scale {
                            id: stretch
                            origin.x: bubble.width / 2
                            origin.y: bubble.height / 2
                            xScale: 1
                            yScale: 1
                        }
                        Connections {
                            target: list
                            function onCurrentIndexChanged(): void { if (!bubble.atEdge) pulse.restart(); }
                        }
                        SequentialAnimation {
                            id: pulse
                            ParallelAnimation {
                                NumberAnimation { target: stretch; property: "yScale"; to: 1.35; duration: 90; easing.type: Easing.OutQuad }
                                NumberAnimation { target: stretch; property: "xScale"; to: 0.85; duration: 90; easing.type: Easing.OutQuad }
                            }
                            ParallelAnimation {
                                NumberAnimation { target: stretch; property: "yScale"; to: 1.0; duration: 260; easing.type: Easing.OutElastic; easing.amplitude: 0.6; easing.period: 0.5 }
                                NumberAnimation { target: stretch; property: "xScale"; to: 1.0; duration: 260; easing.type: Easing.OutElastic; easing.amplitude: 0.6; easing.period: 0.5 }
                            }
                        }
                    }

                    ListView {
                        id: list
                        z: 1
                        anchors.fill: parent
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: false
                        model: root.results
                        currentIndex: root.sel
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Item {
                            id: entry
                            required property var modelData
                            required property int index
                            readonly property bool isSelected: index === root.sel
                            width: ListView.view.width
                            height: 52

                            HoverHandler { onHoveredChanged: if (hovered) root.sel = entry.index }
                            TapHandler { id: entryTap; onTapped: root.sel = entry.index }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 10
                                spacing: 12
                                scale: entryTap.pressed ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                // "icon" box holding the key combo
                                Rectangle {
                                    Layout.preferredWidth: 196
                                    Layout.preferredHeight: 40
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: Math.max(4, theme.borderRadius)
                                    color: entry.isSelected
                                        ? Qt.tint(theme.surface2, Qt.rgba(theme.mauve.r, theme.mauve.g, theme.mauve.b, 0.2))
                                        : theme.surface2
                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    Text {
                                        id: keysT
                                        anchors.centerIn: parent
                                        width: Math.min(implicitWidth, 184)
                                        elide: Text.ElideRight
                                        text: entry.modelData.keys
                                        color: theme.mauve
                                        font.family: theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                        scale: entry.isSelected ? 1.06 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 0
                                    Text {
                                        Layout.fillWidth: true
                                        text: entry.modelData.desc
                                        color: entry.isSelected ? theme.crust : theme.text
                                        font.family: theme.fontFamily
                                        font.pixelSize: 14
                                        font.weight: entry.isSelected ? Font.Bold : Font.Medium
                                        elide: Text.ElideRight
                                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: entry.modelData.group + " · " + entry.modelData.session
                                        color: entry.isSelected ? theme.crust : theme.subtext0
                                        opacity: entry.isSelected ? 0.9 : 0.85
                                        font.family: theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
