pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// astrax-app-switcher: lists ALL open windows on ALL the
// workspaces OF THE FOCUSED SCREEN (independent per monitor -- it never
// mixes in apps from the other screen). 100% Serpantinum design: the same color/
// radius/font tokens as its real Launcher.qml + ThemeBackend.qml (not
// a made-up approximation) -- see the "theme" block below.
//
// Zero polling, zero subprocesses: the whole list comes from the
// REACTIVE properties of Quickshell.Hyprland (Hyprland.workspaces.values, each
// with .monitor.name and .toplevels.values) -- the same mechanism
// WallpaperEngine.qml/WidgetLoader.qml already use. The focus action uses
// Hyprland.dispatch(...), the same method Serpantinum uses natively
// in WorkspacesWidget.qml (talks straight to the socket, without
// spawning hyprctl).
//
// One instance per screen (Variants over Quickshell.screens, same
// pattern as WidgetLoader.qml) with its own IpcHandler
// ("appswitcher-" + monitorName) -- so the "Menu" toggle (which
// resolves the focused monitor in the bind, see binds-serpantinum.lua)
// opens ONLY that screen's instance.
ShellRoot {
    id: switcherRoot

    // Purely decorative classes from our own widgets (they aren't
    // real "apps" worth switching to) -- same rule
    // as ignoredWallpaperClasses in WallpaperEngine.qml. The REAL,
    // interactive kitty windows (widget4-term/widget5-term/normal kitty) ARE
    // shown -- they're real windows, not decoration.
    readonly property var ignoredClasses: [
        "widget-clock", "widget-clock-ghost",
        "widget-lavat",
        "widget4-unimatrix", "widget4-lavat",
        "widget5-unimatrix", "widget5-lavat"
    ]

    function segClass(s) {
        return (s || "").toLowerCase().replace(/\.desktop$/, "").split(".").pop();
    }

    // Same matching as astrax-launcher's runningWindow(), but inverted:
    // given the class of an ALREADY open window, find the matching
    // .desktop entry (to get its real icon).
    function findEntryForClass(cls) {
        if (!cls) return null;
        const wantedCls = cls.toLowerCase();
        const wantedSeg = switcherRoot.segClass(cls);
        const apps = DesktopEntries.applications.values;
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i];
            if (!e) continue;
            const idL = (e.id || "").toLowerCase();
            const scL = (e.startupClass || "").toLowerCase();
            if (idL === wantedCls || scL === wantedCls ||
                switcherRoot.segClass(idL) === wantedSeg || switcherRoot.segClass(scL) === wantedSeg) {
                return e;
            }
        }
        return null;
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: win

                required property var modelData
                screen: modelData
                readonly property string safeMonitorName: (modelData.name || "default").replace(/[^a-zA-Z0-9_-]/g, "_")

                property bool open: false
                property bool islandEnabled: false
                onIslandEnabledChanged: if (islandEnabled) win.open = false
                property string query: ""
                property int selectedIndex: 0

                WlrLayershell.namespace: "astrax-app-switcher"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: win.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                color: "transparent"
                exclusiveZone: 0
                // no anchors -> wlr-layer-shell centres the surface by itself.
                // Must be >= the largest possible "card" size (720x600) plus
                // margin, otherwise the grid gets clipped by the edge
                // of this surface (real bug found live: it was
                // cut at 560x480, the old size of the list version).
                implicitWidth: 760
                implicitHeight: 640
                visible: win.open || win.openProg > 0.001

                // same curves as Serpantinum's CENTRED launcher
                // (Launcher.qml: animProgress, OutBack 1.28 on open /
                // InQuad on close, 420/200ms).
                property real openProg: win.open ? 1 : 0
                Behavior on openProg {
                    NumberAnimation {
                        duration: win.open ? 420 : 200
                        easing.type: win.open ? Easing.OutBack : Easing.InQuad
                        easing.overshoot: win.open ? 1.28 : 1.0
                    }
                }

                IpcHandler {
                    target: "appswitcher-" + win.safeMonitorName
                    function toggle(): void {
                        if (win.islandEnabled) win.routeIsland("toggleSwitcher", true);
                        else win.open = !win.open;
                    }
                    function show(): void {
                        if (win.islandEnabled) win.routeIsland("openSwitcher", true);
                        else win.open = true;
                    }
                    function hide(): void {
                        win.open = false;
                        if (win.islandEnabled) win.routeIsland("closeSwitcher", false);
                    }
                    function isOpen(): bool { return win.open; }
                }

                onOpenChanged: {
                    if (open) {
                        selectedIndex = 0;
                        query = "";
                        keyHandler.forceActiveFocus();
                        grabTimer.restart();
                    }
                }
                function routeIsland(method, fallbackOpen) {
                    win.open = false;
                    islandRequest.fallbackOpen = fallbackOpen;
                    islandRequest.command = ["qs", "-c", "astrax-island", "ipc", "call", "island", method];
                    if (!islandRequest.running) islandRequest.running = true;
                }
                Process {
                    id: islandRequest
                    property bool fallbackOpen: false
                    onExited: (exitCode, exitStatus) => {
                        if (exitCode !== 0 && fallbackOpen) win.open = true;
                    }
                }

                Timer {
                    id: grabTimer
                    interval: 40
                    onTriggered: grab.active = Qt.binding(() => win.open)
                }

                // closing a single app (window.close via dispatch) makes Hyprland
                // lose focus briefly, which breaks this focus grab and
                // used to close the whole menu as a side effect (real bug: "if
                // I press the X the UI closes"). While ignoreNextGrabClear
                // is on (closeEntry turns it on for 400ms) a clear is treated
                // as noise and only re-arms the grab, without touching win.open.
                property bool ignoreNextGrabClear: false

                Timer {
                    id: grabClearGuardTimer
                    interval: 400
                    onTriggered: win.ignoreNextGrabClear = false
                }

                HyprlandFocusGrab {
                    id: grab
                    windows: [win]
                    onCleared: {
                        if (win.ignoreNextGrabClear) {
                            win.ignoreNextGrabClear = false;
                            grabTimer.restart();
                            return;
                        }
                        win.open = false;
                    }
                }

                // ---------- theme: REAL Serpantinum tokens ----------
                // Catppuccin Mocha (same default hex as
                // singletons/theme/ThemeBackend.qml), overridden live by the
                // color derived from the current wallpaper (matugen) and by
                // fontFamily/borderRadius from ~/.config/serpantinum/settings.json
                // -- the SAME source of truth Serpantinum itself uses,
                // not a made-up palette nor caelestia's.
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
                    // same formula as Serpantinum's Launcher.qml for the
                    // outer container radius from borderRadius
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

                // true = active theme is matugen (color derived from the wallpaper,
                // lives in qs_matugen_colors.json). false = STATIC preset
                // picked by hand in Serpantinum (guide > theme) -- its colors
                // come from settings.json > theme.colors, not matugen. Without
                // this, switching presets in Serpantinum (e.g. to "Charoite") wasn't
                // reflected here.
                property bool matugenMode: true

                FileView {
                    path: `${Quickshell.env("HOME")}/.config/serpantinum/settings.json`
                    watchChanges: true
                    onFileChanged: reload()
                    onLoaded: {
                        try {
                            // Real BUG: the theme lives NESTED under "theme", not
                            // at the json root -- reading it from the root
                            // (s.matugen/s.colors) never found anything, so
                            // a static preset was never applied,
                            // matugen colors always stayed.
                            const s = JSON.parse(text());
                            win.islandEnabled = !s.island || s.island.enabled !== false;
                            const t = s.theme || {};
                            if (t.fontFamily) theme.fontFamily = t.fontFamily;
                            if (t.borderRadius !== undefined) theme.borderRadius = t.borderRadius;
                            win.matugenMode = t.matugen !== false;
                            if (!win.matugenMode && t.colors) win.applySerpColors(t.colors);
                        } catch (e) {
                            console.warn("astrax-app-switcher: could not parse settings.json:", e);
                        }
                    }
                }

                FileView {
                    path: `${Quickshell.env("HOME")}/.local/state/serpantinum/qs_matugen_colors.json`
                    watchChanges: true
                    onFileChanged: reload()
                    onLoaded: {
                        // if the active preset is static (not matugen), this
                        // file may hold stale colors --
                        // ignore it completely so it doesn't override the real preset.
                        if (!win.matugenMode) return;
                        try {
                            const c = JSON.parse(text());
                            win.applySerpColors(c && c.colors ? c.colors : c);
                        } catch (e) {
                            console.warn("astrax-app-switcher: could not parse qs_matugen_colors.json:", e);
                        }
                    }
                }

                // ---------- data: workspaces of THIS screen, reactive ----------
                readonly property var myWorkspaces: {
                    if (typeof Hyprland === "undefined" || !Hyprland.workspaces || !Hyprland.workspaces.values) return [];
                    return Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === win.modelData.name);
                }

                readonly property int wsOffset: {
                    if (win.myWorkspaces.length === 0) return 0;
                    return Math.min(...win.myWorkspaces.map(w => w.id));
                }

                // Groups by workspace: 1 single app -> normal entry (icon +
                // name + live preview of THAT window, as usual). 2+ apps
                // on the SAME workspace -> ONE single "group" entry for the whole
                // workspace: an icons-only row (a name would be ambiguous with
                // several apps) and the preview is a MOSAIC with
                // the live capture of EACH window in the group -- Hyprland/wlroots
                // can't screencopy a whole workspace that isn't
                // currently shown on a monitor (it isn't a surface
                // of its own), so a mosaic of the real windows
                // is the most faithful way to "see the apps" without faking a
                // screenshot.
                //
                // "Raw" on purpose: it is NOT used directly to paint the
                // grid. Real bug found live: when opening several kitty
                // windows in a row, this block was recomputed (new JS array) for EACH
                // window that appeared, and since Repeater/GridView can't tell
                // it's "the same list with one more item" (they're new arrays with no
                // stable identity), it destroyed and recreated ALL cells -- and
                // with them ALL the live ScreencopyViews -- several times per
                // second. That saturates the wlr-screencopy protocol and Hyprland
                // ended up killing the process ("error in client communication").
                // windowsModel (below) dampens this with a debounce.
                readonly property var windowsModelRaw: {
                    let byWs = {};
                    let order = [];
                    for (let i = 0; i < win.myWorkspaces.length; i++) {
                        const ws = win.myWorkspaces[i];
                        if (!ws.toplevels || !ws.toplevels.values) continue;
                        for (let j = 0; j < ws.toplevels.values.length; j++) {
                            const tl = ws.toplevels.values[j];
                            const cls = (tl.wayland && tl.wayland.appId) || "";
                            if (switcherRoot.ignoredClasses.indexOf(cls) !== -1) continue;
                            const entry = switcherRoot.findEntryForClass(cls);
                            const w = {
                                address: tl.address,
                                toplevel: tl,
                                title: tl.title || cls || "?",
                                cls: cls,
                                iconName: entry ? entry.icon : cls,
                                active: !!tl.activated
                            };
                            if (!byWs[ws.id]) { byWs[ws.id] = { wsId: ws.id, windows: [] }; order.push(ws.id); }
                            byWs[ws.id].windows.push(w);
                        }
                    }

                    let out = [];
                    for (let k = 0; k < order.length; k++) {
                        const g = byWs[order[k]];
                        const localWs = g.wsId - win.wsOffset + 1;
                        if (g.windows.length === 1) {
                            const w = g.windows[0];
                            out.push({
                                isGroup: false,
                                address: w.address,
                                toplevel: w.toplevel,
                                wsId: g.wsId,
                                localWs: localWs,
                                title: w.title,
                                cls: w.cls,
                                iconName: w.iconName,
                                active: w.active,
                                windows: [w]
                            });
                        } else {
                            const rep = g.windows.find(w => w.active) || g.windows[0];
                            // icon summary DEDUPLICATED by class -- if there are several
                            // windows of the SAME app (e.g. 3 kitty) the icon isn't
                            // repeated 3 times in the row, it's shown ONCE with an
                            // "x3" badge in the corner.
                            let counts = {};
                            let iconFor = {};
                            let iconOrder = [];
                            for (const w of g.windows) {
                                const key = w.cls || w.iconName;
                                if (!(key in counts)) { counts[key] = 0; iconFor[key] = w.iconName; iconOrder.push(key); }
                                counts[key]++;
                            }
                            const iconSummary = iconOrder.map(key => ({ iconName: iconFor[key], count: counts[key] }));
                            out.push({
                                isGroup: true,
                                address: rep.address,
                                toplevel: rep.toplevel,
                                wsId: g.wsId,
                                localWs: localWs,
                                // not shown on screen (icons-only), but kept
                                // complete so the text filter can still
                                // find individual apps inside the group
                                title: g.windows.length + " apps: " + g.windows.map(w => w.title).join(", "),
                                cls: g.windows.map(w => w.cls).join(" "),
                                iconName: rep.iconName,
                                iconSummary: iconSummary,
                                active: g.windows.some(w => w.active),
                                windows: g.windows
                            });
                        }
                    }
                    // active first, then by workspace
                    out.sort((a, b) => (b.active - a.active) || (a.wsId - b.wsId));
                    return out;
                }

                // debounced snapshot of windowsModelRaw -- only updated
                // 200ms after the LAST change (not each one), so a
                // burst of N windows opening in a row rebuilds the
                // grid (and its live captures) ONCE, not N times.
                property var windowsModel: windowsModelRaw
                onWindowsModelRawChanged: modelDebounce.restart()
                Timer {
                    id: modelDebounce
                    interval: 200
                    onTriggered: win.windowsModel = win.windowsModelRaw
                }

                readonly property var displayModel: {
                    const q = win.query.trim().toLowerCase();
                    if (q.length === 0) return win.windowsModel;
                    return win.windowsModel.filter(e =>
                        (e.title || "").toLowerCase().includes(q) ||
                        (e.cls || "").toLowerCase().includes(q));
                }

                // how many columns fit in the grid given the card's real
                // width -- used both to draw the GridView and so that
                // Up/Down jump by row instead of item by item.
                readonly property real gridInnerWidth: card.width - 28
                // at most 4 per row, fewer if they don't fit or there are
                // few apps.
                readonly property int gridColumns: Math.min(4, Math.max(1, Math.floor(win.gridInnerWidth / 170)))

                function clampSel(i) {
                    return Math.max(0, Math.min(win.displayModel.length - 1, i));
                }
                function move(delta) {
                    win.selectedIndex = win.clampSel(win.selectedIndex + delta);
                }
                function moveRow(dir) {
                    win.selectedIndex = win.clampSel(win.selectedIndex + dir * win.gridColumns);
                }

                // focus: jumps to the workspace (Hyprland.dispatch, no subprocess --
                // same method WorkspacesWidget.qml uses natively) and then
                // focuses the specific window.
                //
                // Real BUG found live (2 layers): (1) the string selector
                // "address:" + tl.address failed with "window not found" because
                // tl.address (Quickshell) comes WITHOUT the "0x" prefix that syntax
                // expects. (2) the "fix" first tried -- the OBJECT selector
                // hl.get_windows({address=...})[1] -- turned out to be EVEN MORE broken:
                // confirmed live with hyprctl repl that this hyprland-lua fork
                // completely ignores the "address" filter in get_windows (with
                // ANY address, real or made-up, with or without "0x", it always
                // returns ALL windows) and [1] always grabbed the SAME
                // window no matter what -- that was the real reported bug
                // ("I picked an app and it took me to another one", ALWAYS the same). The
                // string selector WITH the "0x" added DOES work (confirmed
                // live: focus moved exactly to the requested window).
                function focusEntry(entry) {
                    if (!entry) return;
                    Hyprland.dispatch('hl.dsp.focus({ workspace = ' + entry.wsId + ' })');
                    Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + entry.address + '" })');
                    win.open = false;
                }
                function focusSelected() {
                    win.focusEntry(win.displayModel[win.selectedIndex]);
                }

                // close a single app from the grid without closing the menu --
                // same "address:0x..." string selector as focusEntry (the
                // OBJECT selector via get_windows is confirmed broken, see above).
                // Arms ignoreNextGrabClear because closing a window moves focus
                // in Hyprland briefly, which breaks HyprlandFocusGrab and used to close the
                // whole menu as a side effect (real reported bug).
                function closeEntry(entry) {
                    if (!entry) return;
                    win.ignoreNextGrabClear = true;
                    grabClearGuardTimer.restart();
                    Hyprland.dispatch('hl.dsp.window.close({ window = "address:0x' + entry.address + '" })');
                }

                onQueryChanged: win.selectedIndex = 0

                // click outside -> close
                MouseArea {
                    anchors.fill: parent
                    onClicked: win.open = false
                    onWheel: event => {
                        if (event.angleDelta.y > 0) win.move(-1);
                        else if (event.angleDelta.y < 0) win.move(1);
                    }
                }

                Item {
                    id: keyHandler
                    anchors.fill: parent
                    focus: true

                    Keys.onEscapePressed: win.open = false
                    Keys.onUpPressed: win.moveRow(-1)
                    Keys.onDownPressed: win.moveRow(1)
                    Keys.onLeftPressed: win.move(-1)
                    Keys.onRightPressed: win.move(1)
                    Keys.onReturnPressed: win.focusSelected()
                    Keys.onEnterPressed: win.focusSelected()
                    Keys.onPressed: event => {
                        if (event.text.length === 1 && event.text >= " " && !search.activeFocus) {
                            search.text += event.text;
                            search.forceActiveFocus();
                            event.accepted = true;
                        }
                    }
                }

                // ---------- card: solid, no blur -- same as Launcher.qml ----------
                Rectangle {
                    id: card

                    anchors.centerIn: parent
                    width: 720
                    height: Math.min(600, 108 + grid.contentHeight)
                    radius: theme.cornerRadius
                    color: theme.base
                    border.width: 1
                    border.color: Qt.alpha(theme.surface2, 0.6)

                    opacity: win.openProg
                    scale: 0.92 + 0.08 * win.openProg
                    Behavior on scale {
                        NumberAnimation {
                            duration: win.open ? 420 : 200
                            easing.type: win.open ? Easing.OutBack : Easing.InQuad
                            easing.overshoot: win.open ? 1.28 : 1.0
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Open apps — " + win.modelData.name
                                color: theme.subtext0
                                font.family: theme.fontFamily
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }
                        }

                        TextField {
                            id: search
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            placeholderText: "Filter…"
                            color: theme.text
                            placeholderTextColor: theme.subtext0
                            font.family: theme.fontFamily
                            font.pixelSize: 13
                            leftPadding: 12
                            rightPadding: 12
                            background: Rectangle {
                                radius: theme.borderRadius
                                color: search.activeFocus ? Qt.darker(theme.surface0, 1.14) : theme.surface0
                                Behavior on color { ColorAnimation { duration: 180 } }
                                border.width: search.activeFocus ? 1 : 0
                                border.color: theme.mauve
                            }
                            onTextChanged: win.query = text
                            Keys.onEscapePressed: win.open = false
                            Keys.onUpPressed: win.moveRow(-1)
                            Keys.onDownPressed: win.moveRow(1)
                            Keys.onReturnPressed: win.focusSelected()
                            Keys.onEnterPressed: win.focusSelected()
                        }

                        Item {
                            id: gridWrap
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // selection bubble in VIEWPORT coordinates (not
                            // content ones): when reaching the
                            // last visible row and going further down, the bubble
                            // stays still at the edge and the apps keep scrolling
                            // UNDER it, instead of chasing them on every
                            // key press. Done by subtracting grid.contentY from the cell
                            // position, instead of using the native "highlight:"
                            // (which lives INSIDE the scrollable content and whose
                            // own animation competed with the
                            // positionViewAtIndex jump, feeling doubled).
                            Rectangle {
                                id: bubble
                                z: 0
                                visible: !!grid.currentItem
                                width: grid.currentItem ? grid.currentItem.width - 6 : 0
                                // height = what the content really takes (header +
                                // preview already fitted to its aspect ratio), not the fixed
                                // cell height -- otherwise it's bigger than what's visible
                                // (real bug after shrinking the preview to its aspect).
                                height: grid.currentItem
                                    ? Math.min(grid.currentItem.height - 6, Math.max(0, grid.currentItem.visualContentHeight - 6))
                                    : 0
                                x: grid.currentItem ? grid.currentItem.x + 3 : 0
                                radius: theme.borderRadius
                                // SOLID fill -- same treatment as morphHighlight
                                // in Launcher.qml (no translucent bubble/border)
                                color: theme.mauve

                                readonly property real rawY: grid.currentItem ? (grid.currentItem.y + 3 - grid.contentY) : 0
                                y: Math.max(0, Math.min(grid.height - height, rawY))

                                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }

                            GridView {
                                id: grid
                                z: 1
                                anchors.fill: parent
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: false
                                model: win.displayModel
                                currentIndex: win.selectedIndex
                                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                                cellWidth: width / win.gridColumns
                                cellHeight: 172

                            delegate: Item {
                                id: entryItem
                                required property var modelData
                                required property int index
                                width: GridView.view.cellWidth
                                height: GridView.view.cellHeight
                                readonly property bool isSelected: index === win.selectedIndex
                                // REAL height taken by the content (header + preview already
                                // fitted to its aspect ratio), not the fixed cell height --
                                // the selection bubble uses this so it isn't bigger
                                // than what's actually visible (real bug after shrinking
                                // the preview to its real aspect ratio).
                                readonly property real visualContentHeight: headerRow.height + cellContent.spacing + previewFrame.height + 2 * cellContent.anchors.margins

                                HoverHandler {
                                    onHoveredChanged: if (hovered) win.selectedIndex = entryItem.index
                                }
                                TapHandler {
                                    id: cellTap
                                    // explicit guard, doesn't rely on the X's MouseArea
                                    // "blocking" this TapHandler (real bug: it didn't, the
                                    // tap on the X always ended up focusing the app too) --
                                    // if the mouse is over the X at tap time,
                                    // focus is ignored completely, closeArea.onClicked handles it.
                                    onTapped: {
                                        if (closeArea.containsMouse) return;
                                        win.focusEntry(entryItem.modelData);
                                    }
                                }

                                // press feedback -- same as delegateContent in
                                // Launcher.qml (scale 0.98, OutBack overshoot 1.2, 180ms)
                                ColumnLayout {
                                    id: cellContent
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    scale: cellTap.pressed ? 0.98 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                    RowLayout {
                                        id: headerRow
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // normal case (1 single app on the workspace): rounded icon
                                        // box + name -- same treatment as
                                        // delegateIconArea in Launcher.qml (surface2, slightly
                                        // lighter/tinted mauve when selected).
                                        Rectangle {
                                            visible: !entryItem.modelData.isGroup
                                            Layout.preferredWidth: 24
                                            Layout.preferredHeight: 24
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: Math.max(2, theme.borderRadius - 2)
                                            color: entryItem.isSelected
                                                ? Qt.tint(theme.surface2, Qt.rgba(theme.mauve.r, theme.mauve.g, theme.mauve.b, 0.2))
                                                : theme.surface2
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                            IconImage {
                                                anchors.fill: parent
                                                anchors.margins: 3
                                                asynchronous: true
                                                source: Quickshell.iconPath(entryItem.modelData.iconName, "application-x-executable")
                                                scale: entryItem.isSelected ? 1.1 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            visible: !entryItem.modelData.isGroup
                                            text: entryItem.modelData.title
                                            color: entryItem.isSelected ? theme.crust : theme.text
                                            font.family: theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: entryItem.isSelected ? Font.Bold : (entryItem.modelData.active ? Font.DemiBold : Font.Medium)
                                            elide: Text.ElideRight
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }

                                        // group case (2+ apps on the same workspace): ONLY icons,
                                        // no name -- a single name would be ambiguous with several
                                        // apps. Deduplicated by class: if there are
                                        // several windows of the SAME app (e.g. 3 kitty) ONE
                                        // icon is shown with an "x3" badge in the corner, not 3
                                        // repeated icons.
                                        Row {
                                            Layout.fillWidth: true
                                            visible: entryItem.modelData.isGroup
                                            spacing: 6

                                            Repeater {
                                                model: entryItem.modelData.isGroup ? entryItem.modelData.iconSummary : []
                                                delegate: Item {
                                                    required property var modelData
                                                    implicitWidth: 18
                                                    implicitHeight: 18

                                                    IconImage {
                                                        anchors.fill: parent
                                                        asynchronous: true
                                                        source: Quickshell.iconPath(modelData.iconName, "application-x-executable")
                                                    }

                                                    Rectangle {
                                                        visible: modelData.count > 1
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        anchors.rightMargin: -5
                                                        anchors.bottomMargin: -5
                                                        implicitWidth: Math.max(14, badgeText.implicitWidth + 6)
                                                        implicitHeight: 12
                                                        radius: 6
                                                        color: theme.mauve
                                                        border.width: 1
                                                        border.color: theme.base

                                                        Text {
                                                            id: badgeText
                                                            anchors.centerIn: parent
                                                            text: "x" + modelData.count
                                                            font.family: theme.fontFamily
                                                            font.pixelSize: 8
                                                            font.bold: true
                                                            color: theme.crust
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            text: "ws " + entryItem.modelData.localWs
                                            color: entryItem.isSelected ? theme.crust : theme.subtext0
                                            opacity: entryItem.isSelected ? 0.9 : 0.85
                                            font.family: theme.fontFamily
                                            font.pixelSize: 10
                                            Layout.alignment: Qt.AlignVCenter
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }

                                        // X to close this single app without closing the menu,
                                        // to the right of "ws N". Uses MouseArea
                                        // (not TapHandler) on purpose: a child TapHandler did NOT
                                        // block the whole cell's TapHandler (real bug
                                        // found live -- the click always focused the app
                                        // instead of closing it). MouseArea takes the exclusive grab
                                        // of the click and if it accepts it, the ancestor TapHandler never
                                        // completes the gesture.
                                        Rectangle {
                                            id: closeBtn
                                            // ambiguous which one to close with 2+ apps on the same
                                            // workspace -- hidden on group cells.
                                            visible: !entryItem.modelData.isGroup
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitWidth: 16
                                            implicitHeight: 16
                                            radius: 8
                                            color: closeArea.containsMouse
                                                ? Qt.alpha(entryItem.isSelected ? theme.crust : theme.text, 0.16)
                                                : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                color: {
                                                    if (closeArea.containsMouse) return entryItem.isSelected ? theme.crust : theme.text;
                                                    return entryItem.isSelected ? Qt.alpha(theme.crust, 0.75) : theme.subtext0;
                                                }
                                                font.pixelSize: 10
                                                font.family: theme.fontFamily
                                            }

                                            MouseArea {
                                                id: closeArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    win.closeEntry(entryItem.modelData);
                                                    mouse.accepted = true;
                                                }
                                            }
                                        }
                                    }

                                    // live preview of the real window -- same mechanism
                                    // caelestia uses in windowinfo/Preview.qml
                                    // (ScreencopyView.captureSource = toplevel.wayland). "live"
                                    // tied to win.open: no captures running while the menu
                                    // is closed (zero polling/background work at rest).
                                    //
                                    // previewSlot reserves the available space in the cell;
                                    // "previewFrame" (the frame with color/border) does NOT fill
                                    // it all -- it SHRINKS to match the real aspect ratio
                                    // of the captured window exactly, centred inside. Before, the
                                    // frame was always the full cell size and the
                                    // (smaller, "letterboxed") preview left grey bars
                                    // top/bottom or on the sides -- the frame
                                    // now adapts to the preview, not the other way round.
                                    Item {
                                        id: previewSlot
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        Rectangle {
                                            id: previewFrame
                                            readonly property bool isGroup: !!entryItem.modelData.isGroup

                                            // pinned to the top (not centred in the whole slot) --
                                            // otherwise, with the frame already shrunk to its real
                                            // aspect ratio, it floated in the middle of the slot's
                                            // leftover space instead of right under the header
                                            // (real bug: "the preview is lower
                                            // than it should be").
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            radius: theme.borderRadius
                                            clip: true
                                            color: theme.surface1
                                            border.width: entryItem.isSelected ? 1 : 0
                                            border.color: theme.mauve

                                            readonly property real aspect: (!isGroup && preview.sourceSize.width > 0 && preview.sourceSize.height > 0)
                                                ? preview.sourceSize.width / preview.sourceSize.height
                                                : (previewSlot.width / previewSlot.height)

                                            // group (2+ apps) -> fills the whole slot, the mosaic
                                            // inside splits that space by itself. single app -> it
                                            // shrinks to its real aspect ratio (see comment above).
                                            width: isGroup ? previewSlot.width : Math.min(previewSlot.width, previewSlot.height * aspect)
                                            height: isGroup ? previewSlot.height : Math.min(previewSlot.height, previewSlot.width / aspect)
                                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                            // small margin on purpose: without it the video (corners
                                            // always square) covers both the frame's rounded radius
                                            // and the mauve selection border -- QML's "clip: true"
                                            // only clips to the rectangle, not the rounded
                                            // shape (real bug: the Serpantinum details
                                            // and rounded borders were lost).
                                            //
                                            // "live" ONLY on the selected cell -- not on all
                                            // visible ones at once. Real bug found live:
                                            // with many simultaneous live captures, opening several
                                            // apps in a row (while the model rebuilds)
                                            // saturated wlr-screencopy and Hyprland killed the process
                                            // ("error in client communication").
                                            ScreencopyView {
                                                id: preview
                                                visible: !previewFrame.isGroup
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                captureSource: (!previewFrame.isGroup && entryItem.modelData.toplevel) ? entryItem.modelData.toplevel.wayland : null
                                                live: win.open && !previewFrame.isGroup && entryItem.isSelected
                                                paintCursor: false
                                            }

                                            IconImage {
                                                anchors.centerIn: parent
                                                implicitSize: 40
                                                asynchronous: true
                                                visible: !previewFrame.isGroup && !preview.hasContent
                                                opacity: 0.5
                                                source: Quickshell.iconPath(entryItem.modelData.iconName, "application-x-executable")
                                            }

                                            // group (2+ apps on the same workspace): mosaic with the
                                            // live capture of EACH window -- there's no way to
                                            // screencopy a whole workspace that isn't
                                            // visible right now on a monitor (it isn't a surface
                                            // of its own), this is the most faithful way to "see the apps"
                                            // without faking a screenshot.
                                            GridLayout {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                visible: previewFrame.isGroup
                                                columns: (entryItem.modelData.windows && entryItem.modelData.windows.length > 2) ? 2 : 1
                                                rowSpacing: 4
                                                columnSpacing: 4

                                                Repeater {
                                                    model: previewFrame.isGroup ? entryItem.modelData.windows : []
                                                    delegate: Rectangle {
                                                        id: tile
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        radius: Math.max(2, theme.borderRadius - 4)
                                                        clip: true
                                                        color: theme.mantle

                                                        // "live" only if this group cell is the
                                                        // selected one -- same reason as the simple
                                                        // preview: avoid many simultaneous captures
                                                        // (real bug: it saturated wlr-screencopy and
                                                        // Hyprland killed the process when opening several
                                                        // apps in a row).
                                                        ScreencopyView {
                                                            id: tilePreview
                                                            anchors.fill: parent
                                                            anchors.margins: 1
                                                            captureSource: tile.modelData.toplevel ? tile.modelData.toplevel.wayland : null
                                                            live: win.open && previewFrame.isGroup && entryItem.isSelected
                                                            paintCursor: false
                                                        }

                                                        IconImage {
                                                            anchors.centerIn: parent
                                                            implicitSize: 20
                                                            asynchronous: true
                                                            visible: !tilePreview.hasContent
                                                            opacity: 0.5
                                                            source: Quickshell.iconPath(tile.modelData.iconName, "application-x-executable")
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
                    }
                }
            }
        }
    }
}
