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
    // Liquid Glass needs the compositor blur, which `opti` turns off: it is ignored while opti is on.
    property bool optiOn: false
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/opti"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.optiOn = text().trim() === "on"
        onLoadFailed: root.optiOn = false
    }
    readonly property bool glassCfg: cfg.glass === true && !optiOn
    readonly property real glassAlpha: (cfg.glassOpacity !== undefined ? cfg.glassOpacity : 55) / 100
    readonly property real refraction: (cfg.glassRefraction !== undefined ? cfg.glassRefraction : 60) / 100
    readonly property real bounce: (cfg.bounce !== undefined ? cfg.bounce : 60) / 100
    readonly property int edgeMargin: cfg.topMargin !== undefined ? cfg.topMargin : 4
    // position picked in Super+C (percent of the free space, like the notification picker)
    readonly property real posX: (cfg.posX !== undefined ? cfg.posX : 50) / 100
    readonly property real posY: (cfg.posY !== undefined ? cfg.posY : 0) / 100
    // Show one island on the focused monitor, or one instance per connected screen.
    readonly property var targetScreens: {
        if (root.cfg.showOnAllScreens === true) return Quickshell.screens;
        const s0 = Quickshell.screens[0];
        const fm = Hyprland.focusedMonitor;
        const focused = fm ? Quickshell.screens.find(x => x.name === fm.name) : null;
        return [focused || s0];
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/serpantinum/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.cfg = (j && j.island) ? j.island : ({});
                if (root.cfg.enabled === false) { root.switcherOpen = false; root.appLauncherOpen = false; }
            } catch (e) { root.cfg = ({}); }
        }
    }

    ScreenTimeStore {
        id: screenTime
        enabled: root.cfg.enabled !== false && root.cfg.trackScreenTime !== false
    }

    // ------------------------------------------------------------- palette
    readonly property color fg: "#f5f5f7"
    readonly property color dim: Qt.rgba(1, 1, 1, 0.58)
    readonly property string textFont: "Rubik"
    readonly property string iconFont: "Iosevka Nerd Font"

    // -------------------------------------------------------------- events
    property var current: null
    property var queue: []
    ListModel { id: activeNotifications }
    property var notificationEvents: ({})
    property int notificationToken: 0
    property bool notificationBatchSealed: false

    function notificationIndex(ev) {
        for (let i = 0; i < activeNotifications.count; i++) {
            const item = root.notificationEvents[activeNotifications.get(i).token];
            if (item === ev || (ev && ev.uid !== undefined && item && item.uid === ev.uid)) return i;
        }
        return -1;
    }
    function clearNotificationBatch() {
        activeNotifications.clear();
        root.notificationEvents = ({});
        root.notificationBatchSealed = false;
    }
    function addNotification(ev) {
        const existing = root.notificationIndex(ev);
        const token = existing >= 0 ? activeNotifications.get(existing).token : ++root.notificationToken;
        const events = Object.assign({}, root.notificationEvents);
        events[token] = ev;
        root.notificationEvents = events;
        if (existing < 0) activeNotifications.insert(0, { token: token });
        else if (existing > 0) activeNotifications.move(existing, 0, 1);
        if (activeNotifications.count >= 3) root.notificationBatchSealed = true;
        root.current = ev;
        hold.interval = Math.max(...Object.values(root.notificationEvents).map(n => n.duration || 2500));
        hold.restart();
    }
    function removeNotification(ev) {
        const i = root.notificationIndex(ev);
        if (i < 0) return;
        const token = activeNotifications.get(i).token;
        activeNotifications.remove(i);
        const events = Object.assign({}, root.notificationEvents);
        delete events[token];
        root.notificationEvents = events;
        if (activeNotifications.count === 0) root.next();
        else root.current = events[activeNotifications.get(0).token];
    }
    function dismissNotification(ev) {
        if (!ev) return;
        root.cancelLeftClicks();
        if (ev.uid !== undefined) root.srpCall("dismiss", [ev.uid]);
        root.removeNotification(ev);
    }
    function activateNotification(ev) {
        if (!ev) return;
        if (ev.uid !== undefined) root.srpCall("activate", [ev.uid]);
        root.removeNotification(ev);
    }
    property bool listOpen: false       // notification list (triple-click)
    property var listItems: []          // notifications, from Serpantinum
    property var activity: []           // files / clipboard / device events seen by the island
    property int activityId: 0
    // one list for everything, newest first
    readonly property var allItems: {
        const ev = root.activity
            .filter(a => !/^brain\.sqlite3(?:-(?:wal|shm|journal))?$/i.test(a.summary || ""))
            .map(a => Object.assign({ kind: "event" }, a));
        return root.listItems.concat(ev).sort((a, b) => b.ts - a.ts).slice(0, 30);
    }
    readonly property var stateColors: ({ progress: "#0a84ff", done: "#30d158", canceled: "#ff453a", added: "#30d158",
                                          modified: "#ff9f0a", deleted: "#ff453a", renamed: "#0a84ff", batch: "#0a84ff",
                                          copied: "#0a84ff", cut: "#ff9f0a", pasted: "#30d158", alarm: "#ff9f0a" })
    // what the list remembers: file, clipboard and device events (volume/brightness HUDs and live progress are too noisy)
    function record(ev) {
        if (ev.kind === "alarm") return; // Its original notification is already in history.
        if (ev.layout === "hud" || ev.layout === "notif" || ev.state === "progress") return;
        if (ev.layout !== "file" && ev.layout !== "status") return;
        const a = root.activity.slice();
        a.unshift({ id: ++root.activityId, ts: Date.now(), summary: ev.name || ev.title || "", body: ev.sub || ev.detail || "",
                    glyph: ev.glyph || "", thumb: ev.thumb || "", openPath: ev.openPath || ev.path || "",
                    accent: ev.layout === "status" ? (ev.accent || "#ffffff") : (root.stateColors[ev.state] || "#ffffff") });
        root.activity = a.slice(0, 40);
    }
    property int leftClickCount: 0
    property string leftClickAction: ""
    property var leftClickEvent: null
    property int rightClickCount: 0
    property real lastRightPress: 0
    property bool skipRightRelease: false
    property bool appLauncherOpen: false
    property bool switcherOpen: false
    property string switcherMonitor: ""
    property bool shelfOpen: false
    property bool shelfPreview: false
    property bool shelfDragging: false
    property bool overviewOpen: false
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
        if (root.appLauncherOpen || root.switcherOpen || root.listOpen || root.overviewOpen || root.shelfOpen || root.shelfPreview) {
            // the list is open: events wait their turn and show when it closes
            const q = root.queue.slice();
            if (ev.replaceKey) { const i = q.findIndex(x => x.replaceKey === ev.replaceKey); if (i >= 0) q.splice(i, 1); }
            q.push(ev);
            root.queue = q;
            return;
        }
        if (ev.layout === "notif" && root.current && root.current.layout === "notif") {
            // A sealed batch never backfills: queued alerts wait for every row to leave.
            if (!root.notificationBatchSealed || root.notificationIndex(ev) >= 0) root.addNotification(ev);
            else root.queue = root.queue.concat([ev]);
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
            if (root.current && root.current.layout === "notif") {
                const batch = [];
                for (let i = activeNotifications.count - 1; i >= 0; i--)
                    batch.push(root.notificationEvents[activeNotifications.get(i).token]);
                root.queue = batch.concat(root.queue);
            }
            root.show(ev);
            return;
        }
        if (root.current) {
            const q = root.queue.slice();
            q.push(ev);
            root.queue = q;
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
        if (ev.layout === "notif") { root.activateNotification(ev); return; }
        if (ev.kind === "alarm") {
            if (ev.uid !== undefined) root.srpCall("activate", [ev.uid]);
            root.next();
            return;
        }
        if (ev.kind === "track") root.expanded = true;
        else if (ev.layout === "file") root.openPath(ev.openPath || ev.path, ev.openDir === true);
        else if (ev.uid !== undefined) root.srpCall("activate", [ev.uid]);
        root.next();
    }
    function dismissCurrent() {
        const ev = root.current;
        if (ev && ev.layout === "notif") { root.dismissNotification(ev); return; }
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
        root.appLauncherOpen = false;
        root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        root.overviewOpen = false;
        root.listOpen = true;
        root.notifOpen = false;
        hold.stop();
        listProc.running = false;
        listProc.running = true;
    }
    function closeList() {
        root.listOpen = false;
        if (root.queue.length) root.next();
        else { root.current = null; root.clearNotificationBatch(); }
    }
    function toggleList() { if (root.listOpen) root.closeList(); else root.openList(); }
    function cancelLeftClicks() {
        leftClickWait.stop();
        root.leftClickCount = 0;
        root.leftClickAction = "";
        root.leftClickEvent = null;
    }
    function registerLeftClick(notification) {
        if (root.leftClickCount === 0) {
            // Closing a manual panel is immediate, but remains the first press
            // of a possible triple-click sequence. Never schedule a reopen.
            if (root.largeView && root.mode !== "notif") {
                root.compactOutside();
            } else {
                root.leftClickEvent = notification || root.current;
                root.leftClickAction = "";
                if (root.mode === "notif" || root.mode === "file") root.leftClickAction = "activate";
                else if (!root.current && root.hasMusic) root.leftClickAction = "music";
            }
        }
        root.leftClickCount++;
        if (root.leftClickCount >= 3) {
            root.cancelLeftClicks();
            root.toggleList();
            return;
        }
        leftClickWait.restart();
    }
    Timer {
        id: leftClickWait
        interval: 500
        onTriggered: {
            const count = root.leftClickCount;
            const action = root.leftClickAction;
            const event = root.leftClickEvent;
            root.cancelLeftClicks();
            // Opening waits for 500 ms without another press; closing was immediate.
            if (count !== 1 || root.listOpen || root.overviewOpen || root.shelfOpen || root.shelfPreview) return;
            if (action === "activate" && event && (root.current === event || root.notificationIndex(event) >= 0)) {
                if (event.layout === "notif") root.activateNotification(event);
                else root.activateCurrent();
            }
            else if (action === "music" && !root.current && root.hasMusic) root.expanded = true;
        }
    }

    // Collapse a surface without dismissing notifications in history.
    function compactOutside() {
        root.appLauncherOpen = false;
        root.switcherOpen = false;
        rightClick.stop();
        root.shelfOpen = false; root.shelfPreview = false;
        root.overviewOpen = false;
        root.listOpen = false;
        root.expanded = false;
        root.notifOpen = false;
        root.cancelLeftClicks();
        root.current = null;
        root.clearNotificationBatch();
        hold.stop();
    }
    Timer {
        id: rightClick
        interval: Application.styleHints.mouseDoubleClickInterval + 50
        onTriggered: {
            if (root.rightClickCount === 2) {
                if (root.overviewOpen) root.compactOutside();
                else root.openOverview();
            }
            root.rightClickCount = 0;
        }
    }
    function openShelf() {
        root.appLauncherOpen = false;
        root.switcherOpen = false;
        root.overviewOpen = false; root.listOpen = false;
        root.shelfOpen = true; root.shelfPreview = false;
        root.expanded = false; root.notifOpen = false;
        hold.stop();
    }
    function openOverview() {
        root.appLauncherOpen = false;
        root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        // The double-right-click gesture toggles this overview.
        root.listOpen = false;
        root.overviewOpen = true;
        root.expanded = false;
        root.notifOpen = false;
        hold.stop();
    }
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
        root.clearNotificationBatch();
        if (ev.layout === "notif") {
            root.addNotification(ev);
            const remaining = root.queue.slice();
            while (remaining.length && remaining[0].layout === "notif" && activeNotifications.count < 3)
                root.addNotification(remaining.shift());
            root.queue = remaining;
            return;
        }
        root.current = ev;
        hold.interval = ev.duration || 2500;
        hold.restart();
    }
    function next() {
        root.notifOpen = false;
        root.clearNotificationBatch();
        if (root.queue.length) {
            const q = root.queue.slice();
            const ev = q.shift();
            root.queue = q;
            root.show(ev);
        } else root.current = null;
    }
    Timer { id: hold; onTriggered: root.next() }

    // The compositor reports clicks without consuming them; read the pointer only
    // while an expanded island exists. Input outside the island stays with the app.
    signal desktopClicked(real desktopX, real desktopY)
    Process {
        id: outsidePointer
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                if ((!root.largeView && root.leftClickCount === 0) || root.shelfDragging) return;
                try {
                    const point = JSON.parse(this.text);
                    if (typeof point.x === "number" && typeof point.y === "number"
                        && isFinite(point.x) && isFinite(point.y))
                        root.desktopClicked(point.x, point.y);
                } catch (e) {}
            }
        }
    }

    // qs -c astrax-island ipc call island toggleList   (same as clicking the island three times)
    IpcHandler {
        target: "island"
        function toggleApps(): string {
            if (root.appLauncherOpen) root.closeApps(); else root.openApps();
            return root.appLauncherOpen ? "open" : "closed";
        }
        function openApps(): void { root.openApps(); }
        function closeApps(): void { root.closeApps(); }
        function toggleSwitcher(): string {
            if (root.switcherOpen) root.closeSwitcher(); else root.openSwitcher();
            return root.switcherOpen ? "open" : "closed";
        }
        function openSwitcher(): void { root.openSwitcher(); }
        function closeSwitcher(): void { root.closeSwitcher(); }
        function toggleList(): string { root.toggleList(); return root.listOpen ? "open" : "closed"; }
        // called by the non-consuming Ctrl+V binds (config/binds-island.lua)
        function paste(): string { clipSrc.paste(); return "ok"; }
        function outsideClick(): string {
            if ((!root.largeView && root.leftClickCount === 0) || root.shelfDragging || outsidePointer.running) return "ignored";
            outsidePointer.running = true;
            return "ok";
        }
    }

    function openApps() {
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.switcherOpen = false; root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.expanded = false; root.notifOpen = false;
        root.appLauncherOpen = true; hold.stop();
    }
    function closeApps() {
        root.appLauncherOpen = false;
        if (root.cfg.enabled === false) return;
        if (root.current) { hold.interval = 1600; hold.restart(); }
        else if (root.queue.length) root.next();
    }
    function appAction(method, appId) {
        if (launcherAction.running || !appId) return;
        launcherAction.command = ["qs", "-c", "astrax-launcher", "ipc", "call", "launcher", method, appId];
        launcherAction.running = true;
        if (method === "launchId") root.closeApps();
    }
    Process { id: launcherAction }

    function openSwitcher() {
        root.appLauncherOpen = false;
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false;
        root.expanded = false; root.notifOpen = false;
        root.switcherMonitor = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : Quickshell.screens[0].name;
        root.switcherOpen = true;
        hold.stop();
    }
    function closeSwitcher() {
        root.switcherOpen = false;
        if (root.cfg.enabled === false) return;
        if (root.current) { hold.interval = 1600; hold.restart(); }
        else if (root.queue.length) root.next();
    }

    // --------------------------------------------------------------- music
    readonly property var player: {
        const list = Mpris.players.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].isPlaying) return list[i];
        return list.length ? list[0] : null;
    }
    property string musicTitle: ""
    property string musicArtist: ""
    property string musicArt: ""
    property string lookedUpArt: ""
    property string artworkRequestKey: ""
    property bool artworkHelperMissing: false
    readonly property string artworkLookupKey: player && player.dbusName.startsWith("org.mpris.MediaPlayer2.iPhone_")
        && !player.trackArtUrl && player.trackTitle && player.trackArtist
        ? JSON.stringify([player.trackTitle, player.trackArtist, player.trackAlbum || "", player.length || 0]) : ""
    onArtworkLookupKeyChanged: {
        root.lookedUpArt = "";
        if (root.player && !root.player.trackArtUrl) root.musicArt = "";
        artworkDelay.restart();
    }
    readonly property bool hasMusic: cfg.showMusic !== false && musicTitle !== ""
    readonly property string musicMetadata: player
        ? JSON.stringify([player.trackTitle || "", player.trackArtist || "", player.trackArtUrl || "", player.trackAlbum || "", player.isPlaying, player.dbusName]) : ""
    onMusicMetadataChanged: musicSettle.restart()

    function updateMusic() {
        const title = root.player ? (root.player.trackTitle || "") : "";
        if (title === "") {
            // MPRIS may briefly clear the old track before publishing the next one.
            if (root.musicTitle !== "" && !musicGrace.running) musicGrace.start();
            return;
        }
        musicGrace.stop();
        root.musicTitle = title;
        root.musicArtist = root.player.trackArtist || "";
        root.musicArt = root.player.trackArtUrl || root.lookedUpArt;
        // Update the existing music card in place instead of replacing it with
        // a timed notification that hides the expanded player on every skip.
    }
    Timer { id: musicSettle; interval: 120; onTriggered: root.updateMusic() }
    Timer {
        id: artworkDelay
        interval: 800
        onTriggered: {
            if (!root.artworkLookupKey || artworkLookup.running) return;
            root.artworkRequestKey = root.artworkLookupKey;
            // Optional helper of the iPhone/Bluetooth pack (`astrax-iphone install`); exit 99 = not installed.
            if (root.artworkHelperMissing) return;
            artworkLookup.command = ["sh", "-c", "[ -f \"$1\" ] || exit 99; exec /usr/bin/python3 \"$1\" \"$2\"",
                                     "sh", Quickshell.env("HOME") + "/.local/lib/iphone-notifications/phone-artwork.py", root.artworkRequestKey];
            artworkLookup.running = true;
        }
    }
    Process {
        id: artworkLookup
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(this.text);
                    // Ignore a slow answer if the user has already changed tracks.
                    if (result.key === root.artworkLookupKey) {
                        root.lookedUpArt = result.url || "";
                        root.updateMusic();
                    }
                } catch (e) {}
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 99) { root.artworkHelperMissing = true; return; }
            if (root.artworkLookupKey && root.artworkLookupKey !== root.artworkRequestKey)
                artworkDelay.restart();
        }
    }
    Timer {
        id: musicGrace
        interval: 2000
        onTriggered: {
            if (!root.player || (root.player.trackTitle || "") === "") {
                root.musicTitle = ""; root.musicArtist = ""; root.musicArt = "";
            }
        }
    }

    // ---------------------------------------------------------------- mode
    readonly property string mode: appLauncherOpen ? "apps" : switcherOpen ? "switcher" : (shelfOpen || shelfPreview) ? "shelf" : overviewOpen ? "overview" : listOpen ? "list" : current ? current.layout
        : (expanded && hasMusic) ? "musicExpanded" : hasMusic ? "music" : "idle"
    readonly property bool largeView: mode === "apps" || mode === "switcher" || mode === "list" || mode === "notif" || mode === "musicExpanded" || mode === "overview" || mode === "shelf"

    function iconSource(icon) {
        if (!icon) return "";
        // Quickshell hands image-path hints over as image://icon/<path or name>
        if (icon.startsWith("image://icon/")) return root.iconSource(icon.substring(13));
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.indexOf("://") > 0) return icon.startsWith("image://") ? "" : icon;
        return Quickshell.iconPath(icon, true) || "";
    }

    Variants {
        model: root.targetScreens
        delegate: Component {
            PanelWindow {
                id: win
                required property var modelData
                screen: win.modelData

                readonly property bool isFocusedMonitor: {
                    const focused = Hyprland.focusedMonitor;
                    const currentScreen = win.screen;
                    if (focused && currentScreen) return currentScreen.name === focused.name;
                    return currentScreen === Quickshell.screens[0];
                }
                readonly property string viewMode: {
                    if (root.cfg.showOnAllScreens === true && !win.isFocusedMonitor)
                        return root.current ? root.current.layout : (root.hasMusic ? "music" : "idle");
                    return root.mode;
                }
                // Panels accept input only over the island; the rest reaches the desktop.
                readonly property var inputTarget: win.isFocusedMonitor ? pill : emptyInputRegion

        WlrLayershell.namespace: "astrax-island"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: (win.viewMode === "switcher" || win.viewMode === "apps") && win.isFocusedMonitor ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // the whole screen is the canvas; only the pill takes input (mask)
        anchors { top: true; bottom: true; left: true; right: true }
        visible: root.cfg.enabled !== false && !(root.cfg.hideWhenIdle === true && win.viewMode === "idle")
        mask: Region { item: win.inputTarget }

        // Zero-sized input shape makes non-focused screen copies visual-only.
        Item { id: emptyInputRegion; width: 0; height: 0; visible: false }

        Connections {
            target: root
            function onDesktopClicked(desktopX, desktopY) {
                if (!win.visible || !win.isFocusedMonitor || !win.screen
                    || (!root.largeView && root.leftClickCount === 0) || root.shelfDragging) return;
                // Hyprland and ShellScreen share desktop logical coordinates.
                // Invert the island's live hover/press transform before hit testing.
                const halfW = pill.width / 2;
                const halfH = pill.height / 2;
                const x = (desktopX - win.screen.x - pill.x - halfW) / pill.bx + halfW;
                const y = (desktopY - win.screen.y - pill.y - halfH) / pill.by + halfH;
                const radius = Math.min(pill.radius, halfW, halfH);
                const qx = Math.abs(x - halfW) - (halfW - radius);
                const qy = Math.abs(y - halfH) - (halfH - radius);
                const dx = Math.max(qx, 0);
                const dy = Math.max(qy, 0);
                const distance = Math.sqrt(dx * dx + dy * dy)
                    + Math.min(Math.max(qx, qy), 0) - radius;
                if (distance > 0) {
                    if (root.largeView) root.compactOutside();
                    else root.cancelLeftClicks();
                }
            }
        }

        // Keep the captured texture aligned with the monitor's (0, 0) origin.
        ScreencopyView {
            id: snap
            captureSource: win.visible && pill.glassOn && root.refraction > 0 ? win.screen : null
            live: win.visible && pill.glassOn && root.refraction > 0
            visible: true
            width: win.width; height: win.height
        }
        ShaderEffectSource {
            id: backdropTexture
            sourceItem: snap
            hideSource: true
            live: win.visible && pill.glassOn && root.refraction > 0
            visible: false
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
            x: (win.viewMode === "switcher" || win.viewMode === "apps") ? Math.max(root.edgeMargin, Math.min(cx - width / 2, parent.width - width - root.edgeMargin)) : cx - width / 2
            y: topY

            readonly property bool glassOn: root.glassCfg && (win.viewMode === "notif" || win.viewMode === "musicExpanded" || win.viewMode === "overview" || win.viewMode === "shelf" || win.viewMode === "switcher" || win.viewMode === "apps")
            readonly property real listH: 62 + Math.min(5, Math.max(1, root.allItems.length)) * 54 + 6
            readonly property real notifH: Math.max(68, notificationStack.implicitHeight)

            // compact states keep the pill's height and only get wider (like the
            // real island); notifications and the music card grow downwards
            readonly property real targetW: ({ idle: 126, music: 250, hud: 300, status: 320, notif: 410, file: 340, musicExpanded: 430, list: 540, overview: 540, shelf: 540, apps: Math.min(win.width - 2 * root.edgeMargin, Math.max(300, 48 + (appsLoader.item ? appsLoader.item.columns : 5) * 88)), switcher: Math.min(win.width - 2 * root.edgeMargin, Math.max(300, 48 + (switcherLoader.item ? switcherLoader.item.columns : 4) * 220)) })[win.viewMode]
            readonly property real targetH: ({ idle: 34, music: 34, hud: 34, status: 34, notif: notifH, file: 46, musicExpanded: 136, list: listH, overview: 360, shelf: shelf.preferredHeight, apps: (appsLoader.item ? appsLoader.item.preferredHeight : 396), switcher: (switcherLoader.item ? switcherLoader.item.preferredHeight : 266) })[win.viewMode]
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

            ShaderEffect {
                id: lens
                anchors.fill: parent
                visible: pill.glassOn && snap.hasContent && root.refraction > 0
                property var src: backdropTexture
                property real radius: pill.radius
                property real strength: root.refraction
                property real band: Math.min(pill.radius, 14 + root.refraction * 20)
                property vector2d stretch: Qt.vector2d(pill.bx, pill.by)
                property vector2d size: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(pill.x, pill.y)
                property vector2d screen: Qt.vector2d(win.width, win.height)
                fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
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
                cursorShape: (win.viewMode === "list" || win.viewMode === "notif" || win.viewMode === "music" || win.viewMode === "file") ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: {
                    if (root.appLauncherOpen || root.switcherOpen || root.listOpen || root.overviewOpen || root.shelfOpen || root.shelfPreview) return;
                    if (root.current) { hold.stop(); if (win.viewMode === "notif") root.notifOpen = true; }
                }
                onExited: {
                    root.notifOpen = false;
                    if (!root.appLauncherOpen && !root.switcherOpen && !root.listOpen && !root.overviewOpen && !root.shelfOpen && !root.shelfPreview && root.current) { hold.interval = 1200; hold.restart(); }
                }
                onPressed: m => {
                    if (m.button === Qt.RightButton) {
                        root.cancelLeftClicks();
                        rightClick.stop(); root.skipRightRelease = false;
                        if (root.current && (win.viewMode === "notif" || (win.viewMode === "file" && root.current.kind === "alarm"))) {
                            root.rightClickCount = 0;
                            root.lastRightPress = 0;
                            root.skipRightRelease = true;
                            root.dismissCurrent();
                            return;
                        }
                        const now = Date.now();
                        root.rightClickCount = now - root.lastRightPress <= Application.styleHints.mouseDoubleClickInterval
                            ? root.rightClickCount + 1 : 1;
                        root.lastRightPress = now;
                        if (root.rightClickCount >= 3) {
                            root.rightClickCount = 0;
                            root.skipRightRelease = true;
                            if (root.shelfOpen) root.compactOutside();
                            else root.openShelf();
                        }
                    } else if (m.button === Qt.LeftButton) {
                        root.registerLeftClick();
                    }
                }
                onClicked: m => {
                    if (m.button === Qt.RightButton) {
                        if (!root.skipRightRelease) rightClick.restart();
                        return;
                    }
                }
                onDoubleClicked: m => {
                    if (m.button === Qt.RightButton) {
                        if (!root.skipRightRelease) rightClick.restart();
                        m.accepted = true;
                    } else if (m.button === Qt.LeftButton) {
                        // Qt suppresses the second press when a double-click is
                        // accepted. Count it here exactly once instead.
                        root.registerLeftClick();
                        m.accepted = true;
                    } else m.accepted = false;
                }
            }

            // =================== music (compact) ===================
            Item {
                id: musicView
                readonly property bool on: win.viewMode === "music"
                anchors.fill: parent
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.9
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: musicView.on ? 220 : 110 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                RoundedImage {
                    id: miniArt
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 12
                    source: root.musicArt
                }
                Text {
                    anchors.left: miniArt.right; anchors.leftMargin: 9
                    anchors.right: eq.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.musicTitle
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
                readonly property bool on: win.viewMode === "hud"
                anchors.fill: parent
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.9
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: hudView.on ? 220 : 110 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                readonly property var ev: root.current && root.current.layout === "hud" ? root.current : null
                readonly property bool isVolume: ev !== null && ev.kind === "volume"
                readonly property bool volumeMuted: isVolume && ev.title === "Muted"
                readonly property real level: ev && ev.value !== undefined ? Math.max(0, Math.min(1, ev.value)) : 0

                // Volume uses a quiet monochrome capsule, with a retargetable fill.
                Item {
                    anchors.fill: parent
                    visible: hudView.isVolume
                    Image {
                        id: volumeSpeaker
                        x: 19
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24
                        sourceSize.width: 48; sourceSize.height: 48
                        smooth: true
                        opacity: hudView.volumeMuted ? 0.55 : 1
                        source: {
                            const speaker = '<path d="M3.5 9h3.8l5-4.1c.6-.5 1.2-.2 1.2.6v13c0 .8-.6 1.1-1.2.6l-5-4.1H3.5c-.6 0-1-.4-1-1v-4c0-.6.4-1 1-1Z" fill="#f5f5f7"/>';
                            let waves = '';
                            if (hudView.volumeMuted)
                                waves = '<path d="m17 9 5 6m0-6-5 6"/>';
                            else if (hudView.level > 0) {
                                waves = '<path d="M16 8.8a4.6 4.6 0 0 1 0 6.4"/>';
                                if (hudView.level >= .34) waves += '<path d="M18.5 6.2a8.2 8.2 0 0 1 0 11.6"/>';
                                if (hudView.level >= .67) waves += '<path d="M21 3.9a11.5 11.5 0 0 1 0 16.2"/>';
                            }
                            return 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="26" height="24" viewBox="0 0 26 24">' + speaker + '<g fill="none" stroke="#f5f5f7" stroke-width="1.7" stroke-linecap="round">' + waves + '</g></svg>');
                        }
                    }
                    Rectangle {
                        id: volumeTrack
                        anchors.left: volumeSpeaker.right; anchors.leftMargin: 15
                        anchors.right: volumePercent.left; anchors.rightMargin: 15
                        anchors.verticalCenter: parent.verticalCenter
                        height: 9; radius: height / 2
                        color: "#343436"
                        clip: true
                        Rectangle {
                            height: parent.height; radius: height / 2
                            width: volumeTrack.width * hudView.level
                            color: "#f5f5f7"
                            Behavior on width {
                                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                    Text {
                        id: volumePercent
                        anchors.right: parent.right; anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        width: 43
                        text: hudView.volumeMuted ? "0%" : (hudView.ev ? hudView.ev.detail + "%" : "")
                        horizontalAlignment: Text.AlignRight
                        color: hudView.volumeMuted ? "#8e8e93" : "#d1d1d6"
                        font.family: "Adwaita Sans"
                        font.pixelSize: 12; font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }

                // glyph gives a small kick every time the level changes
                Text {
                    id: hudGlyph
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    visible: !hudView.isVolume
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
                    function onLevelChanged() { if (hudView.on && !hudView.isVolume) kick.restart(); }
                }
                Rectangle {
                    id: track
                    visible: !hudView.isVolume
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
                    visible: !hudView.isVolume
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
                readonly property bool on: win.viewMode === "status"
                anchors.fill: parent
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.9
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: musicView.on ? 220 : 110 } }
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
                readonly property bool on: win.viewMode === "list"
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
                        color: rowArea.pressed ? "#29292d" : rowArea.containsMouse ? "#202023" : "#111113"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        // Dark glass finish over the black history panel. These
                        // highlights are static; no monitor capture or blur pass.
                        Rectangle {
                            anchors.fill: parent
                            radius: row.radius
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#20ffffff" }
                                GradientStop { position: 0.32; color: "#07ffffff" }
                                GradientStop { position: 0.68; color: "#02ffffff" }
                                GradientStop { position: 1; color: "#0dffffff" }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: row.radius
                            color: "transparent"
                            border.width: 1
                            border.color: rowArea.containsMouse ? "#42ffffff" : "#25ffffff"
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                        Rectangle {
                            x: row.radius
                            y: 1
                            width: Math.max(0, parent.width - row.radius * 2)
                            height: 1
                            opacity: 0.45
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 0.28; color: "#b3ffffff" }
                                GradientStop { position: 0.72; color: "#38ffffff" }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }

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
                readonly property bool on: win.viewMode === "file"
                anchors.fill: parent
                opacity: on ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: fileView.on ? 200 : 100 } }

                readonly property var ev: root.current && root.current.layout === "file" ? root.current : null
                readonly property string st: ev ? ev.state : ""
                readonly property color accent: root.stateColors[st] || "#ffffff"
                readonly property string badgeGlyph: ({ done: "󰄬", added: "󰐕", modified: "󰏫", deleted: "󰩺", renamed: "󰑕", canceled: "󰅖",
                                                        copied: "󰆏", cut: "󰆐", pasted: "󰆒", alarm: "󰀠" })[st] || ""

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
                readonly property bool on: win.viewMode === "notif"
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

                NotificationStack {
                    id: notificationStack
                    width: parent.width
                    rows: activeNotifications
                    events: root.notificationEvents
                    textFont: root.textFont
                    foreground: root.fg
                    secondary: root.dim
                    expandedBody: win.isFocusedMonitor && root.notifOpen && activeNotifications.count === 1
                    onPressed: (event, button) => {
                        if (button === Qt.RightButton) {
                            rightClick.stop();
                            root.rightClickCount = 0;
                            root.lastRightPress = 0;
                            root.skipRightRelease = true;
                            root.dismissNotification(event);
                        } else root.registerLeftClick(event);
                    }
                    onDoublePressed: event => root.registerLeftClick(event)
                    onActionRequested: (event, action) => {
                        if (event && event.uid !== undefined) root.srpCall("action", [event.uid, action]);
                        root.removeNotification(event);
                    }
                }
            }

            // =================== music (expanded) ===================
            Item {
                id: bigMusic
                readonly property bool on: win.viewMode === "musicExpanded"
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
                    source: root.musicArt
                }
                Column {
                    anchors.left: bigArt.right; anchors.leftMargin: 14
                    anchors.right: parent.right; anchors.top: parent.top
                    spacing: 2
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.musicTitle
                        color: root.fg
                        font.family: root.textFont; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.musicArtist
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
                Loader {
                    anchors.left: parent.left; anchors.leftMargin: 196
                    anchors.right: parent.right
                    anchors.top: parent.top; anchors.topMargin: 40
                    height: 52
                    active: bigMusic.on && root.cfg.showLyrics !== false && root.player !== null
                    sourceComponent: Component {
                        IslandLyrics {
                            player: root.player
                            position: root.player ? root.player.position : 0
                            textFont: root.textFont
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                    height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.2)
                    Rectangle {
                        height: parent.height; radius: 2; color: "#ffffff"
                        width: root.player && root.player.length > 0 ? parent.width * Math.max(0, Math.min(1, root.player.position / root.player.length)) : 0
                    }
                }
                FrameAnimation {
                    running: bigMusic.on && root.player !== null && root.player.isPlaying
                    onTriggered: root.player.positionChanged()
                }
            }
            // Overview shares the island's shape, palette and expansion springs.
            Overview {
                anchors.fill: parent; anchors.margins: 24
                glassTexture: backdropTexture
                glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                glassStrength: root.refraction
                glassOrigin: Qt.point(pill.x + 24, pill.y + 24)
                glassScreen: Qt.vector2d(win.width, win.height)
                widgetOrder: Array.isArray(root.cfg.overviewWidgets) ? root.cfg.overviewWidgets : ["clock", "batteries", "connections", "screenTime", "system", "files"]
                screenSeconds: screenTime.seconds
                screenHours: screenTime.hours
                screenIdle: screenTime.idle
                textFont: root.textFont; iconFont: root.iconFont
                fileCount: shelf.count
                onFilesRequested: root.openShelf()
                opacity: win.viewMode === "overview" ? 1 : 0
                visible: opacity > 0.01
                scale: win.viewMode === "overview" ? 1 : 0.96
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            }
            Loader {
                id: appsLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "apps"
                sourceComponent: Component {
                    AppLauncher {
                        opened: root.appLauncherOpen && win.isFocusedMonitor
                        glassTexture: backdropTexture
                        glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                        glassStrength: root.refraction
                        glassOrigin: Qt.point(pill.x + appsLoader.x, pill.y + appsLoader.y)
                        glassScreen: Qt.vector2d(win.width, win.height)
                        textFont: root.textFont
                        onDismissed: root.closeApps()
                        onLaunchRequested: appId => root.appAction("launchId", appId)
                        onPinRequested: appId => root.appAction("pinId", appId)
                    }
                }
            }
            Loader {
                id: switcherLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "switcher"
                sourceComponent: Component {
                    WindowSwitcher {
                        opened: root.switcherOpen && win.isFocusedMonitor
                        glassTexture: backdropTexture
                        glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                        glassStrength: root.refraction
                        glassOrigin: Qt.point(pill.x + switcherLoader.x, pill.y + switcherLoader.y)
                        glassScreen: Qt.vector2d(win.width, win.height)
                        monitorName: root.switcherMonitor
                        textFont: root.textFont
                        onDismissed: root.closeSwitcher()
                    }
                }
            }
            FileShelf {
                id: shelf
                anchors.fill: parent; anchors.margins: 24
                glassTexture: backdropTexture
                glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                glassStrength: root.refraction
                glassOrigin: Qt.point(pill.x + shelf.x, pill.y + shelf.y)
                glassScreen: Qt.vector2d(win.width, win.height)
                textFont: root.textFont; iconFont: root.iconFont
                hoveringDrop: shelfDrop.containsDrag
                opacity: win.viewMode === "shelf" ? 1 : 0
                visible: opacity > 0.01
                onDraggingOut: active => root.shelfDragging = active
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            DropArea {
                id: shelfDrop
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: drag => {
                    if (!drag.hasUrls || (drag.source && drag.source.isShelfFile === true) || shelf.busy) {
                        drag.accepted = false; return;
                    }
                    drag.accepted = true;
                    root.shelfPreview = true;
                    hold.stop();
                }
                onExited: {
                    shelf.dropSlot = -1;
                    root.shelfPreview = false;
                    if (!root.shelfOpen && !root.listOpen && !root.overviewOpen && root.current) {
                        hold.interval = 1200; hold.restart();
                    }
                }
                onPositionChanged: drag => {
                    const point = shelf.mapFromItem(shelfDrop, drag.x, drag.y);
                    shelf.dropSlot = shelf.slotAt(point.x, point.y);
                }
                onDropped: drop => {
                    if (!drop.hasUrls || shelf.busy || (drop.source && drop.source.isShelfFile === true)) { drop.accepted = false; return; }
                    const urls = drop.urls;
                    root.openShelf();
                    const point = shelf.mapFromItem(shelfDrop, drop.x, drop.y);
                    shelf.add(urls, shelf.slotAt(point.x, point.y));
                    shelf.dropSlot = -1;
                    drop.action = Qt.CopyAction;
                    drop.accepted = true;
                }
            }
        }
            }
        }
    }
}
