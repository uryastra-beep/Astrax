import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris

// Astrax Dynamic Island -- pill at the top-center of the focused monitor.
// Shows notifications, volume / mic / brightness, lock keys, airplane mode,
// charging, Bluetooth and USB events, and the current song. Settings live in
// the "island" key of Serpantinum's settings.json (Super+C > Dynamic Island).
//
// Only the pill takes input (mask); the rest of the layer is click-through.
ShellRoot {
    id: root

    // ------------------------------------------------------------ settings
    property var cfg: ({})
    // off by default: the island is solid black like the real one
    readonly property bool glassCfg: cfg.glass === true
    readonly property real glassAlpha: (cfg.glassOpacity !== undefined ? cfg.glassOpacity : 55) / 100
    readonly property real refraction: (cfg.glassRefraction !== undefined ? cfg.glassRefraction : 60) / 100
    readonly property real bounce: (cfg.bounce !== undefined ? cfg.bounce : 60) / 100
    readonly property int edgeMargin: cfg.topMargin !== undefined ? cfg.topMargin : 4
    // position picked in Super+C (percent of the free space, like the notification picker)
    readonly property real posX: (cfg.posX !== undefined ? cfg.posX : 50) / 100
    readonly property real posY: (cfg.posY !== undefined ? cfg.posY : 0) / 100

    FileView {
        path: Quickshell.env("HOME") + "/.config/serpantinum/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.cfg = (j && j.island) ? j.island : ({});
            } catch (e) { root.cfg = ({}); }
        }
    }

    // ------------------------------------------------------------- palette
    readonly property color fg: "#f5f5f7"
    readonly property color dim: Qt.rgba(1, 1, 1, 0.58)
    readonly property string textFont: "Rubik"
    readonly property string iconFont: "Iosevka Nerd Font"

    // -------------------------------------------------------------- events
    property var current: null
    property var queue: []
    property bool expanded: false       // music card
    property bool notifOpen: false      // notification card shows full body

    Sources {
        cfg: root.cfg
        onEvent: ev => root.push(ev)
    }

    function push(ev) {
        if (root.cfg.enabled === false) return;
        if (ev.coalesce && root.current && root.current.coalesce === ev.coalesce) {
            root.current = Object.assign({}, root.current, ev);
            hold.interval = ev.duration; hold.restart();
            return;
        }
        if (ev.coalesce) {
            // HUDs (volume, brightness) jump the line; what they cover comes back after
            if (root.current && root.current.layout === "notif") root.queue.unshift(root.current);
            root.show(ev);
            return;
        }
        if (root.current) {
            const q = root.queue.slice();
            q.push(ev);
            root.queue = q.slice(-8);
        } else root.show(ev);
    }
    // ---- click-back into Serpantinum (it owns the real notification objects) ----
    readonly property string srpShell: Quickshell.env("HOME") + "/.local/share/serpantinum/src/quickshell/Shell.qml"
    function srpCall(fn, args) {
        Quickshell.execDetached(["quickshell", "ipc", "-p", root.srpShell, "call", "island", fn].concat(args.map(String)));
    }
    function activateCurrent() {
        const ev = root.current;
        if (!ev) return;
        if (ev.kind === "track") root.expanded = true;
        else if (ev.uid !== undefined) root.srpCall("activate", [ev.uid]);
        root.next();
    }
    function dismissCurrent() {
        const ev = root.current;
        if (ev && ev.uid !== undefined) root.srpCall("dismiss", [ev.uid]);
        root.next();
    }
    function show(ev) {
        root.notifOpen = false;
        root.current = ev;
        hold.interval = ev.duration || 2500;
        hold.restart();
    }
    function next() {
        root.notifOpen = false;
        if (root.queue.length) {
            const q = root.queue.slice();
            const ev = q.shift();
            root.queue = q;
            root.show(ev);
        } else root.current = null;
    }
    Timer { id: hold; onTriggered: root.next() }

    // --------------------------------------------------------------- music
    readonly property var player: {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].isPlaying) return list[i];
        return list.length ? list[0] : null;
    }
    readonly property bool hasMusic: cfg.showMusic !== false && player !== null && (player.trackTitle || "") !== ""

    property string lastTrack: ""
    readonly property string trackTitle: player ? (player.trackTitle || "") : ""
    onTrackTitleChanged: {
        if (!hasMusic || trackTitle === "" || trackTitle === lastTrack) return;
        const first = lastTrack === "";
        lastTrack = trackTitle;
        if (first || !player.isPlaying) return;
        push({ kind: "track", layout: "notif", coalesce: "track", app: "Now Playing", title: trackTitle,
               detail: player.trackArtist || "", icon: player.trackArtUrl || "", duration: 3000 });
    }

    // ---------------------------------------------------------------- mode
    readonly property string mode: current ? current.layout
        : (expanded && hasMusic) ? "musicExpanded" : hasMusic ? "music" : "idle"

    function iconSource(icon) {
        if (!icon) return "";
        // Quickshell hands image-path hints over as image://icon/<path or name>
        if (icon.startsWith("image://icon/")) return root.iconSource(icon.substring(13));
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.indexOf("://") > 0) return icon.startsWith("image://") ? "" : icon;
        return Quickshell.iconPath(icon, true) || "";
    }

    PanelWindow {
        id: win
        screen: {
            const s0 = Quickshell.screens[0];
            if (root.cfg.followFocus === false) return s0;
            const fm = Hyprland.focusedMonitor;
            const s = fm ? Quickshell.screens.find(x => x.name === fm.name) : null;
            return s || s0;
        }

        WlrLayershell.namespace: "astrax-island"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // the whole screen is the canvas; only the pill takes input (mask)
        anchors { top: true; bottom: true; left: true; right: true }
        visible: root.cfg.enabled !== false && !(root.cfg.hideWhenIdle === true && root.mode === "idle")
        mask: Region { item: pill }

        Rectangle {
            id: pill
            // The pill is pinned by its horizontal centre and its top edge, computed
            // from a fixed reference size (not the animated one), so it grows
            // symmetrically in place instead of sliding sideways while it springs.
            readonly property real refW: 430
            readonly property real refH: 150
            property real cx: root.edgeMargin + refW / 2 + root.posX * Math.max(0, parent.width - refW - 2 * root.edgeMargin)
            property real topY: root.edgeMargin + root.posY * Math.max(0, parent.height - refH - 2 * root.edgeMargin)
            Behavior on cx { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on topY { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            x: cx - width / 2
            y: topY

            readonly property bool glassOn: root.glassCfg && (root.mode === "notif" || root.mode === "musicExpanded")
            readonly property real notifH: Math.max(68, notifCol.implicitHeight + 28)

            // compact states keep the pill's height and only get wider (like the
            // real island); notifications and the music card grow downwards
            readonly property real targetW: ({ idle: 126, music: 250, hud: 300, status: 320, notif: 410, musicExpanded: 430 })[root.mode]
            readonly property real targetH: ({ idle: 34, music: 34, hud: 34, status: 34, notif: notifH, musicExpanded: 136 })[root.mode]
            width: targetW
            height: targetH
            radius: height <= 40 ? height / 2 : 34
            clip: true

            color: glassOn ? Qt.rgba(0.08, 0.08, 0.1, root.glassAlpha) : "#000000"
            Behavior on color { ColorAnimation { duration: 260 } }

            // springs: a little overshoot on the way out, settles on its own
            readonly property real damp: 0.78 - 0.56 * root.bounce
            Behavior on width { SpringAnimation { spring: 4.2; damping: pill.damp; epsilon: 0.3; mass: 0.9 } }
            Behavior on height { SpringAnimation { spring: 4.2; damping: pill.damp; epsilon: 0.3; mass: 0.9 } }

            // bubble: swells a little under the pointer, more while pressed, and
            // wobbles back on release (taller than wide, like a soap bubble)
            property real bx: touch.pressed ? 1.06 : touch.containsMouse ? 1.025 : 1.0
            property real by: touch.pressed ? 1.12 : touch.containsMouse ? 1.04 : 1.0
            Behavior on bx { SpringAnimation { spring: 6; damping: 0.18; epsilon: 0.001 } }
            Behavior on by { SpringAnimation { spring: 5; damping: 0.16; epsilon: 0.001 } }
            transform: Scale {
                origin.x: pill.width / 2
                origin.y: pill.height / 2
                xScale: pill.bx
                yScale: pill.by
            }

            // ---- liquid glass refraction: lens at the rim, fed by a snapshot of the screen ----
            ScreencopyView {
                id: snap
                captureSource: win.screen
                live: false
                visible: false
                width: win.width; height: win.height
            }
            Connections {
                target: pill
                function onGlassOnChanged() { if (pill.glassOn) snap.captureFrame(); }
            }
            ShaderEffect {
                id: lens
                anchors.fill: parent
                visible: pill.glassOn && snap.hasContent && root.refraction > 0
                property var src: snap
                property real radius: pill.radius
                property real strength: root.refraction
                property real band: 20
                property vector2d size: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(pill.x, pill.y)
                property vector2d screen: Qt.vector2d(win.width, win.height)
                fragmentShader: Qt.resolvedUrl("glass.frag.qsb")
            }

            // ---- liquid glass finish: top specular + rim light ----
            Rectangle {
                anchors.fill: parent
                radius: pill.radius
                opacity: pill.glassOn ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260 } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                    GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.03) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.07) }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: pill.radius
                color: "transparent"
                border.width: 1
                border.color: pill.glassOn ? Qt.rgba(1, 1, 1, 0.26) : "transparent"
                Behavior on border.color { ColorAnimation { duration: 260 } }
            }

            // ---- input ----
            MouseArea {
                id: touch
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: (root.mode === "notif" || root.mode === "music") ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: if (root.current) { hold.stop(); if (root.mode === "notif") root.notifOpen = true; }
                onExited: {
                    root.notifOpen = false;
                    if (root.current) { hold.interval = 1200; hold.restart(); }
                }
                onClicked: m => {
                    if (root.mode === "notif") {
                        if (m.button === Qt.RightButton) root.dismissCurrent();
                        else root.activateCurrent();
                    } else if (!root.current) {
                        if (m.button === Qt.RightButton && root.player) root.player.togglePlaying();
                        else if (root.hasMusic) root.expanded = !root.expanded;
                    }
                }
            }

            // =================== music (compact) ===================
            Item {
                id: musicView
                readonly property bool on: root.mode === "music"
                anchors.fill: parent
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.9
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: on ? 220 : 110 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                RoundedImage {
                    id: miniArt
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 12
                    source: root.player ? root.player.trackArtUrl : ""
                }
                Text {
                    anchors.left: miniArt.right; anchors.leftMargin: 9
                    anchors.right: eq.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.player ? root.player.trackTitle : ""
                    color: root.fg; elide: Text.ElideRight
                    font.family: root.textFont; font.pixelSize: 13; font.weight: Font.Medium
                }
                Row {
                    id: eq
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            width: 3; radius: 1.5; color: root.fg
                            anchors.verticalCenter: parent.verticalCenter
                            height: 5
                            SequentialAnimation on height {
                                running: musicView.on && root.player !== null && root.player.isPlaying
                                loops: Animation.Infinite
                                NumberAnimation { to: 15; duration: 260 + index * 80; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 5; duration: 300 + index * 60; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
            }

            // =================== HUD: icon + bar + value ===================
            Item {
                id: hudView
                readonly property bool on: root.mode === "hud"
                anchors.fill: parent
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.9
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: on ? 220 : 110 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                readonly property var ev: root.current && root.current.layout === "hud" ? root.current : null
                readonly property real level: ev && ev.value !== undefined ? Math.max(0, Math.min(1, ev.value)) : 0

                // glyph gives a small kick every time the level changes
                Text {
                    id: hudGlyph
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    text: hudView.ev ? hudView.ev.glyph : ""
                    color: hudView.ev && hudView.ev.accent ? hudView.ev.accent : root.fg
                    font.family: root.iconFont; font.pixelSize: 17
                    horizontalAlignment: Text.AlignHCenter
                    transformOrigin: Item.Center
                    SequentialAnimation on scale {
                        id: kick
                        running: false
                        NumberAnimation { to: 1.22; duration: 90; easing.type: Easing.OutQuad }
                        SpringAnimation { to: 1.0; spring: 5; damping: 0.3 }
                    }
                }
                Connections {
                    target: hudView
                    function onLevelChanged() { if (hudView.on) kick.restart(); }
                }
                Rectangle {
                    id: track
                    anchors.left: hudGlyph.right; anchors.leftMargin: 10
                    anchors.right: hudVal.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 5; radius: 2.5; color: Qt.rgba(1, 1, 1, 0.16)
                    Rectangle {
                        height: parent.height; radius: 2.5
                        color: hudView.ev && hudView.ev.accent && hudView.ev.accent !== "#ffffff" ? hudView.ev.accent : "#ffffff"
                        width: Math.max(height, track.width * hudView.level)
                        opacity: hudView.level > 0 ? 1 : 0
                        Behavior on width { SpringAnimation { spring: 6; damping: 0.55; epsilon: 0.2 } }
                    }
                }
                Text {
                    id: hudVal
                    anchors.right: parent.right; anchors.rightMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26; horizontalAlignment: Text.AlignRight
                    text: hudView.ev ? (hudView.ev.detail || "") : ""
                    color: root.fg
                    font.family: root.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }

            // =================== status: glyph + title + detail ===================
            Item {
                id: statusView
                readonly property bool on: root.mode === "status"
                anchors.fill: parent
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.9
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: on ? 220 : 110 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                Text {
                    id: stGlyph
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    text: root.current && root.current.layout === "status" ? root.current.glyph : ""
                    color: root.current && root.current.accent ? root.current.accent : root.fg
                    font.family: root.iconFont; font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    anchors.left: stGlyph.right; anchors.leftMargin: 12
                    anchors.right: stDetail.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current && root.current.layout === "status" ? root.current.title : ""
                    color: root.fg; elide: Text.ElideRight
                    font.family: root.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Text {
                    id: stDetail
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current && root.current.layout === "status" ? (root.current.detail || "") : ""
                    color: root.current && root.current.accent ? root.current.accent : root.dim
                    font.family: root.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }

            // =================== notification card ===================
            Item {
                id: notifView
                readonly property bool on: root.mode === "notif"
                anchors.fill: parent
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.8
                transformOrigin: Item.Top
                visible: opacity > 0.01
                // content arrives a beat after the pill starts growing
                Behavior on opacity { SequentialAnimation {
                    PauseAnimation { duration: notifView.on ? 90 : 0 }
                    NumberAnimation { duration: notifView.on ? 240 : 100 }
                } }
                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

                readonly property var ev: root.current && root.current.layout === "notif" ? root.current : null
                readonly property string iconSrc: ev ? root.iconSource(ev.image || ev.icon) : ""

                Rectangle {
                    id: nIcon
                    x: 14; y: 14
                    width: 40; height: 40; radius: 10
                    color: Qt.rgba(1, 1, 1, 0.12)
                    RoundedImage {
                        anchors.fill: parent; radius: 10
                        source: notifView.iconSrc
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: notifView.iconSrc === ""
                        text: notifView.ev && notifView.ev.app ? notifView.ev.app.charAt(0).toUpperCase() : "!"
                        color: root.fg; font.family: root.textFont; font.pixelSize: 18; font.weight: Font.Bold
                    }
                }
                Column {
                    id: notifCol
                    x: 14 + 40 + 12; y: 14
                    width: 410 - 14 - 40 - 12 - 16
                    spacing: 2
                    Row {
                        spacing: 6
                        Text {
                            text: notifView.ev ? notifView.ev.app.toUpperCase() : ""
                            color: root.dim
                            font.family: root.textFont; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6
                        }
                        Rectangle {
                            visible: notifView.ev !== null && notifView.ev.urgent === true
                            width: 6; height: 6; radius: 3; color: "#ff453a"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Text {
                        width: parent.width
                        text: notifView.ev ? notifView.ev.title : ""
                        color: root.fg; elide: Text.ElideRight; maximumLineCount: 1
                        font.family: root.textFont; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: notifView.ev ? notifView.ev.detail.replace(/<[^>]*>/g, "") : ""
                        color: Qt.rgba(1, 1, 1, 0.78)
                        wrapMode: Text.Wrap; elide: Text.ElideRight
                        maximumLineCount: root.notifOpen ? 7 : 2
                        font.family: root.textFont; font.pixelSize: 13
                    }
                    Row {
                        id: chips
                        spacing: 8
                        topPadding: visible ? 6 : 0
                        readonly property var list: (notifView.ev && notifView.ev.actions)
                            ? notifView.ev.actions.filter(a => a.id !== "default" && a.text !== "").slice(0, 3) : []
                        visible: list.length > 0
                        Repeater {
                            model: chips.list
                            Rectangle {
                                required property var modelData
                                height: 26; width: chipText.implicitWidth + 24; radius: 13
                                color: chipArea.pressed ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: modelData.text; color: root.fg
                                    font.family: root.textFont; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                MouseArea {
                                    id: chipArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (notifView.ev && notifView.ev.uid !== undefined) root.srpCall("action", [notifView.ev.uid, modelData.id]);
                                        root.next();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================== music (expanded) ===================
            Item {
                id: bigMusic
                readonly property bool on: root.mode === "musicExpanded"
                anchors.fill: parent
                anchors.margins: 16
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.94
                visible: opacity > 0.01
                Behavior on opacity { SequentialAnimation {
                    PauseAnimation { duration: bigMusic.on ? 90 : 0 }
                    NumberAnimation { duration: bigMusic.on ? 240 : 100 }
                } }
                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                RoundedImage {
                    id: bigArt
                    width: 72; height: 72; radius: 14
                    source: root.player ? root.player.trackArtUrl : ""
                }
                Column {
                    anchors.left: bigArt.right; anchors.leftMargin: 14
                    anchors.right: parent.right; anchors.top: parent.top
                    spacing: 2
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.player ? root.player.trackTitle : ""
                        color: root.fg
                        font.family: root.textFont; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.player ? root.player.trackArtist : ""
                        color: root.dim
                        font.family: root.textFont; font.pixelSize: 13
                    }
                    Row {
                        spacing: 30
                        topPadding: 10
                        Repeater {
                            model: [
                                { t: "󰒮", a: "prev" },
                                { t: root.player && root.player.isPlaying ? "󰏤" : "󰐊", a: "toggle" },
                                { t: "󰒭", a: "next" }
                            ]
                            Text {
                                required property var modelData
                                text: modelData.t; color: root.fg
                                font.family: root.iconFont; font.pixelSize: 24
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -8
                                    onClicked: {
                                        if (!root.player) return;
                                        if (modelData.a === "prev") root.player.previous();
                                        else if (modelData.a === "next") root.player.next();
                                        else root.player.togglePlaying();
                                    }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                    height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.2)
                    Rectangle {
                        height: parent.height; radius: 2; color: "#ffffff"
                        width: root.player && root.player.length > 0 ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                    }
                }
                Timer {
                    interval: 1000; repeat: true
                    running: bigMusic.on && root.player !== null && root.player.isPlaying
                    onTriggered: root.player.positionChanged()
                }
            }
        }
    }
}
