import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: dock
    property var settings: ({})
    readonly property var cfg: settings.macDock || ({})
    readonly property bool enabled: cfg.enabled === true
    // Liquid Glass needs the compositor blur, which `opti` turns off: it is ignored while opti is on.
    property bool optiOn: false
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/opti"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: dock.optiOn = text().trim() === "on"
        onLoadFailed: dock.optiOn = false
    }
    readonly property var monitors: !enabled ? [] : cfg.allScreens === true ? Quickshell.screens : [Quickshell.screens[0]]
    readonly property var pins: Array.isArray(cfg.apps) ? cfg.apps : ["org.gnome.Nautilus", "kitty"]
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
        return result.concat(running);
    }
    // The icons live in a stable list (not the `apps` array, which rebuilds every delegate on each change),
    // so an app that appears slides open a gap and grows in, and one that goes away shrinks and closes it.
    // Rows of apps that went away stay (leaving) until their delegate has finished shrinking.
    ListModel { id: tileModel }
    readonly property var appsById: { const m = {}; for (const a of apps) m[a.id] = a; return m; }
    property bool tilesReady: false   // rows added after start-up animate in; the first fill does not
    property int leavingCount: 0
    Timer { interval: 1500; running: true; onTriggered: dock.tilesReady = true }
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
            const target = app.windows[(current+1) % app.windows.length];
            if (target.workspace) Hyprland.dispatch('hl.dsp.focus({ workspace = '+target.workspace.id+' })');
            Hyprland.dispatch('hl.dsp.focus({ window = "address:'+address(target.address)+'" })');
        } else if (app.entry) app.entry.execute();
    }
    function closeApp(app) {
        if (!app) return;
        for (const window of app.windows) Hyprland.dispatch('hl.dsp.window.close({ window = "address:'+address(window.address)+'" })');
    }
    Process {
        id: pinWriter
        command: []
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
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded" && !blurSetup.running) blurSetup.running = true; }
    }
    Variants {
        model: dock.monitors
        delegate: PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors.bottom: true; anchors.left: true; anchors.right: true
            implicitHeight: Math.ceil(baseIcon*1.7 + 240)
            color: "transparent"
            exclusionMode: dock.cfg.reserveSpace === true && !configuredAutoHide ? ExclusionMode.Normal : ExclusionMode.Ignore
            exclusiveZone: dock.cfg.reserveSpace === true && !configuredAutoHide ? baseIcon+34 : 0
            WlrLayershell.namespace: "astrax-macos-dock"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            readonly property bool configuredAutoHide: dock.cfg.autoHide === true
            readonly property bool desktopEmpty: {
                const monitor = Hyprland.monitors.values.find(m => win.screen && m.name === win.screen.name);
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
            readonly property bool autoHide: configuredAutoHide && !(dock.cfg.showInDesktop === true && desktopEmpty)
            property bool revealed: true
            property real hoverPosition: -10
            property var menuAnchor: null
            property var menuApp: null
            readonly property bool menuOpen: menuApp !== null
            // The menu model is rebuilt when menuApp changes. Run actions in
            // the stable window scope, rather than a delegate being destroyed.
            function runMenuAction(action) {
                const app = menuApp;
                menuApp = null;
                if (action === 0) dock.togglePin(app);
                else if (action === 1) dock.activate(app, true);
                else dock.closeApp(app);
                hideDelay.restart();
            }
            readonly property bool showing: !autoHide || revealed || menuOpen
            readonly property bool glass: dock.cfg.glass !== false && !dock.optiOn
            readonly property real magnification: dock.cfg.magnification === false ? 0 : Math.max(0, Math.min(0.9,(dock.cfg.zoom || 155)/100-1))
            readonly property int count: dock.apps.filter(a => !a.separator).length
            readonly property real baseIcon: Math.max(24, Math.min(Number(dock.cfg.iconSize || 48), (width-80)/Math.max(1,count*(1+magnification*.35))-12))
            readonly property real maxIcon: baseIcon*(1+magnification)
            readonly property int margin: 12
            onAutoHideChanged: { revealed = true; if (autoHide) hideDelay.restart(); }
            Component.onCompleted: if (autoHide) hideDelay.restart()
            Timer {
                id: hideDelay
                interval: Math.max(150,Number(dock.cfg.hideDelay || 650))
                onTriggered: if (!dockHover.hovered && !menuHover.hovered) { win.revealed = false; win.menuApp = null; win.hoverPosition = -10; }
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
            ScreencopyView {
                id: capture
                width: win.screen ? win.screen.width : 1; height: win.screen ? win.screen.height : 1
                captureSource: win.glass && win.showing && win.visible ? win.screen : null
                live: win.glass && win.showing && win.visible
            }
            ShaderEffectSource { id: backdrop; sourceItem: capture; hideSource: true; visible: false; live: win.glass && win.showing && win.visible }
            Item {
                id: revealZone
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(win.width-32, Math.max(180,frame.width)); height: 4
                MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton; onEntered: { win.revealed = true; hideDelay.stop(); } }
            }
            Item {
                id: interaction
                x: (win.width-width)/2; y: win.height-height-win.margin
                width: Math.min(win.width-24, row.width+24); height: win.maxIcon+28
                opacity: win.showing ? 1 : 0
                transform: Translate { y: win.showing ? 0 : interaction.height+win.margin+4; Behavior on y { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } } }
                Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                HoverHandler {
                    id: dockHover
                    onHoveredChanged: {
                        if (hovered) { win.revealed = true; hideDelay.stop(); }
                        else { win.hoverPosition = -10; hideDelay.restart(); }
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
                        visible: win.glass && capture.hasContent
                        property var src: backdrop
                        property real radius: frame.radius
                        property real strength: 0.6
                        property real band: 13
                        property vector2d stretch: Qt.vector2d(1,1)
                        property vector2d size: Qt.vector2d(width,height)
                        property vector2d screen: Qt.vector2d(win.screen ? win.screen.width : 1,win.screen ? win.screen.height : 1)
                        property vector2d origin: Qt.vector2d(interaction.x + frame.x,
                            (win.screen ? win.screen.height : win.height)-win.height+interaction.y+frame.y)
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
                            opacity: Math.min(1, presence * 1.6)
                            width: (divider ? 17 : iconSize+12) * presence
                            height: row.height
                            Behavior on iconSize { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Rectangle { visible: appTile.divider; width: 1; height: win.baseIcon*.7; color: "#40ffffff"; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 9 }
                            AppIcon {
                                visible: !appTile.divider
                                size: appTile.iconSize; appleStyle: true
                                app: appTile.modelData.name || ""; entry: appTile.modelData.id || ""; icon: appTile.modelData.icon || ""
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                                transform: [
                                    Translate { y: -appTile.bounce },
                                    // grows from (and shrinks to) the bottom centre of its slot
                                    Scale { origin.x: appTile.iconSize/2; origin.y: appTile.iconSize; xScale: appTile.presence; yScale: appTile.presence }
                                ]
                                scale: tileMouse.pressed ? .93 : 1
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            }
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
                                onEntered: { win.hoverPosition = appTile.index+.5; win.revealed = true; hideDelay.stop(); }
                                onPositionChanged: mouse => { win.hoverPosition = appTile.index + Math.max(0,Math.min(1,mouse.x/width)); }
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) { win.menuAnchor = appTile; win.menuApp = win.menuApp && win.menuApp.id === appTile.modelData.id ? null : appTile.modelData; return; }
                                    win.menuApp = null;
                                    if (!appTile.modelData.windows.length || mouse.modifiers & Qt.ShiftModifier) launchBounce.restart();
                                    dock.activate(appTile.modelData, !!(mouse.modifiers & Qt.ShiftModifier));
                                }
                            }
                            SequentialAnimation {
                                id: launchBounce
                                NumberAnimation { target: appTile; property: "bounce"; to: 16; duration: 170; easing.type: Easing.OutCubic }
                                NumberAnimation { target: appTile; property: "bounce"; to: 0; duration: 240; easing.type: Easing.OutQuad }
                            }
                            Rectangle {
                                visible: !appTile.divider && tileMouse.containsMouse && !win.menuOpen
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom; anchors.bottomMargin: appTile.iconSize+22
                                width: label.implicitWidth+22; height: 29; radius: 9
                                color: "#e6434348"; border.width: 1; border.color: "#35ffffff"
                                Text { id: label; anchors.centerIn: parent; text: appTile.modelData.name || ""; color: "#f5f5f7"; font.family: "Rubik"; font.pixelSize: 12 }
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: contextMenu
                opacity: win.menuOpen ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                readonly property real iconCenter: win.menuAnchor ? interaction.x + row.x + win.menuAnchor.x + win.menuAnchor.width/2 : win.width/2
                readonly property real iconTop: win.menuAnchor ? interaction.y + row.y + row.height - 12 - win.menuAnchor.iconSize : interaction.y
                x: Math.max(12, Math.min(win.width-width-12, iconCenter-width/2))
                y: Math.max(8, iconTop-height-10)
                Behavior on x { enabled: win.menuOpen; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: win.menuOpen; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                width: 215; height: menuColumn.height+16; radius: 15
                color: win.glass ? "#38202025" : "#f02a2a2f"
                border.width: 1; border.color: "#60ffffff"
                ShaderEffect {
                    anchors.fill: parent
                    visible: win.glass && capture.hasContent
                    property var src: backdrop
                    property real radius: contextMenu.radius
                    property real strength: 0.6
                    property real band: 13
                    property vector2d stretch: Qt.vector2d(1, 1)
                    property vector2d size: Qt.vector2d(width, height)
                    property vector2d screen: Qt.vector2d(win.screen ? win.screen.width : 1, win.screen ? win.screen.height : 1)
                    property vector2d origin: Qt.vector2d(contextMenu.x, (win.screen ? win.screen.height : win.height)-win.height+contextMenu.y)
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
                        model: [win.menuApp && win.menuApp.pinned ? "Remove from Dock" : "Keep in Dock", "Open New", "Close Windows"]
                        delegate: Rectangle {
                            id: menuAction
                            required property string modelData
                            required property int index
                            width: menuColumn.width; height: 30; radius: 7
                            color: actionMouse.containsMouse ? "#0a84ff" : "transparent"
                            Text { x: 9; anchors.verticalCenter: parent.verticalCenter; text: menuAction.modelData; color: "#f5f5f7"; font.family: "Rubik"; font.pixelSize: 12 }
                            MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; onClicked: win.runMenuAction(menuAction.index) }
                        }
                    }
                }
            }
        }
    }
}
