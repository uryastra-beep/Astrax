pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

ShellRoot {
    id: root

    property bool open: false
    property string query: ""
    property int selectedIndex: 0

    // ---------- usage frequency (most used apps on top) ----------
    property var usage: ({})
    property int usageRev: 0

    // ---------- pinned apps (Ctrl+F on the selected one) ----------
    property var pinned: []          // array of ids, in order; the first one goes highest

    function isPinned(id): bool {
        return id && root.pinned.indexOf(id) >= 0;
    }
    function togglePin(): void {
        const e = root.displayModel[root.selectedIndex];
        if (!e || !e.id)
            return;
        const arr = root.pinned.slice();
        const i = arr.indexOf(e.id);
        if (i >= 0)
            arr.splice(i, 1);       // already pinned -> unpin
        else
            arr.unshift(e.id);      // pin at the top of the pinned group
        root.pinned = arr;
        pinnedFile.setText(JSON.stringify(arr));
        root.refreshDisplay();      // explicit action: reorder now even if open
        const ni = root.displayModel.indexOf(e);
        if (ni >= 0)
            root.selectedIndex = ni;
    }

    // find an already open window of that app (wlr-foreign-toplevel)
    function runningWindow(entry) {
        const seg = s => (s || "").toLowerCase().replace(/\.desktop$/, "").split(".").pop();
        const wanted = [];
        if (entry.startupClass) {
            wanted.push(entry.startupClass.toLowerCase());
            wanted.push(seg(entry.startupClass));
        }
        if (entry.id) {
            wanted.push(entry.id.toLowerCase());
            wanted.push(seg(entry.id));
        }
        for (const tl of ToplevelManager.toplevels.values) {
            const app = (tl.appId || "").toLowerCase();
            if (!app)
                continue;
            if (wanted.indexOf(app) >= 0 || wanted.indexOf(seg(app)) >= 0)
                return tl;
        }
        return null;
    }

    function launch(entry): void {
        if (!entry)
            return;
        if (entry.id) {
            root.usage[entry.id] = (root.usage[entry.id] || 0) + 1;
            root.usageRev++;
            usageFile.setText(JSON.stringify(root.usage));
        }
        const tl = root.runningWindow(entry);
        if (tl)
            tl.activate();      // already open -> focus that window
        else
            entry.execute();    // not open -> launch it
        root.open = false;
    }

    // displayed list: "frozen" while the launcher is open
    // so the order doesn't jump around while using it; refreshed on close / on search
    property var displayModel: []
    function refreshDisplay(): void { root.displayModel = root.appModel; }

    function clamp(i: int): int {
        return Math.max(0, Math.min(root.displayModel.length - 1, i));
    }
    function move(delta: int): void {
        root.selectedIndex = root.clamp(root.selectedIndex + delta);
    }
    function launchSelected(): void {
        root.launch(root.displayModel[root.selectedIndex]);
    }

    Component.onCompleted: refreshDisplay()
    onAppModelChanged: if (!root.open) root.refreshDisplay()
    onQueryChanged: { root.refreshDisplay(); root.selectedIndex = 0; }
    onOpenChanged: {
        if (!open) {
            query = "";
            selectedIndex = 0;
            refreshDisplay();
        } else {
            selectedIndex = 0;
        }
    }

    // ---------- theme: REAL Serpantinum tokens ----------
    // Catppuccin Mocha (same default hex as
    // singletons/theme/ThemeBackend.qml), overridden live by the color
    // derived from the current wallpaper (matugen) and by
    // fontFamily/borderRadius from ~/.config/serpantinum/settings.json --
    // the SAME source of truth Serpantinum itself uses, not a
    // made-up palette nor caelestia's.
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
        // same formula as Serpantinum's Launcher.qml for the outer
        // container radius from borderRadius
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
        set("base", c.base); set("mantle", c.mantle); set("crust", c.crust);
        set("text", c.text); set("subtext0", c.subtext0); set("subtext1", c.subtext1);
        set("surface0", c.surface0); set("surface1", c.surface1); set("surface2", c.surface2);
        set("mauve", c.mauve);
    }

    FileView {
        id: usageFile
        path: `${Quickshell.env("HOME")}/.local/state/astrax-launcher/usage.json`
        onLoaded: {
            try {
                const o = JSON.parse(text());
                if (o && typeof o === "object") {
                    root.usage = o;
                    root.usageRev++;
                }
            } catch (e) {
                console.warn("astrax-launcher: usage.json ilegible:", e);
            }
        }
        onLoadFailed: root.usageRev++
    }

    FileView {
        id: pinnedFile
        path: `${Quickshell.env("HOME")}/.local/state/astrax-launcher/pinned.json`
        onLoaded: {
            try {
                const a = JSON.parse(text());
                if (Array.isArray(a)) {
                    root.pinned = a;
                    root.refreshDisplay();
                }
            } catch (e) {
                console.warn("astrax-launcher: pinned.json ilegible:", e);
            }
        }
    }

    // true = active theme is matugen (color derived from the wallpaper, lives in
    // qs_matugen_colors.json). false = STATIC preset picked by hand in
    // Serpantinum (guide > theme) -- its colors come from
    // settings.json > theme.colors, not matugen. Without this, switching
    // presets in Serpantinum (e.g. to "Charoite") wasn't reflected here --
    // the launcher should follow the theme picked in Serpantinum.
    property bool matugenMode: true

    FileView {
        path: `${Quickshell.env("HOME")}/.config/serpantinum/settings.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                // Real BUG: the theme lives NESTED under "theme", not at the
                // json root -- reading it from the root (s.matugen/s.colors) never
                // found anything, so a static preset was never
                // applied, matugen colors always stayed.
                const s = JSON.parse(text());
                const t = s.theme || {};
                if (t.fontFamily) theme.fontFamily = t.fontFamily;
                if (t.borderRadius !== undefined) theme.borderRadius = t.borderRadius;
                root.matugenMode = t.matugen !== false;
                if (!root.matugenMode && t.colors) root.applySerpColors(t.colors);
            } catch (e) {
                console.warn("astrax-launcher: could not parse settings.json:", e);
            }
        }
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/serpantinum/qs_matugen_colors.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            // if the active preset is static (not matugen), this file
            // may hold stale colors -- ignore it
            // completely so it doesn't override the preset that IS active.
            if (!root.matugenMode) return;
            try {
                const c = JSON.parse(text());
                root.applySerpColors(c && c.colors ? c.colors : c);
            } catch (e) {
                console.warn("astrax-launcher: could not parse qs_matugen_colors.json:", e);
            }
        }
    }

    // ---------- app list: pinned on top, then by usage, then alphabetical ----------
    readonly property var appModel: {
        root.usageRev; // dependency to recompute when usage changes
        root.pinned;   // dependency to recompute on pin/unpin
        const q = root.query.trim().toLowerCase();
        let apps = DesktopEntries.applications.values.filter(a => a && !a.noDisplay);
        if (q.length > 0)
            apps = apps.filter(a =>
                (a.name || "").toLowerCase().includes(q) ||
                (a.genericName || "").toLowerCase().includes(q) ||
                (a.comment || "").toLowerCase().includes(q));
        const uses = a => (a.id && root.usage[a.id]) || 0;
        const pinRank = a => {
            const i = a.id ? root.pinned.indexOf(a.id) : -1;
            return i < 0 ? 1e9 : i;
        };
        apps.sort((a, b) => {
            const p = pinRank(a) - pinRank(b);
            if (p !== 0)
                return p;
            const d = uses(b) - uses(a);
            if (d !== 0)
                return d;
            return (a.name || "").localeCompare(b.name || "");
        });
        return apps;
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.open = !root.open; }
        function show(): void { root.open = true; }
        function hide(): void { root.open = false; }
        function isOpen(): bool { return root.open; }
    }

    PanelWindow {
        id: win

        WlrLayershell.namespace: "astrax-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        color: "transparent"
        exclusiveZone: 0
        anchors { left: true; top: true; bottom: true }
        implicitWidth: 380
        visible: root.open || win.openProg > 0.001

        // same curves as Serpantinum's SIDE launcher (Launcher.qml:
        // animProgress, OutBack 1.28 on open / InQuad on close, 340/150ms
        // for the "isSideAttached" mode -- ours also hangs from the
        // left edge).
        // 0 = closed (off to the left), 1 = open
        property real openProg: root.open ? 1 : 0
        Behavior on openProg {
            NumberAnimation {
                duration: root.open ? 340 : 150
                easing.type: root.open ? Easing.OutBack : Easing.InQuad
                easing.overshoot: root.open ? 1.28 : 1.0
            }
        }

        property bool typedExpand: false
        property bool expanded: hover.hovered || search.activeFocus || typedExpand

        onVisibleChanged: {
            if (visible) {
                keyHandler.forceActiveFocus();
                grabTimer.restart();
            } else {
                typedExpand = false;
            }
        }

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

        // click outside -> close; also catches scroll in the launcher area
        // the card doesn't cover (e.g. right as it collapses)
        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
            onWheel: event => {
                if (event.angleDelta.y > 0)
                    root.move(-1);
                else if (event.angleDelta.y < 0)
                    root.move(1);
            }
        }

        Item {
            id: keyHandler
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: root.open = false
            Keys.onUpPressed: root.move(-1)
            Keys.onDownPressed: root.move(1)
            Keys.onReturnPressed: root.launchSelected()
            Keys.onEnterPressed: root.launchSelected()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                    root.togglePin();
                    event.accepted = true;
                    return;
                }
                // optional, they don't replace arrows/Enter: W/S moves, Shift opens
                if (event.key === Qt.Key_W || event.key === Qt.Key_S) {
                    root.move(event.key === Qt.Key_W ? -1 : 1);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Shift) {
                    if (!event.isAutoRepeat)
                        root.launchSelected();
                    event.accepted = true;
                    return;
                }
                if (event.text.length === 1 && event.text >= " " && !search.activeFocus) {
                    win.typedExpand = true;
                    search.text += event.text;
                    search.forceActiveFocus();
                    event.accepted = true;
                }
            }
        }

        // ---------- card: solid, no blur -- same as Launcher.qml ----------
        // it should look like it "comes out" of the screen edge,
        // like Serpantinum's taskbar when the launcher is attached to a
        // bar (those joining curves). Flush against the left edge (no
        // margin there, no rounding on that half) and rounded only on the
        // free side (right) -- Qt 6.7+ has per-corner radius in Rectangle.
        Rectangle {
            id: card

            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            anchors.leftMargin: 0
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            anchors.rightMargin: 8
            width: win.expanded ? 320 : 68
            topLeftRadius: 0
            bottomLeftRadius: 0
            topRightRadius: theme.cornerRadius
            bottomRightRadius: theme.cornerRadius
            color: theme.base
            border.width: 1
            border.color: Qt.alpha(theme.surface2, 0.6)

            // entry animation: slides out from the left edge + fade.
            // NOT a rigid tilt (it rotated like a board, the
            // movement showed more at the bottom than at the top, uneven) -- a
            // full JELLY wobble, along the WHOLE card
            // evenly, as if something pulled it from the left edge (where it
            // "comes out" of) on open and close. Done with a NON-uniform Scale
            // (xScale/yScale separately, pivot on the left edge) plus
            // OutElastic, which oscillates several times by itself before settling --
            // that IS the wobble, no need to simulate it by hand.
            opacity: win.openProg
            transform: [
                Translate {
                    x: (win.openProg - 1) * card.width
                },
                Scale {
                    id: jelly
                    origin.x: 0
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
                    NumberAnimation { target: jelly; property: "yScale"; to: win.open ? 1.16 : 0.88; duration: 90; easing.type: Easing.OutQuad }
                    NumberAnimation { target: jelly; property: "xScale"; to: win.open ? 0.88 : 1.12; duration: 90; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: jelly; property: "yScale"; to: 1.0; duration: 420; easing.type: Easing.OutElastic; easing.amplitude: 1.0; easing.period: 0.42 }
                    NumberAnimation { target: jelly; property: "xScale"; to: 1.0; duration: 420; easing.type: Easing.OutElastic; easing.amplitude: 1.0; easing.period: 0.42 }
                }
            }

            Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            HoverHandler { id: hover }

            // mouse scroll moves the bubble; placed here (ancestor of the
            // list/icons) so the event reaches it while hovering them
            WheelHandler {
                target: null
                onWheel: event => {
                    if (event.angleDelta.y > 0)
                        root.move(-1);
                    else if (event.angleDelta.y < 0)
                        root.move(1);
                    event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                TextField {
                    id: search

                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    visible: win.expanded
                    opacity: win.expanded ? 1 : 0
                    placeholderText: "Search apps…"
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
                    Keys.onEscapePressed: root.open = false
                    Keys.onUpPressed: root.move(-1)
                    Keys.onDownPressed: root.move(1)
                    Keys.onReturnPressed: root.launchSelected()
                    Keys.onEnterPressed: root.launchSelected()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                            root.togglePin();
                            event.accepted = true;
                        }
                    }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                Item {
                    id: listWrap
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // selection bubble in VIEWPORT coordinates (not
                    // content ones): when reaching the last visible
                    // item and going further down, the bubble stays still at the
                    // edge and the apps keep scrolling UNDER it, instead
                    // of the bubble chasing them on every key press. Done by
                    // subtracting list.contentY from the item position, instead of
                    // using the ListView's native "highlight:" (which lives INSIDE
                    // the scrollable content and whose own animation competed
                    // with the positionViewAtIndex jump, feeling doubled).
                    Rectangle {
                        id: bubble
                        z: 0
                        visible: !!list.currentItem
                        width: list.width
                        height: list.currentItem ? list.currentItem.height : 48
                        radius: theme.borderRadius
                        color: theme.mauve

                        readonly property real rawY: list.currentItem ? (list.currentItem.y - list.contentY) : 0
                        // true when the bubble is "stuck" to the edge (rawY
                        // leaves the visible range and the "y" clamp below
                        // stops it there) -- in that state, holding the arrow
                        // keeps changing currentIndex but the bubble NO LONGER
                        // MOVES, so the stretch looks excessive/jittery
                        // repeating without real movement.
                        readonly property bool atEdge: rawY < 0 || rawY > (list.height - height)
                        y: Math.max(0, Math.min(list.height - height, rawY))

                        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        // stretch: stretches vertically (yScale up, xScale
                        // down so it doesn't look fat) when the selection changes, and
                        // then bounces back to its normal shape with a
                        // spring. Vertical list =
                        // always stretches in Y (unlike the
                        // app-switcher grid, which can also move in X).
                        //
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
                        cacheBuffer: 800
                        boundsBehavior: Flickable.StopAtBounds
                        // no scroll/drag of its own: the only scroll is the launcher's
                        // WheelHandler (moves the selection), so they don't compete
                        interactive: false
                        model: root.displayModel
                        currentIndex: root.selectedIndex

                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        id: entry

                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 48
                        readonly property bool isSelected: index === root.selectedIndex

                        HoverHandler {
                            id: entryHover
                            onHoveredChanged: if (hovered) root.selectedIndex = entry.index
                        }
                        TapHandler {
                            id: entryTap
                            onTapped: root.launch(entry.modelData)
                        }

                        // press feedback -- same as delegateContent in
                        // Launcher.qml (scale 0.98, OutBack overshoot 1.2, 180ms)
                        //
                        // DYNAMIC margins on purpose: expanded (with text) uses
                        // 8/10 so the icon sits against the left of the
                        // row. Collapsed (icon only, text invisible/0px) those
                        // same uneven margins left the icon off the
                        // real centre of the 68px rail (real bug: "the
                        // app logo is shifted a bit to the right") -- exact
                        // centring: margin = (width of THIS row
                        // - 40 of the icon) / 2 on each side. NOTE: the real width of
                        // the row is NOT card.width -- the ColumnLayout inside
                        // "card" already subtracts 10+10 of margins (see below,
                        // "anchors.margins: 10"), so centring against
                        // card.width was still off (bug
                        // reported again after the first attempt: "still
                        // crooked"). parent.width (the "entry" Item itself) is the
                        // correct width no matter how many margins there are above.
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: win.expanded ? 8 : (parent.width - 40) / 2
                            anchors.rightMargin: win.expanded ? 10 : (parent.width - 40) / 2
                            spacing: 12

                            scale: entryTap.pressed ? 0.98 : 1.0
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                            // rounded icon box -- same treatment as
                            // delegateIconArea in Launcher.qml (surface2, tinted
                            // mauve when selected)
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignVCenter
                                radius: Math.max(4, theme.borderRadius)
                                color: entry.isSelected
                                    ? Qt.tint(theme.surface2, Qt.rgba(theme.mauve.r, theme.mauve.g, theme.mauve.b, 0.2))
                                    : theme.surface2
                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                IconImage {
                                    id: appIcon
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    asynchronous: true
                                    source: Quickshell.iconPath(entry.modelData.icon, "application-x-executable")

                                    // icon "pop" when it becomes selected (arrows)
                                    scale: entry.isSelected ? 1.1 : 1.0
                                    transformOrigin: Item.Center
                                    Behavior on scale {
                                        NumberAnimation { duration: 170; easing.type: Easing.OutBack }
                                    }
                                }

                                // star in the corner if the app is pinned (Ctrl+F)
                                Rectangle {
                                    id: starBadge
                                    visible: root.isPinned(entry.modelData.id)
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -4
                                    anchors.topMargin: -4
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: theme.base
                                    border.width: 1
                                    border.color: Qt.alpha(theme.mauve, 0.55)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "★"
                                        font.pixelSize: 10
                                        color: theme.mauve
                                    }

                                    scale: visible ? 1 : 0
                                    Behavior on scale {
                                        NumberAnimation { duration: 160; easing.type: Easing.OutBack }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 0
                                visible: win.expanded
                                opacity: win.expanded ? 1 : 0

                                Text {
                                    Layout.fillWidth: true
                                    text: entry.modelData.name || ""
                                    color: entry.isSelected ? theme.crust : theme.text
                                    font.family: theme.fontFamily
                                    font.pixelSize: 14
                                    font.weight: entry.isSelected ? Font.Bold : Font.Medium
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: entry.modelData.genericName || entry.modelData.comment || ""
                                    color: entry.isSelected ? theme.crust : theme.subtext0
                                    opacity: entry.isSelected ? 0.9 : 0.85
                                    font.family: theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                }

                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }
                    }
                    }
                }
            }
        }

        // floating label for the selected item while collapsed (keyboard nav)
        Rectangle {
            id: tip
            visible: root.open && !win.expanded && root.displayModel.length > 0 && !!list.currentItem
            x: card.x + card.width + 10
            y: {
                if (!list.currentItem)
                    return card.y + 20;
                const p = list.currentItem.mapToItem(tip.parent, 0, 0);
                return p.y + (list.currentItem.height - tip.height) / 2;
            }
            height: 34
            width: tipText.implicitWidth + 24
            radius: theme.borderRadius
            opacity: win.openProg
            color: theme.surface1
            border.width: 1
            border.color: Qt.alpha(theme.surface2, 0.6)

            Behavior on y { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            Text {
                id: tipText
                anchors.centerIn: parent
                text: root.displayModel[root.selectedIndex] ? (root.displayModel[root.selectedIndex].name || "") : ""
                color: theme.text
                font.family: theme.fontFamily
                font.pixelSize: 13
            }
        }
    }
}
