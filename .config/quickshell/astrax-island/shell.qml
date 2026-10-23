import QtQuick
import QtQuick.Shapes
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
    property bool listOpen: false       // notification list (triple-click)
    property var listItems: []          // notifications, from Serpantinum
    property var activity: []           // files / clipboard / device events seen by the island
    property int activityId: 0
    // one list for everything, newest first
    readonly property var allItems: {
        const ev = root.activity.map(a => Object.assign({ kind: "event" }, a));
        return root.listItems.concat(ev).sort((a, b) => b.ts - a.ts).slice(0, 30);
    }
    readonly property var stateColors: ({ progress: "#0a84ff", done: "#30d158", canceled: "#ff453a", added: "#30d158",
                                          modified: "#ff9f0a", deleted: "#ff453a", renamed: "#0a84ff", batch: "#0a84ff",
                                          copied: "#0a84ff", cut: "#ff9f0a", pasted: "#30d158" })
    // what the list remembers: file, clipboard and device events (volume/brightness HUDs and live progress are too noisy)
    function record(ev) {
        if (ev.layout === "hud" || ev.layout === "notif" || ev.state === "progress") return;
        if (ev.layout !== "file" && ev.layout !== "status") return;
        const a = root.activity.slice();
        a.unshift({ id: ++root.activityId, ts: Date.now(), summary: ev.name || ev.title || "", body: ev.sub || ev.detail || "",
                    glyph: ev.glyph || "", thumb: ev.thumb || "", openPath: ev.openPath || ev.path || "",
                    accent: ev.layout === "status" ? (ev.accent || "#ffffff") : (root.stateColors[ev.state] || "#ffffff") });
        root.activity = a.slice(0, 40);
    }
    property var clickTimes: []
    property bool expanded: false       // music card
    property bool notifOpen: false      // notification card shows full body

    Sources {
        cfg: root.cfg
        onEvent: ev => root.push(ev)
    }
    FileSources {
        cfg: root.cfg
        onEvent: ev => root.push(ev)
    }
    ClipSources {
        id: clipSrc
        cfg: root.cfg
        onEvent: ev => root.push(ev)
    }

    function push(ev) {
        if (root.cfg.enabled === false) return;
        root.record(ev);
        if (root.listOpen) {
            // the list is open: events wait their turn and show when it closes
            const q = root.queue.slice();
            if (ev.replaceKey) { const i = q.findIndex(x => x.replaceKey === ev.replaceKey); if (i >= 0) q.splice(i, 1); }
            q.push(ev);
            root.queue = q.slice(-8);
            return;
        }
        // file cards replace each other in place (a download going from progress to done)
        if (ev.replaceKey && root.current && root.current.replaceKey === ev.replaceKey) {
            root.current = ev;
            hold.interval = ev.duration || 2500; hold.restart();
            return;
        }
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
    // tapping a file card goes straight to the file in the file manager (HIG: open the related place)
    function openPath(path, dirOnly) {
        if (!path) return;
        const dir = path.substring(0, path.lastIndexOf("/"));
        Quickshell.execDetached(["sh", "-c",
            "if [ \"$2\" != 1 ] && [ -e \"$1\" ] && command -v nautilus >/dev/null; then nautilus --select \"$1\"; else xdg-open \"$3\"; fi",
            "_", path, dirOnly ? "1" : "0", dir]);
    }
    function activateCurrent() {
        const ev = root.current;
        if (!ev) return;
        if (ev.kind === "track") root.expanded = true;
        else if (ev.layout === "file") root.openPath(ev.openPath || ev.path, ev.openDir === true);
        else if (ev.uid !== undefined) root.srpCall("activate", [ev.uid]);
        root.next();
    }
    function dismissCurrent() {
        const ev = root.current;
        if (ev && ev.uid !== undefined) root.srpCall("dismiss", [ev.uid]);
        root.next();
    }
    // ---- notification list: three clicks within 4 s ----
    function timeAgo(ts) {
        const m = Math.floor((Date.now() - ts) / 60000);
        if (m < 1) return "now";
        if (m < 60) return m + "m";
        const h = Math.floor(m / 60);
        return h < 24 ? h + "h" : Math.floor(h / 24) + "d";
    }
    function openList() {
        root.listOpen = true;
        root.notifOpen = false;
        hold.stop();
        listProc.running = false;
        listProc.running = true;
    }
    function closeList() {
        root.listOpen = false;
        if (root.queue.length) root.next(); else root.current = null;
    }
    function toggleList() { if (root.listOpen) root.closeList(); else root.openList(); }
    Process {
        id: listProc
        command: ["quickshell", "ipc", "-p", root.srpShell, "call", "island", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.listItems = JSON.parse(this.text.trim()); } catch (e) { root.listItems = []; }
            }
        }
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

    // qs -c astrax-island ipc call island toggleList   (same as clicking the island three times)
    IpcHandler {
        target: "island"
        function toggleList(): string { root.toggleList(); return root.listOpen ? "open" : "closed"; }
        // called by the non-consuming Ctrl+V binds (config/binds-island.lua)
        function paste(): string { clipSrc.paste(); return "ok"; }
    }

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
    readonly property string mode: listOpen ? "list" : current ? current.layout
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
        mask: Region { item: root.listOpen ? outsideCatcher : pill }

        // only while the list is open: swallows a click anywhere else on the screen and closes the list
        Item {
            id: outsideCatcher
            anchors.fill: parent
            MouseArea {
                anchors.fill: parent
                enabled: root.listOpen
                acceptedButtons: Qt.AllButtons
                onPressed: root.closeList()
            }
        }

        Rectangle {
            id: pill
            // The pill is pinned by its horizontal centre and its top edge, computed
            // from a fixed reference size (not the animated one), so it grows
            // symmetrically in place instead of sliding sideways while it springs.
            readonly property real refW: 540
            readonly property real refH: 150
            property real cx: root.edgeMargin + refW / 2 + root.posX * Math.max(0, parent.width - refW - 2 * root.edgeMargin)
            property real topY: root.edgeMargin + root.posY * Math.max(0, parent.height - refH - 2 * root.edgeMargin)
            Behavior on cx { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on topY { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            x: cx - width / 2
            y: topY

            readonly property bool glassOn: root.glassCfg && (root.mode === "notif" || root.mode === "musicExpanded")
            readonly property real listH: 62 + Math.min(5, Math.max(1, root.allItems.length)) * 54 + 6
            readonly property real notifH: Math.max(68, notifCol.implicitHeight + 28)

            // compact states keep the pill's height and only get wider (like the
            // real island); notifications and the music card grow downwards
            readonly property real targetW: ({ idle: 126, music: 250, hud: 300, status: 320, notif: 410, file: 340, musicExpanded: 430, list: 540 })[root.mode]
            readonly property real targetH: ({ idle: 34, music: 34, hud: 34, status: 34, notif: notifH, file: 46, musicExpanded: 136, list: listH })[root.mode]
            width: targetW
            height: targetH
            radius: height <= 48 ? height / 2 : 34
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
                cursorShape: (root.mode === "list" || root.mode === "notif" || root.mode === "music" || root.mode === "file") ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: {
                    if (root.listOpen) return;
                    if (root.current) { hold.stop(); if (root.mode === "notif") root.notifOpen = true; }
                }
                onExited: {
                    root.notifOpen = false;
                    if (!root.listOpen && root.current) { hold.interval = 1200; hold.restart(); }
                }
                onClicked: m => {
                    // three left clicks within 4 s open / close the notification list
                    if (m.button === Qt.LeftButton) {
                        const now = Date.now();
                        const t = root.clickTimes.filter(x => now - x < 4000);
                        t.push(now);
                        root.clickTimes = t;
                        if (t.length >= 3) { root.clickTimes = []; root.toggleList(); return; }
                    }
                    if (root.listOpen) return;
                    if (root.mode === "notif" || root.mode === "file") {
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

            // =================== notification list ===================
            Item {
                id: listView
                readonly property bool on: root.mode === "list"
                anchors.fill: parent
                anchors.margins: 14
                opacity: on ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { SequentialAnimation {
                    PauseAnimation { duration: listView.on ? 120 : 0 }
                    NumberAnimation { duration: listView.on ? 220 : 90 }
                } }

                // header
                Text {
                    id: listTitle
                    x: 4; y: 2
                    text: "Notifications"
                    color: root.fg
                    font.family: root.textFont; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    anchors.left: listTitle.right; anchors.leftMargin: 8
                    anchors.baseline: listTitle.baseline
                    visible: root.allItems.length > 0
                    text: root.allItems.length
                    color: root.dim
                    font.family: root.textFont; font.pixelSize: 12; font.weight: Font.Medium
                }
                Row {
                    anchors.right: parent.right; anchors.top: parent.top
                    spacing: 8
                    Rectangle {
                        visible: root.allItems.length > 0
                        height: 24; width: clearText.implicitWidth + 22; radius: 12
                        color: clearArea.pressed ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.14)
                        Text { id: clearText; anchors.centerIn: parent; text: "Clear all"; color: root.fg
                               font.family: root.textFont; font.pixelSize: 12; font.weight: Font.Medium }
                        MouseArea { id: clearArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.srpCall("clear", []); root.listItems = []; root.activity = []; } }
                    }
                    Rectangle {
                        height: 24; width: 24; radius: 12
                        color: closeArea.pressed ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.14)
                        Text { anchors.centerIn: parent; text: "󰅖"; color: root.fg; font.family: root.iconFont; font.pixelSize: 13 }
                        MouseArea { id: closeArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeList() }
                    }
                }

                ListView {
                    id: rows
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 36
                    anchors.bottom: parent.bottom
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.allItems
                    // rows slide up when one is removed
                    remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 140 } }
                    displaced: Transition { SpringAnimation { property: "y"; spring: 5; damping: 0.4; epsilon: 0.3 } }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: rows.width
                        height: 52
                        radius: 14
                        color: rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        // notifications: the app's icon; file / clipboard / device events: a tinted glyph tile
                        Item {
                            id: rIcon
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 36; height: 36
                            readonly property bool isEv: row.modelData.kind === "event"
                            AppIcon {
                                anchors.fill: parent
                                visible: !rIcon.isEv
                                size: 36
                                app: row.modelData.app || ""
                                entry: row.modelData.entry || ""
                                icon: row.modelData.icon || ""
                                image: row.modelData.image || ""
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: rIcon.isEv
                                radius: 18
                                color: Qt.rgba(Qt.color(row.modelData.accent || "#ffffff").r, Qt.color(row.modelData.accent || "#ffffff").g,
                                               Qt.color(row.modelData.accent || "#ffffff").b, 0.2)
                                Text {
                                    anchors.centerIn: parent
                                    visible: !row.modelData.thumb
                                    text: row.modelData.glyph || ""
                                    color: row.modelData.accent || "#ffffff"
                                    font.family: root.iconFont; font.pixelSize: 18
                                }
                                RoundedImage {
                                    anchors.fill: parent; radius: 10
                                    visible: row.modelData.thumb ? true : false
                                    source: row.modelData.thumb || ""
                                }
                            }
                        }
                        Rectangle {   // unread dot
                            visible: row.modelData.kind !== "event" && row.modelData.read === false
                            x: rIcon.x + rIcon.width - 7; y: rIcon.y - 3
                            width: 9; height: 9; radius: 4.5; color: "#0a84ff"
                            border.width: 2; border.color: "#000000"
                        }
                        Column {
                            anchors.left: rIcon.right; anchors.leftMargin: 11
                            anchors.right: rTime.left; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: row.modelData.summary || row.modelData.app
                                color: root.fg
                                font.family: root.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: (row.modelData.body || row.modelData.app || "").replace(/<[^>]*>/g, "").replace(/\n/g, " ")
                                color: root.dim
                                font.family: root.textFont; font.pixelSize: 12
                            }
                        }
                        Text {
                            id: rTime
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.timeAgo(row.modelData.ts)
                            color: root.dim
                            font.family: root.textFont; font.pixelSize: 11; font.weight: Font.Medium
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: m => {
                                const isEv = row.modelData.kind === "event";
                                if (m.button === Qt.RightButton) {
                                    if (isEv) root.activity = root.activity.filter(x => x.id !== row.modelData.id);
                                    else {
                                        root.srpCall("dismiss", [row.modelData.uid]);
                                        root.listItems = root.listItems.filter(x => x.uid !== row.modelData.uid);
                                    }
                                } else {
                                    if (isEv) { if (row.modelData.openPath) root.openPath(row.modelData.openPath, false); }
                                    else root.srpCall("activate", [row.modelData.uid]);
                                    root.closeList();
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.allItems.length === 0
                        text: "Nothing yet"
                        color: root.dim
                        font.family: root.textFont; font.pixelSize: 13; font.weight: Font.Medium
                    }
                }
            }

            // =================== file activity ===================
            Item {
                id: fileView
                readonly property bool on: root.mode === "file"
                anchors.fill: parent
                opacity: on ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: on ? 200 : 100 } }

                readonly property var ev: root.current && root.current.layout === "file" ? root.current : null
                readonly property string st: ev ? ev.state : ""
                readonly property color accent: root.stateColors[st] || "#ffffff"
                readonly property string badgeGlyph: ({ done: "󰄬", added: "󰐕", modified: "󰏫", deleted: "󰩺", renamed: "󰑕", canceled: "󰅖",
                                                        copied: "󰆏", cut: "󰆐", pasted: "󰆒" })[st] || ""

                // every new card (not an in-place update) re-plays the entrance
                property int pulse: 0
                Connections {
                    target: root
                    function onCurrentChanged() { if (fileView.on && root.current && root.current.layout === "file") fileView.pulse++; }
                }
                onOnChanged: if (on) pulse++

                // leading: file-type tile, concentric with the pill (margin 8, radius 15)
                Rectangle {
                    id: tile
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: (fileView.ev && fileView.ev.thumb) ? 9 : 15
                    color: Qt.rgba(fileView.accent.r, fileView.accent.g, fileView.accent.b, 0.2)
                    Behavior on color { ColorAnimation { duration: 300 } }
                    Text {
                        anchors.centerIn: parent
                        visible: !(fileView.ev && fileView.ev.thumb)
                        text: fileView.ev ? fileView.ev.glyph : ""
                        color: fileView.accent
                        font.family: root.iconFont; font.pixelSize: 16
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                    RoundedImage {
                        anchors.fill: parent
                        radius: 9
                        visible: fileView.ev && fileView.ev.thumb
                        source: fileView.ev && fileView.ev.thumb ? fileView.ev.thumb : ""
                    }
                    transformOrigin: Item.Center
                    SequentialAnimation on scale {
                        id: tilePop
                        running: false
                        PropertyAction { value: 0.55 }
                        SpringAnimation { to: 1.0; spring: 5; damping: 0.32; epsilon: 0.002 }
                    }
                }
                Connections { target: fileView; function onPulseChanged() { tilePop.restart(); badgePop.restart(); ripple.restart(); shake.restart(); } }

                Column {
                    anchors.left: tile.right; anchors.leftMargin: 10
                    anchors.right: badge.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        width: parent.width
                        text: fileView.ev ? fileView.ev.name : ""
                        color: root.fg; elide: Text.ElideMiddle
                        font.family: root.textFont; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: fileView.ev ? fileView.ev.sub : ""
                        color: root.dim; elide: Text.ElideRight
                        font.family: root.textFont; font.pixelSize: 11; font.weight: Font.Medium
                    }
                }

                // trailing: spinner while downloading, then a confirming badge that pops in
                Item {
                    id: badge
                    anchors.right: parent.right; anchors.rightMargin: 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24
                    transformOrigin: Item.Center
                    SequentialAnimation on scale {
                        id: badgePop
                        running: false
                        PropertyAction { value: 0.0 }
                        PauseAnimation { duration: 90 }
                        SpringAnimation { to: 1.0; spring: 6; damping: 0.28; epsilon: 0.002 }
                    }

                    // progress ring
                    Item {
                        anchors.fill: parent
                        opacity: fileView.st === "progress" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Shape {
                            anchors.fill: parent
                            layer.enabled: true; layer.samples: 4
                            ShapePath {
                                strokeColor: Qt.rgba(1, 1, 1, 0.16); strokeWidth: 2.5; fillColor: "transparent"
                                PathAngleArc { centerX: 12; centerY: 12; radiusX: 9.5; radiusY: 9.5; startAngle: 0; sweepAngle: 360 }
                            }
                            ShapePath {
                                strokeColor: fileView.accent; strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: 12; centerY: 12; radiusX: 9.5; radiusY: 9.5; startAngle: -90; sweepAngle: 100 }
                            }
                            RotationAnimator on rotation {
                                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                                running: fileView.on && fileView.st === "progress"
                            }
                        }
                    }
                    // confirming badge: filled circle + glyph, with a soft ripple
                    Item {
                        id: done
                        anchors.fill: parent
                        opacity: fileView.st !== "progress" && fileView.st !== "batch" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Rectangle {
                            id: ripple2
                            anchors.centerIn: parent
                            width: 24; height: 24; radius: 12
                            color: "transparent"
                            border.width: 2; border.color: fileView.accent
                            opacity: 0
                            ParallelAnimation {
                                id: ripple
                                running: false
                                NumberAnimation { target: ripple2; property: "scale"; from: 1; to: 1.9; duration: 650; easing.type: Easing.OutCubic }
                                NumberAnimation { target: ripple2; property: "opacity"; from: 0.55; to: 0; duration: 650 }
                            }
                        }
                        Rectangle {
                            id: disc
                            anchors.fill: parent; radius: 12
                            color: fileView.accent
                            Behavior on color { ColorAnimation { duration: 250 } }
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: fileView.badgeGlyph
                                color: "#000000"
                                font.family: root.iconFont; font.pixelSize: 14
                            }
                            transformOrigin: Item.Center
                            // deleted / canceled / modified get a small wiggle, the rest just land
                            SequentialAnimation on rotation {
                                id: shake
                                running: false
                                PropertyAction { value: 0 }
                                PauseAnimation { duration: 260 }
                                NumberAnimation { to: (fileView.st === "deleted" || fileView.st === "canceled") ? -14 : fileView.st === "modified" ? -10 : 0; duration: 90 }
                                NumberAnimation { to: (fileView.st === "deleted" || fileView.st === "canceled") ? 12 : fileView.st === "modified" ? 8 : 0; duration: 110 }
                                SpringAnimation { to: 0; spring: 6; damping: 0.25; epsilon: 0.05 }
                            }
                        }
                    }
                    // batch: item count
                    Text {
                        anchors.centerIn: parent
                        visible: fileView.st === "batch"
                        text: fileView.ev && fileView.ev.count ? fileView.ev.count : ""
                        color: fileView.accent
                        font.family: root.textFont; font.pixelSize: 14; font.weight: Font.Bold
                    }
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

                AppIcon {
                    id: nIcon
                    x: 14; y: 14
                    size: 40
                    app: notifView.ev ? notifView.ev.app : ""
                    entry: notifView.ev && notifView.ev.entry ? notifView.ev.entry : ""
                    icon: notifView.ev ? (notifView.ev.icon || "") : ""
                    image: notifView.ev ? (notifView.ev.image || "") : ""
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
