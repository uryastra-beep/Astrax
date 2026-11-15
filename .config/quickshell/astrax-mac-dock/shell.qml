import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../astrax-common/motionblur"
import "../../astrax-common/lg"

ShellRoot {
    id: dock
    property var settings: ({})
    readonly property var cfg: settings.macDock || ({})
    // iOS-style tinted icons: off | fixed (colour picked in settings) | follow (Astrax theme colour)
    readonly property string tintMode: cfg.iconTint === "fixed" || cfg.iconTint === "follow" ? cfg.iconTint : "off"
    readonly property color tintColorResolved: tintMode === "follow"
        ? ((settings.theme && settings.theme.colors && settings.theme.colors.mauve) || "#9566ff")
        : (cfg.iconTintColor || "#9566ff")
    readonly property bool enabled: cfg.enabled === true
    readonly property var monitors: !enabled ? [] : cfg.allScreens === true ? Quickshell.screens : [Quickshell.screens[0]]
    // While a drag-reorder is being saved, show the new order at once instead of waiting for settings.json
    property var pinsOverride: null
    readonly property var pins: pinsOverride !== null ? pinsOverride : Array.isArray(cfg.apps) ? cfg.apps : ["org.gnome.Nautilus", "kitty"]
    readonly property var apps: {
        const groups = {};
        for (const tl of Hyprland.toplevels.values) {
            const cls = tl.wayland ? tl.wayland.appId || "" : "";
            if (!cls || /^(widget-|widget4-|widget5-)/.test(cls)) continue;
            const entry = DesktopEntries.heuristicLookup(cls);
            const key = entry ? entry.id : cls;
            if (!groups[key]) groups[key] = {id:key, name:entry ? entry.name : cls, icon:entry ? entry.icon : cls, entry:entry, windows:[], pinned:false};
            groups[key].windows.push(tl);
        }
        const result = []; const used = {};
        for (const id of pins) {
            const entry = DesktopEntries.byId(id);
            if (!entry) continue;
            const key = entry.id;
            if (used[key]) continue;
            const group = groups[key] || {id:key,name:entry.name,icon:entry.icon,entry:entry,windows:[]};
            group.pinned = true; result.push(group); used[key] = true;
        }
        const running = cfg.showRunning === false ? [] : Object.keys(groups).filter(k => !used[k]).map(k => groups[k]);
        if (result.length && running.length) result.push({id:"separator",separator:true});
        const list = result.concat(running);
        if (list.length) list.push({id:"separator-trash",separator:true});
        list.push({id:"trash",name:"Trash",icon:"",windows:[],pinned:false,trash:true});
        return list;
    }
    // Trash: full/empty state (polled; also refreshed whenever its menu opens) and the empty-trash confirmation
    property bool trashFull: false
    property bool trashConfirm: false
    readonly property string trashDir: Quickshell.env("HOME") + "/.local/share/Trash/files"
    Process {
        id: trashProbe
        command: ["sh", "-c", "[ -n \"$(ls -A \"$1\" 2>/dev/null | head -n1)\" ] && echo full || echo empty", "sh", dock.trashDir]
        stdout: StdioCollector { onStreamFinished: dock.trashFull = text.trim() === "full" }
    }
    function refreshTrash() { if (!trashProbe.running) trashProbe.running = true; }
    Timer { interval: 2500; running: true; repeat: true; triggeredOnStart: true; onTriggered: dock.refreshTrash() }
    Process { id: trashEmptier; command: ["gio", "trash", "--empty"]; onExited: dock.refreshTrash() }
    // Files dropped on the Trash tile go to the trash (gio trash: recoverable), then the full/empty state refreshes
    Timer { id: trashAfterDrop; interval: 700; onTriggered: dock.refreshTrash() }
    function trashUrls(urls) {
        const paths = [];
        for (const u of urls) {
            const t = String(u);
            if (t.indexOf("file://") === 0) paths.push(decodeURIComponent(t.substring(7)));
        }
        if (!paths.length) return;
        Quickshell.execDetached(["gio", "trash", "--"].concat(paths));
        trashAfterDrop.restart();
    }
    function openTrash() { Quickshell.execDetached(["xdg-open", trashDir]); }
    function emptyTrash() { if (!trashEmptier.running) trashEmptier.running = true; }
    // The icons live in a stable list (not the `apps` array, which rebuilds every delegate on each change),
    // so an app that appears slides open a gap and grows in, and one that goes away shrinks and closes it.
    // Rows of apps that went away stay (leaving) until their delegate has finished shrinking.
    ListModel { id: tileModel }
    readonly property var appsById: { const m = {}; for (const a of apps) m[a.id] = a; return m; }
    property bool tilesReady: false   // rows added after start-up animate in; the first fill does not
    property int leavingCount: 0
    Timer { interval: 1500; running: true; onTriggered: dock.tilesReady = true }
    // `fresh` only means "added just now". Cleared shortly after, so a Dock window created later
    // (it is torn down while hidden) shows its icons at once instead of growing them in again.
    Timer {
        id: freshClear
        interval: 600
        onTriggered: { for (let i = 0; i < tileModel.count; i++) if (tileModel.get(i).fresh) tileModel.setProperty(i, "fresh", false); }
    }
    onAppsChanged: syncTiles()
    function syncTiles() {
        const want = apps.map(a => a.id);
        let leaving = 0;
        for (let i = 0; i < tileModel.count; i++) {
            const row = tileModel.get(i), keep = want.indexOf(row.tid) >= 0;
            if (!keep && !row.leaving) tileModel.setProperty(i, "leaving", true);
            else if (keep && row.leaving) tileModel.setProperty(i, "leaving", false);
            if (!keep) leaving++;
        }
        leavingCount = leaving;
        let pos = 0;
        for (const id of want) {
            while (pos < tileModel.count && tileModel.get(pos).leaving) pos++;   // leaving rows stay where they are
            let at = -1;
            for (let i = pos; i < tileModel.count; i++) if (tileModel.get(i).tid === id) { at = i; break; }
            if (at < 0) tileModel.insert(pos, { tid: id, leaving: false, fresh: tilesReady });
            else if (at !== pos) tileModel.move(at, pos, 1);
            pos++;
        }
        freshClear.restart();
    }
    function reapTile(tid) {
        for (let i = 0; i < tileModel.count; i++) {
            const row = tileModel.get(i);
            if (row.tid === tid && row.leaving) { tileModel.remove(i); break; }
        }
        let leaving = 0;
        for (let i = 0; i < tileModel.count; i++) if (tileModel.get(i).leaving) leaving++;
        leavingCount = leaving;
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/serpantinum/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { dock.settings = JSON.parse(text()); } catch(e) {} }
    }
    function address(value) { return "0x" + String(value).replace(/^0x/, ""); }
    function activate(app, forceNew) {
        if (!app) return;
        if (!forceNew && app.windows.length) {
            const current = app.windows.findIndex(w => w.activated);
            // minimized first: a click on the Dock restores it (brings it to the active workspace)
            const mini = app.windows.find(w => w.workspace && w.workspace.name === "special:minimized");
            if (mini) {
                // genie from the icon (the script falls back to a plain restore if it fails)
                Quickshell.execDetached(["python3", "-I", Quickshell.env("HOME") + "/scripts/genie-restore.py", address(mini.address)]);
                return;
            }
            const target = app.windows[(current+1) % app.windows.length];
            if (target.workspace) Hyprland.dispatch('hl.dsp.focus({ workspace = '+target.workspace.id+' })');
            Hyprland.dispatch('hl.dsp.focus({ window = "address:'+address(target.address)+'" })');
        } else {
            // fresh entry: Quickshell recreates the DesktopEntry objects when the .desktop files change and the reference
            // stored in `app.entry` goes stale ("execute is not a function")
            const fresh = DesktopEntries.byId(app.id) || (app.entry && app.entry.id ? DesktopEntries.byId(app.entry.id) : null);
            if (fresh) fresh.execute();
        }
    }
    function closeApp(app) {
        if (!app) return;
        // with a closing animation (the script falls back to a normal close if it fails)
        Quickshell.execDetached(["python3", "-I", Quickshell.env("HOME") + "/scripts/genie-close.py"].concat(app.windows.map(w => address(w.address))));
    }
    Process {
        id: pinWriter
        command: []
    }
    Process {
        id: orderWriter
        command: []
        onExited: overrideClear.restart()
    }
    // settings.json is reloaded by the FileView shortly after control.py replaces it
    Timer { id: overrideClear; interval: 500; onTriggered: dock.pinsOverride = null }
    function commitOrder(ids) {
        const rest = pins.filter(x => ids.indexOf(x) < 0);
        pinsOverride = ids.concat(rest);
        orderWriter.running = false;
        orderWriter.command = ["python3", Quickshell.shellPath("control.py"), "order", JSON.stringify(ids)];
        orderWriter.running = true;
    }
    function togglePin(app) {
        if (!app || pinWriter.running) return;
        pinWriter.command = ["python3",Quickshell.shellPath("control.py"),"pin",app.id]; pinWriter.running = true;
    }
    Process {
        id: blurSetup
        command: ["hyprctl","eval","dofile("+JSON.stringify(Quickshell.shellPath("blur.lua"))+")"]
    }
    Component.onCompleted: {
        syncTiles();
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) blurSetup.running = true;
    }
    Timer { id: coverRefresh; interval: 90; onTriggered: Hyprland.refreshToplevels() }
    // hl.plugin / scripts ask to show the Dock NOW (e.g. before the genie): qs ipc -c astrax-mac-dock call dock reveal
    property var units: []
    IpcHandler {
        target: "dock"
        function reveal(): void { for (const u of dock.units) u.forceReveal(1500); }
        // center of the icon of the app `cls` in global layout coordinates ("x,y"), or "" if there is no tile
        function iconPos(cls: string, mon: string): string {
            for (const u of dock.units) {
                if (!u.modelData || u.modelData.name !== mon || !u.winRef) continue;
                const r = u.winRef.iconCenter(cls);
                if (r) return Math.round(u.modelData.x + r.x) + "," + Math.round(u.modelData.y + u.modelData.height - u.winRef.height + r.y);
            }
            return "";
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && !blurSetup.running) blurSetup.running = true;
            // the Dock decides whether to hide from the real window sizes: refresh it when they change
            if (["changefloatingmode","fullscreen","openwindow","closewindow","movewindowv2","movewindow","activewindowv2","workspacev2","focusedmon"].indexOf(event.name) >= 0) coverRefresh.restart();
        }
    }
    Variants {
        model: dock.monitors
        delegate: Scope {
            id: unit
            required property var modelData
            readonly property bool configuredAutoHide: dock.cfg.autoHide === true
            // which screens "show on the desktop" applies to: all | hdmi | laptop (eDP = laptop)
            readonly property bool desktopScreenOk: {
                const w = dock.cfg.desktopScreens || "all";
                const laptop = !!(unit.modelData && /^eDP/i.test(unit.modelData.name));
                return w === "all" || (w === "laptop" ? laptop : !laptop);
            }
            readonly property bool desktopEmpty: {
                const monitor = Hyprland.monitors.values.find(m => unit.modelData && m.name === unit.modelData.name);
                if (!monitor || !monitor.activeWorkspace) return false;
                const workspaceId = monitor.activeWorkspace.id;
                const info = monitor.lastIpcObject || {};
                const specialId = info.specialWorkspace ? info.specialWorkspace.id : 0;
                return !Hyprland.toplevels.values.some(tl => {
                    const cls = tl.wayland ? tl.wayland.appId || "" : "";
                    if (/^(widget-|widget4-|widget5-)/.test(cls) || !tl.workspace) return false;
                    return tl.workspace.id === workspaceId || (specialId !== 0 && tl.workspace.id === specialId);
                });
            }
            // The Dock only hides if a window covers (almost) the whole screen or is fullscreen.
            readonly property bool windowCovers: {
                const monitor = Hyprland.monitors.values.find(m => unit.modelData && m.name === unit.modelData.name);
                if (!monitor || !monitor.activeWorkspace || !unit.modelData) return false;
                const workspaceId = monitor.activeWorkspace.id;
                const info = monitor.lastIpcObject || {};
                const specialId = info.specialWorkspace ? info.specialWorkspace.id : 0;
                const mw = unit.modelData.width, mh = unit.modelData.height;
                return Hyprland.toplevels.values.some(tl => {
                    const cls = tl.wayland ? tl.wayland.appId || "" : "";
                    if (/^(widget-|widget4-|widget5-)/.test(cls) || !tl.workspace) return false;
                    if (!(tl.workspace.id === workspaceId || (specialId !== 0 && tl.workspace.id === specialId))) return false;
                    const o = tl.lastIpcObject || {};
                    if (!o.size) return false;
                    if ((o.fullscreen || 0) > 0) return true;
                    return o.size[0] >= mw * 0.9 && o.size[1] >= mh * 0.85;
                });
            }
            // empty screen excluded in Settings ("show on the desktop" only on another screen): the Dock hides there
            readonly property bool hiddenOnEmptyDesktop: dock.cfg.showInDesktop === true && !desktopScreenOk && desktopEmpty
            readonly property bool autoHide: hiddenOnEmptyDesktop || (configuredAutoHide && windowCovers)
            // show the Dock now and keep it for `ms` milliseconds (used by the genie when minimizing)
            property double holdUntil: 0
            property bool pendingReveal: false
            property var winRef: null
            function forceReveal(ms) {
                holdUntil = Date.now() + ms;
                reveal = true;
                if (winRef) { winRef.shownOnce = true; winRef.revealed = true; winRef.hideDelayTimer.restart(); }
                else pendingReveal = true;
            }
            Component.onCompleted: dock.units.push(unit)
            // The Dock window (blur, screen capture, icons) only exists while it is shown.
            // Hidden, all that is left is a 4 px strip along the bottom edge that wakes it on hover.
            property bool reveal: false
            readonly property bool open: !autoHide || reveal
            onAutoHideChanged: reveal = true
            readonly property real zoneWidth: {
                const n = dock.apps.filter(a => !a.separator).length;
                return Math.min(modelData.width - 32, Math.max(180, n * (Number(dock.cfg.iconSize || 48) + 12) + 24));
            }
            PanelWindow {
                id: edge
                screen: unit.modelData
                visible: unit.autoHide && !unit.open
                anchors.bottom: true
                implicitWidth: unit.zoneWidth; implicitHeight: 4
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "astrax-macos-dock-edge"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton; onEntered: unit.reveal = true }
                DropArea { anchors.fill: parent; keys: ["text/uri-list"]; onEntered: drag => { unit.reveal = true; drag.accepted = false; } }
            }
            LazyLoader {
                active: unit.open
                PanelWindow {
                    id: win
                    screen: unit.modelData
                    anchors.bottom: true; anchors.left: true; anchors.right: true
                    implicitHeight: Math.ceil(baseIcon*1.7 + 240)
                    color: "transparent"
                    exclusionMode: dock.cfg.reserveSpace === true && !configuredAutoHide ? ExclusionMode.Normal : ExclusionMode.Ignore
                    exclusiveZone: dock.cfg.reserveSpace === true && !configuredAutoHide ? baseIcon+34 : 0
                    WlrLayershell.namespace: "astrax-macos-dock"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    readonly property bool configuredAutoHide: dock.cfg.autoHide === true
                    readonly property bool autoHide: unit.autoHide
                    // layout uses the final size from the start; the surface itself briefly reports a provisional one
                    readonly property real w: screen ? screen.width : width
                    readonly property real h: implicitHeight
                    property bool revealed: false   // set on the next frame, so a freshly loaded Dock slides in
                    property real hoverPosition: -10
                    property real lastHoverX: 0
                    onHoverPositionChanged: if (hoverPosition >= 0) lastHoverX = hoverPosition * (baseIcon + 12)
                    property var menuAnchor: null
                    property var menuApp: null
                    property bool fileDrag: false   // a file is being dragged over the Dock (from another app)
                    onMenuAppChanged: dock.trashConfirm = false
                    // One shared name tag that glides between icons (instead of one tag per icon appearing in place)
                    property var hoverTile: null
                    property var labelTile: null
                    property string labelName: ""
                    readonly property bool labelOn: hoverTile !== null && !menuOpen && showing && dock.cfg.showLabels !== false && dragFrom < 0
                    // Drag to reorder pinned apps: the dragged icon follows the pointer, the others slide aside
                    property int dragFrom: -1
                    property int dragTarget: -1
                    property real dragDx: 0
                    property real dragWidth: 0
                    readonly property int pinnedCount: dock.apps.filter(a => a.pinned === true).length
                    function targetFor(px) {
                        let t = 0;
                        for (let i = 0; i < pinnedCount; i++) { const it = tiles.itemAt(i); if (it && px >= it.x) t = i; }
                        return t;
                    }
                    function releaseDrag() {
                        if (dragFrom < 0) return;
                        const a = tiles.itemAt(dragFrom), b = tiles.itemAt(dragTarget);
                        let to = 0;
                        if (a && b) {
                            const aCentre = a.x + a.width/2;
                            const bCentre = dragTarget > dragFrom ? b.x + b.width - dragWidth/2 : dragTarget < dragFrom ? b.x + dragWidth/2 : aCentre;
                            to = bCentre - aCentre;
                        }
                        settle.to = to;
                        settle.restart();
                    }
                    // false for a moment after a drop: the icons already sit in their new slots, so their
                    // "slide aside" offsets must drop to 0 at once instead of animating back
                    property bool shiftAnim: true
                    function finishDrag() {
                        const from = dragFrom, to = dragTarget;
                        shiftAnim = false;
                        if (from >= 0 && to >= 0 && from !== to) {
                            const ids = dock.apps.filter(a => a.pinned === true).map(a => a.id);
                            const moved = ids.splice(from, 1)[0];
                            ids.splice(to, 0, moved);
                            dock.commitOrder(ids);
                        }
                        dragFrom = -1; dragTarget = -1; dragDx = 0; hoverPosition = -10;
                        Qt.callLater(() => { win.shiftAnim = true; });
                        hideDelay.restart();
                    }
                    NumberAnimation { id: settle; target: win; property: "dragDx"; duration: 140; easing.type: Easing.OutCubic; onFinished: win.finishDrag() }
                    readonly property bool menuOpen: menuApp !== null
                    // The menu model is rebuilt when menuApp changes. Run actions in
                    // the stable window scope, rather than a delegate being destroyed.
                    function runMenuAction(action) {
                        const app = menuApp;
                        if (app && app.trash === true) {
                            if (action === 0) { menuApp = null; dock.openTrash(); }
                            else if (dock.trashFull) {
                                if (!dock.trashConfirm) { dock.trashConfirm = true; return; }   // second click confirms: it cannot be undone
                                menuApp = null; dock.trashConfirm = false; dock.emptyTrash();
                            }
                            hideDelay.restart();
                            return;
                        }
                        menuApp = null;
                        if (action === 0) dock.togglePin(app);
                        else if (action === 1) dock.activate(app, true);
                        else dock.closeApp(app);
                        hideDelay.restart();
                    }
                    readonly property bool showing: !autoHide || revealed || menuOpen
                    readonly property bool glass: dock.cfg.glass !== false
                    readonly property real magnification: dock.cfg.magnification === false ? 0 : Math.max(0, Math.min(0.9,(dock.cfg.zoom || 155)/100-1))
                    readonly property int count: dock.apps.filter(a => !a.separator).length
                    readonly property real baseIcon: Math.max(24, Math.min(Number(dock.cfg.iconSize || 48), (win.w-80)/Math.max(1,count*(1+magnification*.35))-12))
                    readonly property real maxIcon: baseIcon*(1+magnification)
                    readonly property int margin: 12
                    // (skipped while the window is being created: the binding resolving there counts as a change and showed the Dock at once)
                    onAutoHideChanged: { if (!shownOnce) return; revealed = true; if (autoHide) hideDelay.restart(); }
                    // The first frames of a new window are slow (icons, blur shader), and a slide started then is eaten by the
                    // hitch, leaving only a fade. So draw it hidden first, give that a moment, then slide in. The timer is a fallback.
                    property bool revealArmed: true   // one-shot: later frames (e.g. the slide-out) must not restart this
                    property bool shownOnce: false
                    function startReveal() { if (shownOnce) return; shownOnce = true; revealed = true; hideDelay.restart(); }
                    property alias hideDelayTimer: hideDelay
                    // center (Dock window coords) of the icon of the app with that class, or null
                    function iconCenter(cls) {
                        const entry = DesktopEntries.heuristicLookup(cls);
                        const key = entry ? entry.id : cls;
                        for (let i = 0; i < tileModel.count; i++) {
                            if (tileModel.get(i).tid !== key) continue;
                            const t = tiles.itemAt(i);
                            if (!t) return null;
                            const p = t.mapToItem(null, t.width / 2, t.height - 12 - t.iconSize / 2);
                            return { x: p.x, y: p.y };
                        }
                        return null;
                    }
                    Component.onCompleted: {
                        unit.winRef = win;
                        if (unit.pendingReveal) { unit.pendingReveal = false; startReveal(); }
                        else if (autoHide) revealStart.start();
                    }
                    Component.onDestruction: if (unit.winRef === win) unit.winRef = null
                    Connections {
                        target: contentItem.Window.window
                        enabled: win.revealArmed
                        function onFrameSwapped() { win.revealArmed = false; warmUp.start(); }
                    }
                    Timer { id: warmUp; interval: 150; onTriggered: win.startReveal() }
                    Timer { id: revealStart; interval: 700; onTriggered: win.startReveal() }
                    // Once hidden (after its slide-out), the whole window is torn down; the edge strip brings it back
                    Timer { interval: 360; running: win.autoHide && win.shownOnce && !win.showing; onTriggered: unit.reveal = false }
                    Timer {
                        id: hideDelay
                        interval: Math.max(150,Number(dock.cfg.hideDelay || 650))
                        onTriggered: {
                            if (Date.now() < unit.holdUntil) { hideDelay.restart(); return; }
                            if (!dockHover.hovered && !menuHover.hovered && !win.fileDrag && win.dragFrom < 0) { win.revealed = false; win.menuApp = null; win.hoverPosition = -10; }
                        }
                    }
                    // Keep input limited to the visible Dock, even above other overlays.
                    // Explicit coordinates avoid stale item mappings while the row resizes.
                    mask: Region {
                        x: win.showing ? interaction.x : revealZone.x
                        y: win.showing ? interaction.y : revealZone.y
                        width: win.showing ? interaction.width : revealZone.width
                        height: win.showing ? interaction.height : revealZone.height
                        Region {
                            x: contextMenu.x
                            y: contextMenu.y
                            width: win.menuOpen ? contextMenu.width : 0
                            height: win.menuOpen ? contextMenu.height : 0
                        }
                    }
                    // "Clean" copy of the desktop for the glass: still wallpaper + the windows of this monitor
                    // (no widgets, no dock, no bar). Refreshed at 60 fps while the dock is active and 30 at rest.
                    Item {
                        id: backScene
                        width: win.screen ? win.screen.width : 1; height: win.screen ? win.screen.height : 1
                        readonly property bool ready: wall.hasContent
                        readonly property var monitor: Hyprland.monitors.values.find(m => win.screen && m.name === win.screen.name)
                        readonly property var winList: {
                            const mon = monitor;
                            if (!mon || !mon.activeWorkspace) return [];
                            const wsId = mon.activeWorkspace.id;
                            const info = mon.lastIpcObject || {};
                            const specialId = info.specialWorkspace ? info.specialWorkspace.id : 0;
                            const list = Hyprland.toplevels.values.filter(tl => {
                                const cls = tl.wayland ? tl.wayland.appId || "" : "";
                                if (!tl.wayland || /^(widget-|widget4-|widget5-)/.test(cls) || !tl.workspace) return false;
                                const o = tl.lastIpcObject || {};
                                if (!o.size || !o.at || o.mapped === false || o.hidden === true) return false;
                                return tl.workspace.id === wsId || (specialId !== 0 && tl.workspace.id === specialId);
                            });
                            // tiled and least recent at the bottom; floating and focused on top
                            list.sort((x, y) => {
                                const ox = x.lastIpcObject, oy = y.lastIpcObject;
                                const fx = ox.floating ? 1 : 0, fy = oy.floating ? 1 : 0;
                                if (fx !== fy) return fx - fy;
                                return (oy.focusHistoryID || 0) - (ox.focusHistoryID || 0);
                            });
                            return list;
                        }
                        WallBackdrop { id: wall; anchors.fill: parent; screenName: win.screen ? win.screen.name : ""; active: win.glass && win.showing && win.visible }
                        Repeater {
                            model: backScene.winList
                            ScreencopyView {
                                id: winCap
                                required property var modelData
                                readonly property var o: modelData.lastIpcObject || ({})
                                captureSource: win.glass && win.showing && win.visible ? modelData.wayland : null
                                live: false
                                x: (o.at ? o.at[0] : 0) - (backScene.monitor && backScene.monitor.lastIpcObject ? backScene.monitor.lastIpcObject.x || 0 : 0)
                                y: (o.at ? o.at[1] : 0) - (backScene.monitor && backScene.monitor.lastIpcObject ? backScene.monitor.lastIpcObject.y || 0 : 0)
                                width: o.size ? o.size[0] : 1; height: o.size ? o.size[1] : 1
                                Timer {
                                    interval: win.revealed ? 16 : 33
                                    running: win.glass && win.showing && win.visible
                                    repeat: true; triggeredOnStart: true
                                    onTriggered: winCap.captureFrame()
                                }
                            }
                        }
                    }
                    ShaderEffectSource { id: backdrop; sourceItem: backScene; hideSource: true; visible: false; live: win.glass && win.showing && win.visible }
                    Item {
                        id: revealZone
                        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(win.w-32, Math.max(180,frame.width)); height: 4
                        MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton; onEntered: { if (!win.shownOnce) return; win.revealed = true; hideDelay.stop(); } }   // the pointer is already on this strip when the window is created: that must not skip the slide-in
                    }
                    Item {
                        id: interaction
                        x: (win.w-width)/2; y: win.h-height-win.margin
                        width: Math.min(win.w-24, row.width+24); height: win.maxIcon+28
                        opacity: win.showing ? 1 : 0.003   // not 0: an invisible item is not rendered, so icons and shaders would load only once the slide has started
                        transform: Translate { y: win.showing ? 0 : interaction.height+win.margin+4; Behavior on y { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } } }
                        Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                        HoverHandler {
                            id: dockHover
                            onHoveredChanged: {
                                if (hovered) { win.revealed = true; hideDelay.stop(); }
                                else { win.hoverPosition = -10; win.hoverTile = null; hideDelay.restart(); }
                            }
                        }
                        Rectangle {
                            id: frame
                            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width; height: win.baseIcon+22; radius: 23
                            color: win.glass ? "#38202025" : "#e629292d"
                            border.width: 1; border.color: "#42ffffff"
                            ShaderEffect {
                                anchors.fill: parent
                                visible: win.glass && backScene.ready
                                property var src: backdrop
                                property real radius: frame.radius
                                property real strength: 1.0
                                property real band: height * 0.5   // the glass covers the whole dock, not just the edges
                                property vector2d stretch: Qt.vector2d(1,1)
                                property vector2d size: Qt.vector2d(width,height)
                                property vector2d screen: Qt.vector2d(win.screen ? win.screen.width : 1,win.screen ? win.screen.height : 1)
                                property vector2d origin: Qt.vector2d(interaction.x + frame.x,
                                    (win.screen ? win.screen.height : win.h)-win.h+interaction.y+frame.y)
                                fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
                            }
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "#32ffffff" }
                                    GradientStop { position: 0.5; color: "#05ffffff" }
                                    GradientStop { position: 1; color: "#1bffffff" }
                                }
                            }
                        }
                        Row {
                            id: row
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: win.maxIcon+18
                            Repeater {
                                id: tiles
                                model: tileModel
                                delegate: Item {
                                    id: appTile
                                    required property string tid
                                    required property bool leaving
                                    required property bool fresh
                                    required property int index
                                    // the app behind this row; a row that is leaving keeps the last one it had
                                    readonly property var current: dock.appsById[tid]
                                    property var lastKnown: ({ id: tid, separator: tid === "separator", windows: [] })
                                    onCurrentChanged: if (current) lastKnown = current
                                    readonly property var modelData: current || lastKnown
                                    readonly property bool divider: modelData.separator === true
                                    readonly property real distance: Math.abs(index+0.5-win.hoverPosition)
                                    readonly property real lift: !divider && !win.menuOpen ? win.magnification*Math.exp(-distance*distance/1.5) : 0
                                    property real iconSize: win.baseIcon*(1+lift)
                                    property real bounce: 0
                                    // 0 = not there, 1 = fully in the Dock: drives the gap, the size and the fade
                                    property bool entered: !fresh
                                    property real presence: leaving || !entered ? 0 : 1
                                    Behavior on presence {
                                        NumberAnimation { duration: appTile.leaving ? 230 : 320; easing.type: appTile.leaving ? Easing.InOutCubic : Easing.OutCubic }
                                    }
                                    Component.onCompleted: entered = true
                                    onPresenceChanged: if (leaving && presence <= 0.002) Qt.callLater(dock.reapTile, tid)
                                    // safety net: a row that never got to animate (presence was already 0) never emitted
                                    // onPresenceChanged and stayed "leaving" forever, blocking the drag (leavingCount > 0)
                                    Timer { interval: 700; running: appTile.leaving; onTriggered: if (appTile.leaving) dock.reapTile(appTile.tid) }
                                    opacity: Math.min(1, presence * 1.6)
                                    width: (divider ? 17 : iconSize+12) * presence
                                    height: row.height
                                    z: win.dragFrom === appTile.index ? 10 : 0
                                    // neighbours slide to open a slot while another icon is being dragged
                                    readonly property real shift: {
                                        if (win.dragFrom < 0 || divider || modelData.pinned !== true || index === win.dragFrom) return 0;
                                        if (win.dragFrom < win.dragTarget && index > win.dragFrom && index <= win.dragTarget) return -win.dragWidth;
                                        if (win.dragFrom > win.dragTarget && index >= win.dragTarget && index < win.dragFrom) return win.dragWidth;
                                        return 0;
                                    }
                                    transform: Translate {
                                        x: win.dragFrom === appTile.index ? win.dragDx : appTile.shift
                                        Behavior on x { enabled: win.shiftAnim && win.dragFrom !== appTile.index; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                                    }
                                    Behavior on iconSize { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    Rectangle { visible: appTile.divider; width: 1; height: win.baseIcon*.7; color: "#40ffffff"; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 9 }
                                    // bounce and grow/shrink (from the bottom centre of the slot) act on this wrapper, and the blur is drawn inside it
                                    Item {
                                        id: motionWrap
                                        anchors.fill: parent
                                        transform: [
                                            Translate { y: -appTile.bounce },
                                            Scale { origin.x: appTile.width/2; origin.y: appTile.height - 12; xScale: appTile.presence; yScale: appTile.presence }
                                        ]
                                        Item {
                                            id: tileArt
                                            anchors.fill: parent
                                    Image {
                                        id: trashImg
                                        visible: appTile.modelData.trash === true
                                        source: Qt.resolvedUrl("icons/" + (dock.trashFull ? "trash-full.svg" : "trash-empty.svg"))
                                        sourceSize: Qt.size(256, 256); smooth: true; mipmap: true
                                        width: appTile.iconSize; height: appTile.iconSize
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                                        scale: tileMouse.pressed ? .93 : 1
                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                    }
                                    AppIcon {
                                        visible: !appTile.divider && appTile.modelData.trash !== true
                                        size: appTile.iconSize; appleStyle: true
                                        tinted: dock.tintMode !== "off"; tintColor: dock.tintColorResolved
                                        minimized: !!(appTile.modelData.windows && appTile.modelData.windows.length > 0 && appTile.modelData.windows.every(w => w.workspace && w.workspace.name === "special:minimized"))
                                        app: appTile.modelData.name || ""; entry: appTile.modelData.id || ""; icon: appTile.modelData.icon || ""
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                                        scale: win.dragFrom === appTile.index ? 1.06 : tileMouse.pressed ? .93 : 1
                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                    }
                                        }
                                        MotionBlur {
                                            id: tileBlur
                                            target: tileArt
                                            enabled: !appTile.divider && MotionBlurSettings.on("dock")
                                            anchorX: 0.5; anchorY: 1 - 12 / Math.max(1, appTile.height)
                                            pad: 44; maxBlur: 64
                                            boost: 2.2; zoomWeight: 0.9
                                            // icons near the pointer smear along it while it sweeps across the Dock
                                            extraX: win.hoverPosition >= 0 ? win.hoverPosition * (win.baseIcon + 12) : win.lastHoverX
                                            extraWeight: Math.exp(-appTile.distance * appTile.distance / 2.2)
                                        }
                                    }
                                    Connections { target: appTile; function onXChanged() { tileBlur.poke(0); } function onBounceChanged() { tileBlur.poke(0); } function onPresenceChanged() { tileBlur.poke(0); } function onShiftChanged() { tileBlur.poke(0); } }
                                    Connections { target: win; function onRevealedChanged() { tileBlur.poke(560); } function onDragDxChanged() { if (win.dragFrom === appTile.index) tileBlur.poke(0); } }
                                    Rectangle {
                                        visible: !appTile.divider && dock.cfg.indicators !== false && appTile.modelData.windows && appTile.modelData.windows.length > 0
                                        width: 4; height: 4; radius: 2; color: "#e8ffffff"
                                        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                                    }
                                    MouseArea {
                                        id: tileMouse
                                        anchors.fill: parent; enabled: !appTile.divider && !appTile.leaving
                                        hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: Qt.PointingHandCursor
                                        property real pressX: 0
                                        property bool dragged: false
                                        onPressed: mouse => { pressX = mouse.x; dragged = false; }
                                        onReleased: if (dragged) win.releaseDrag()
                                        onCanceled: if (dragged) { dragged = false; win.dragFrom = -1; win.dragTarget = -1; win.dragDx = 0; }
                                        onEntered: {
                                            if (win.dragFrom >= 0) return;
                                            win.hoverPosition = appTile.index+.5; win.revealed = true; hideDelay.stop();
                                            win.hoverTile = appTile; win.labelTile = appTile; win.labelName = appTile.modelData.name || "";
                                        }
                                        onExited: if (win.hoverTile === appTile) win.hoverTile = null
                                        onPositionChanged: mouse => {
                                            if (pressed && (mouse.buttons & Qt.LeftButton) && appTile.modelData.pinned === true && !win.menuOpen && dock.leavingCount === 0 && !appTile.leaving) {
                                                const pt = tileMouse.mapToItem(row, mouse.x, mouse.y);
                                                if (!dragged && Math.abs(mouse.x - pressX) > 8) {
                                                    dragged = true;
                                                    win.dragFrom = appTile.index; win.dragTarget = appTile.index; win.dragWidth = appTile.width;
                                                    win.hoverPosition = -10; win.hoverTile = null; win.menuApp = null;
                                                }
                                                if (dragged) { win.dragDx = pt.x - (appTile.x + appTile.width/2); win.dragTarget = win.targetFor(pt.x); return; }
                                            }
                                            if (win.dragFrom < 0) win.hoverPosition = appTile.index + Math.max(0,Math.min(1,mouse.x/width));
                                        }
                                        onClicked: mouse => {
                                            if (dragged) return;
                                            if (mouse.button === Qt.RightButton) { dock.trashConfirm = false; if (appTile.modelData.trash === true) dock.refreshTrash(); win.menuAnchor = appTile; win.menuApp = win.menuApp && win.menuApp.id === appTile.modelData.id ? null : appTile.modelData; return; }
                                            win.menuApp = null;
                                            if (appTile.modelData.trash === true) { launchBounce.restart(); dock.openTrash(); return; }
                                            if (!appTile.modelData.windows.length || mouse.modifiers & Qt.ShiftModifier) launchBounce.restart();
                                            dock.activate(appTile.modelData, !!(mouse.modifiers & Qt.ShiftModifier));
                                        }
                                    }
                                    // A file dragged in from another app: the icons magnify under it like under the pointer,
                                    // and dropping it on the Trash moves it there.
                                    DropArea {
                                        anchors.fill: parent
                                        enabled: !appTile.divider && !appTile.leaving
                                        keys: ["text/uri-list"]
                                        onEntered: drag => {
                                            win.fileDrag = true; win.revealed = true; hideDelay.stop();
                                            win.hoverPosition = appTile.index + .5; win.hoverTile = appTile; win.labelTile = appTile; win.labelName = appTile.modelData.name || "";
                                            drag.accepted = appTile.modelData.trash === true && drag.hasUrls;
                                        }
                                        onPositionChanged: drag => { win.hoverPosition = appTile.index + Math.max(0, Math.min(1, drag.x / width)); }
                                        onExited: { win.fileDrag = false; if (win.hoverTile === appTile) win.hoverTile = null; win.hoverPosition = -10; hideDelay.restart(); }
                                        onDropped: drop => {
                                            win.fileDrag = false; win.hoverPosition = -10; win.hoverTile = null; hideDelay.restart();
                                            if (appTile.modelData.trash !== true || !drop.hasUrls) return;
                                            drop.acceptProposedAction();
                                            launchBounce.restart();
                                            dock.trashUrls(drop.urls);
                                        }
                                    }
                                    SequentialAnimation {
                                        id: launchBounce
                                        NumberAnimation { target: appTile; property: "bounce"; to: 16; duration: 170; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: appTile; property: "bounce"; to: 0; duration: 240; easing.type: Easing.OutQuad }
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        id: nameTag
                        readonly property var tile: win.labelTile
                        // same geometry the per-icon tag had: 10 px above the icon, centred on it
                        readonly property real iconTop: tile ? interaction.y + row.y + row.height - 12 - tile.iconSize : interaction.y
                        opacity: win.labelOn ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        width: nameText.implicitWidth + 22; height: 29; radius: 9
                        // glide only while the tag is already on screen; the first appearance does not slide in from the previous spot
                        Behavior on width { enabled: nameTag.opacity > 0.6; SmoothedAnimation { velocity: 1200; maximumEasingTime: 110 } }
                        x: Math.max(8, Math.min(win.w - width - 8, tile ? interaction.x + row.x + tile.x + tile.width/2 - width/2 : (win.w - width)/2))
                        y: iconTop - height - 10
                        // follows a target that moves every frame (icons magnify); SmoothedAnimation keeps
                        // its velocity when retargeted, a NumberAnimation would restart and look stuck.
                        // SmoothedAnimation's default velocity is only 200 px/s, so it is set explicitly (tag lagged far behind)
                        Behavior on x { enabled: nameTag.opacity > 0.6; SmoothedAnimation { velocity: 2200; maximumEasingTime: 120 } }
                        Behavior on y { enabled: nameTag.opacity > 0.6; SmoothedAnimation { velocity: 900; maximumEasingTime: 100 } }
                        color: "#e6434348"; border.width: 1; border.color: "#35ffffff"
                        transform: Translate { y: win.labelOn ? 0 : 4; Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } }
                        Text { id: nameText; anchors.centerIn: parent; text: win.labelName; color: "#f5f5f7"; font.family: "Rubik"; font.pixelSize: 12 }
                    }
                    Rectangle {
                        id: contextMenu
                        opacity: win.menuOpen ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        readonly property real iconCenter: win.menuAnchor ? interaction.x + row.x + win.menuAnchor.x + win.menuAnchor.width/2 : win.w/2
                        readonly property real iconTop: win.menuAnchor ? interaction.y + row.y + row.height - 12 - win.menuAnchor.iconSize : interaction.y
                        x: Math.max(12, Math.min(win.w-width-12, iconCenter-width/2))
                        y: Math.max(8, iconTop-height-10)
                        Behavior on x { enabled: win.menuOpen; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on y { enabled: win.menuOpen; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        width: 215; height: menuColumn.height+16; radius: 15
                        color: win.glass ? "#38202025" : "#f02a2a2f"
                        border.width: 1; border.color: "#60ffffff"
                        ShaderEffect {
                            anchors.fill: parent
                            visible: win.glass && backScene.ready
                            property var src: backdrop
                            property real radius: contextMenu.radius
                            property real strength: 0.6
                            property real band: 13
                            property vector2d stretch: Qt.vector2d(1, 1)
                            property vector2d size: Qt.vector2d(width, height)
                            property vector2d screen: Qt.vector2d(win.screen ? win.screen.width : 1, win.screen ? win.screen.height : 1)
                            property vector2d origin: Qt.vector2d(contextMenu.x, (win.screen ? win.screen.height : win.h)-win.h+contextMenu.y)
                            fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
                        }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius
                            visible: win.glass
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#32ffffff" }
                                GradientStop { position: 0.5; color: "#05ffffff" }
                                GradientStop { position: 1; color: "#1bffffff" }
                            }
                        }
                        HoverHandler { id: menuHover; onHoveredChanged: if (hovered) hideDelay.stop(); else hideDelay.restart() }
                        Column {
                            id: menuColumn; x: 8; y: 8; width: parent.width-16; spacing: 3
                            Text { width: parent.width; height: 27; text: win.menuApp ? win.menuApp.name : ""; elide: Text.ElideRight; color: "#98989d"; font.family: "Rubik"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                            Repeater {
                                model: win.menuApp && win.menuApp.trash === true ? ["Open", dock.trashConfirm ? "Click again to empty" : "Empty Trash"] : [win.menuApp && win.menuApp.pinned ? "Remove from Dock" : "Keep in Dock", "Open New", "Close Windows"]
                                delegate: Rectangle {
                                    id: menuAction
                                    required property string modelData
                                    required property int index
                                    width: menuColumn.width; height: 30; radius: 7
                                    readonly property bool isEmpty: win.menuApp && win.menuApp.trash === true && menuAction.index === 1
                                    readonly property bool disabled: isEmpty && !dock.trashFull
                                    color: actionMouse.containsMouse && !disabled ? (isEmpty && dock.trashConfirm ? "#ff453a" : "#0a84ff") : "transparent"
                                    Text { x: 9; anchors.verticalCenter: parent.verticalCenter; text: menuAction.modelData; color: menuAction.disabled ? "#6c6c70" : "#f5f5f7"; font.family: "Rubik"; font.pixelSize: 12 }
                                    MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; enabled: !menuAction.disabled; onClicked: win.runMenuAction(menuAction.index) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
