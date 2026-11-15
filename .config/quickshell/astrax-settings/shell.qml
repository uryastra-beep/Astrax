import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Pages.js" as Pages

// Astrax settings. An overlay layer (like the island) whose only input area is the window itself, so the
// window can be pushed around inside it and deformed like jelly: the part under the pointer follows it,
// the rest trails behind and springs back.
//
//   qs -c astrax-settings ipc call settings toggle|open|close
ShellRoot {
    id: root

    property bool open: false
    property bool shown: false
    property string page: "island"
    property var screenAtOpen: null

    // genie (same shape as the apps' genie): the window grows out of / collapses into its Dock icon
    property real genieP: 0
    property real gtx: 0       // dock icon, in the overlay's own coordinates
    property real gty: 0
    property bool opening: false
    NumberAnimation { id: genieAnim; target: root; property: "genieP"; duration: 620 }

    function openWindow() {
        if (root.opening || (root.open && root.shown)) return;
        root.opening = true;
        closeTimer.stop();
        genieAnim.stop();
        targetProc.running = false;
        targetProc.running = true;      // finds the screen under the pointer + the Dock icon, then startOpen()
    }
    function startOpen(monName, gx, gy) {
        const sc = Quickshell.screens.find(x => x.name === monName) || Quickshell.screens[0];
        root.screenAtOpen = sc;
        root.gtx = gx !== undefined ? gx - sc.x : sc.width / 2;
        root.gty = gy !== undefined ? gy - sc.y : sc.height - 40;
        root.genieP = 1;
        root.shown = true;
        root.open = true;
        root.opening = false;
        genieAnim.from = 1; genieAnim.to = 0; genieAnim.restart();
    }
    function closeWindow() {
        if (!root.open) return;
        Quickshell.execDetached(["qs", "ipc", "-c", "astrax-mac-dock", "call", "dock", "reveal"]);
        root.open = false;
        genieAnim.stop();
        genieAnim.from = root.genieP; genieAnim.to = 1; genieAnim.restart();
        closeTimer.restart();
    }
    Timer { id: closeTimer; interval: 660; onTriggered: root.shown = false }
    Process {
        id: targetProc
        command: ["python3", "-I", Quickshell.env("HOME") + "/scripts/astrax-settings-target.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                const m = parts[0] || "";
                let gx, gy;
                if (parts.length > 1 && parts[1].indexOf(",") > 0) { const c = parts[1].split(","); gx = parseFloat(c[0]); gy = parseFloat(c[1]); }
                root.startOpen(m, gx, gy);
            }
        }
        onExited: if (root.opening && !root.shown) root.startOpen("", undefined, undefined)
    }

    IpcHandler {
        target: "settings"
        function toggle(): string { if (root.open) root.closeWindow(); else root.openWindow(); return root.open ? "open" : "closed"; }
        function open(): void { root.openWindow(); }
        function close(): void { root.closeWindow(); }
        function dbg(): string { return JSON.stringify({page: root.page, front: stage.front, fading: stage.fading, tA: layerA.title, tB: layerB.title, oA: layerA.opacity, oB: layerB.opacity, x: card.x, y: card.y, tx: card.trailX, ty: card.trailY, lx: card.lagX, ly: card.lagY, w: card.width, h: card.height, ww: win.width, wh: win.height, scale: jelly.scale, op: jelly.opacity}); }
        function go(name: string): void { root.page = name; root.openWindow(); }
    }

    PanelWindow {
        id: win
        screen: root.screenAtOpen
        visible: root.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "astrax-settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: Region { item: card }

        // ------------------------------------------------------------ the window itself
        Item {
            id: card
            width: Math.min(940, win.width - 80)
            height: Math.min(660, win.height - 80)
            focus: true
            Keys.onEscapePressed: root.closeWindow()

            property bool placed: false
            function recenter() {
                snapping = true;          // jump there without wobbling
                x = (win.width - width) / 2;
                y = (win.height - height) / 2;
                trailX = x; trailY = y;
                snapping = false;
                placed = true;
            }
            Connections { target: root; function onOpenChanged() { if (root.open) { card.recenter(); card.forceActiveFocus(); } } }
            onWidthChanged: if (!placed) recenter()

            // ---- jelly state: the trail follows the window with a spring; the difference is the lag
            property bool snapping: false
            property real trailX: 0
            property real trailY: 0
            onXChanged: trailX = x
            onYChanged: trailY = y
            Behavior on trailX { enabled: !card.snapping; SpringAnimation { spring: 2.6; damping: 0.17; epsilon: 0.02 } }
            Behavior on trailY { enabled: !card.snapping; SpringAnimation { spring: 2.6; damping: 0.17; epsilon: 0.02 } }
            readonly property real lagX: Math.max(-140, Math.min(140, x - trailX))
            readonly property real lagY: Math.max(-140, Math.min(140, y - trailY))
            property real grabX: width / 2
            property real grabY: 40
            property bool dragging: false

            Rectangle {
                anchors.fill: parent
                radius: Theme.windowRadius
                color: Theme.window
                border.width: 1; border.color: Theme.line
            }

            // empty areas drag the window; controls on top keep their own clicks
            MouseArea {
                id: dragArea
                anchors.fill: parent
                property real px: 0
                property real py: 0
                onPressed: m => {
                    px = m.x; py = m.y;
                    card.grabX = m.x; card.grabY = m.y;
                    card.dragging = true;
                }
                onPositionChanged: m => {
                    if (!pressed) return;
                    card.x = Math.max(-card.width / 2, Math.min(win.width - card.width / 2, card.x + m.x - px));
                    card.y = Math.max(0, Math.min(win.height - 60, card.y + m.y - py));
                }
                onReleased: card.dragging = false
                onCanceled: card.dragging = false
            }

            // ---- sidebar
            Rectangle {
                id: side
                x: 12; y: 12; width: 232; height: parent.height - 24
                radius: Theme.windowRadius - 12
                color: Theme.sidebar
                border.width: 1; border.color: Theme.line

                Column {
                    x: 20; y: 20; spacing: 2
                    Text { text: "Astrax"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.t4; font.weight: Font.DemiBold }
                    Text { text: "Settings"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.t2 }
                }

                // layout of the entries: y of each one, computed once
                readonly property var layout: {
                    const out = []; let y = 88;
                    for (const e of Pages.nav) {
                        if (e.kind === "label") { y += out.length ? 12 : 0; out.push({ y: y, h: 28 }); y += 28; }
                        else { out.push({ y: y, h: 44 }); y += 46; }
                    }
                    return out;
                }
                readonly property int activeIndex: Pages.nav.findIndex(e => e.id === root.page)

                // shared element: the pill that marks the active entry travels between them
                Rectangle {
                    x: 10; width: parent.width - 20
                    y: side.activeIndex >= 0 ? side.layout[side.activeIndex].y : 0
                    height: 44; radius: Theme.controlRadius + 2
                    color: Theme.accent
                    Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                }
                Repeater {
                    model: Pages.nav
                    delegate: Item {
                        required property var modelData
                        required property int index
                        x: 10; width: side.width - 20
                        y: side.layout[index].y; height: side.layout[index].h
                        Text {
                            visible: parent.modelData.kind === "label"
                            x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                            text: (parent.modelData.text || "").toUpperCase()
                            color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.t1; font.weight: Font.DemiBold
                            font.letterSpacing: 0.9
                        }
                        SideItem {
                            visible: parent.modelData.kind === "item"
                            width: parent.width
                            icon: parent.modelData.icon || ""; label: parent.modelData.label || ""
                            active: root.page === parent.modelData.id
                            onClicked: root.page = parent.modelData.id
                        }
                    }
                }
            }

            // ---- page stage: two layers so the old page can fade out while the new one fades in
            Item {
                id: stage
                x: side.x + side.width + 12 + Theme.sp3
                y: 12 + Theme.sp3
                width: parent.width - x - Theme.sp4
                height: parent.height - 2 * (12 + Theme.sp3) + Theme.sp2
                property int front: 0
                property bool fading: false

                function pageData(id) {
                    return Pages.build(id, {
                        wallpaperDir: Cfg.get("wallpaperDir", ""),
                        screens: Quickshell.screens.map(s => ({ name: s.name, model: s.model, width: s.width, height: s.height, scale: s.devicePixelRatio }))
                    });
                }
                function show(id, instant) {
                    const next = instant ? front : 1 - front;
                    const d = pageData(id);
                    const layer = next === 0 ? layerA : layerB;
                    layer.title = d.title; layer.subtitle = d.subtitle; layer.groups = d.groups;
                    if (instant) return;      // (never assign opacity here: it would break the isFront binding)
                    front = next; fading = true; fadeEnd.restart();
                }
                Timer { id: fadeEnd; interval: 260; onTriggered: stage.fading = false }
                Component.onCompleted: show(root.page, true)
                Connections { target: root; function onPageChanged() { stage.show(root.page, false); } }
                // a hidden page keeps showing what it had; refresh the one in front when the window opens
                Connections { target: root; function onOpenChanged() { if (root.open) stage.show(root.page, true); } }

                component Layer: PageView {
                    id: lp
                    anchors.fill: parent
                    property bool isFront: false
                    property bool fading: false
                    opacity: isFront ? 1 : 0
                    y: isFront ? 0 : 8
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    // no layer/blur here: a nested layer inside the jelly's ShaderEffectSource does not
                    // invalidate it, so the page stayed frozen on the old content
                }
                Layer { id: layerA; isFront: stage.front === 0; fading: stage.fading }
                Layer { id: layerB; isFront: stage.front === 1; fading: stage.fading }
            }

            // ---- close
            Rectangle {
                id: closeBtn
                x: parent.width - width - 22; y: 22; width: 32; height: 32; radius: 16
                color: closeArea.containsMouse ? Theme.surfaceHi : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }
                scale: closeArea.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Text { anchors.centerIn: parent; text: "󰅖"; color: Theme.textDim; font.family: Theme.iconFont; font.pixelSize: 16 }
                MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.closeWindow() }
            }
        }

        // ------------------------------------------------------------ what is actually drawn: the window, deformed
        readonly property real pad: 160
        // The window is drawn through a texture of itself. When nothing else asks for frames, the last animation
        // step can stay one frame behind (sidebar says one page, content shows the previous one). While the pointer is
        // over the window, dragging, or just after a page change, keep refreshing the texture every frame.
        Timer { id: kick; interval: 700 }
        Connections { target: root; function onPageChanged() { kick.restart(); } function onOpenChanged() { kick.restart(); } }
        HoverHandler { id: cardHover; target: card }
        FrameAnimation {
            running: win.visible && (cardHover.hovered || card.dragging || kick.running || genieAnim.running)
            onTriggered: cardTexture.scheduleUpdate()
        }
        ShaderEffectSource {
            id: cardTexture
            sourceItem: card
            sourceRect: Qt.rect(-win.pad, -win.pad, card.width + 2 * win.pad, card.height + 2 * win.pad)
            hideSource: true
            live: true
            visible: false
        }
        ShaderEffect {
            id: jelly
            x: card.x - win.pad; y: card.y - win.pad
            width: card.width + 2 * win.pad; height: card.height + 2 * win.pad
            mesh: GridMesh { resolution: Qt.size(40, 40) }
            property var source: cardTexture
            property vector2d grab: Qt.vector2d(card.grabX + win.pad, card.grabY + win.pad)
            property vector2d lag: Qt.vector2d(card.lagX, card.lagY)
            property real reach: Math.sqrt(card.width * card.width + card.height * card.height) * 0.9
            property real squash: 0.35
            property vector4d gbox: Qt.vector4d(win.pad, win.pad, card.width, card.height)
            property vector2d gtarget: Qt.vector2d(root.gtx - jelly.x, root.gty - jelly.y)
            property real gp: root.genieP
            vertexShader: Qt.resolvedUrl("jelly.vert.qsb")
            fragmentShader: Qt.resolvedUrl("jelly.frag.qsb")
            // open / close: the genie (vertex shader) does the work; invisible while collapsed
            opacity: root.shown && root.genieP < 0.999 ? 1 : 0
        }
    }
}
