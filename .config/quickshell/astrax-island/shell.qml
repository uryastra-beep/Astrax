import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

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
    // shape: "island" (floating pill) or "notch" (hangs from the top edge, square top, rounded bottom).
    // The notch keeps its own idle size; every mode that is bigger grows from it like the island does.
    readonly property bool notch: cfg.shape === "notch"
    readonly property real notchW: cfg.notchWidth !== undefined ? cfg.notchWidth : 200
    readonly property real notchH: cfg.notchHeight !== undefined ? cfg.notchHeight : 34
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
        if (!ev.shownAt) ev.shownAt = Date.now();
        if (existing < 0) {
            activeNotifications.insert(0, { token: token });
        } else if (existing > 0) activeNotifications.move(existing, 0, 1);
        if (activeNotifications.count >= 3) root.notificationBatchSealed = true;
        root.current = root.notificationEvents[activeNotifications.get(0).token];
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
        else {
            root.current = events[activeNotifications.get(0).token];
            hold.interval = 2500; hold.restart();
        }
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
        else if (ev.openPath) root.openPath(ev.openPath, true);
        root.removeNotification(ev);
    }
    property bool listOpen: false       // notification list (triple-click)
    property var listItems: []          // notifications, from Serpantinum
    // ordered ids of the idle-strip items (the "idleWidgets" setting); empty = a plain idle island
    readonly property var idleItems: root.cfg.hideWhenIdle !== true && Array.isArray(root.cfg.idleWidgets) ? root.cfg.idleWidgets : []
    // privacy dots (the "privacy" idle-strip item): kept at the island's corner in every mode, even with a
    // panel open or music playing. idle-status.py reports mic / camera / screen-cast use.
    readonly property bool privacyOn: Array.isArray(root.cfg.idleWidgets) && root.cfg.idleWidgets.indexOf("privacy") >= 0
    property var privacy: ({mic: false, cam: false, screen: false})
    Process {
        running: root.privacyOn && root.cfg.enabled !== false
        command: ["setpriv", "--pdeathsig", "TERM", "python3", Quickshell.shellPath("idle-status.py")]
        stdout: SplitParser { onRead: line => { try { root.privacy = JSON.parse(line); } catch (e) {} } }
    }
    // Spotify "like": like-bridge.py talks to the astrax-like.js Spicetify extension running inside Spotify
    property var like: ({connected: false, liked: false})
    Process {
        running: root.cfg.enabled !== false
        command: ["setpriv", "--pdeathsig", "TERM", "python3", Quickshell.shellPath("like-bridge.py")]
        stdout: SplitParser { onRead: line => { try { root.like = JSON.parse(line); } catch (e) {} } }
    }
    Process { id: likeToggle; command: ["python3", Quickshell.shellPath("like-bridge.py"), "toggle"] }
    readonly property bool canLike: like.connected && player !== null && player.dbusName.toLowerCase().indexOf("spotify") >= 0
    function toggleLike() {
        if (!canLike || likeToggle.running) return;
        root.like = Object.assign({}, root.like, {liked: !root.like.liked});   // flips at once, the extension confirms
        likeToggle.running = true;
    }
    property var activity: []           // files / clipboard / device events seen by the island
    property int activityId: 0
    // one list for everything, newest first
    readonly property var allItems: {
        const ev = root.activity
            .filter(a => !/^brain\.sqlite3(?:-(?:wal|shm|journal))?$/i.test(a.summary || ""))
            .map(a => Object.assign({ kind: "event" }, a));
        return root.listItems.concat(ev).sort((a, b) => b.ts - a.ts).slice(0, 30);
    }
    readonly property var stateColors: ({ progress: "#4aa3ff", done: "#30d158", canceled: "#ff453a", added: "#30d158",
                                          modified: "#ff9f0a", deleted: "#ff453a", renamed: "#4aa3ff", batch: "#4aa3ff",
                                          copied: "#4aa3ff", cut: "#ff9f0a", pasted: "#30d158", alarm: "#ff9f0a" })
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
    property bool clipOpen: false
    property bool trOpen: false         // translator (Super+T)
    property bool aiOpen: false         // AI monitor: Claude + Codex status/usage (Super+M)
    property bool ctrlOpen: false       // control panel (click on the idle island)
    property string hubTab: "widgets"    // last tab picked in the double right-click hub (NotchHub.qml)
    property bool ctrlPicking: false
    property bool musicLyricsHidden: true    // lyrics button on the expanded music card (off by default)    // the control panel's file picker is open: keep the panel, free the keyboard
    property bool emojiOpen: false      // emoji picker (Super+.): inside the island, or its own window when the island is off
    property bool qaOpen: false
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
        if (root.appLauncherOpen || root.switcherOpen || root.listOpen || root.overviewOpen || root.clipOpen || root.emojiOpen || root.aiOpen || root.trOpen || root.ctrlOpen || root.qaOpen || root.shelfOpen || root.shelfPreview) {
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
            "if command -v ski >/dev/null; then ski \"$3\"; else xdg-open \"$3\"; fi",
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
        root.overviewOpen = false; root.clipOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; root.qaOpen = false;
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
    property real lastLeftRegister: 0
    function registerLeftClick(notification) {
        // Qt can report the second press of a double click twice (onPressed and onDoubleClicked):
        // count one physical press once, or a double click turns into a triple (notification list).
        const nowMs = Date.now();
        if (nowMs - root.lastLeftRegister < 40) return;
        root.lastLeftRegister = nowMs;
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
                else if (!root.current && root.mode === "idle") root.leftClickAction = "control";
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
            // With music in the island, a single click opens the player, so Ask Claude moves to a double click.
            if (count === 2 && action === "music" && !root.current && root.hasMusic
                && !root.listOpen && !root.overviewOpen && !root.clipOpen && !root.emojiOpen && !root.aiOpen && !root.trOpen && !root.ctrlOpen && !root.qaOpen && !root.shelfOpen && !root.shelfPreview) {
                root.openCtrl();
                return;
            }
            if (count !== 1 || root.listOpen || root.overviewOpen || root.clipOpen || root.emojiOpen || root.aiOpen || root.trOpen || root.ctrlOpen || root.qaOpen || root.shelfOpen || root.shelfPreview) return;
            if (action === "activate" && event && (root.current === event || root.notificationIndex(event) >= 0)) {
                if (event.layout === "notif") root.activateNotification(event);
                else root.activateCurrent();
            }
            else if (action === "music" && !root.current && root.hasMusic) root.expanded = true;
            else if (action === "control" && !root.current && root.mode === "idle") root.openCtrl();
        }
    }

    // Collapse a surface without dismissing notifications in history.
    function compactOutside() {
        root.appLauncherOpen = false;
        root.switcherOpen = false;
        rightClick.stop();
        root.shelfOpen = false; root.shelfPreview = false;
        root.overviewOpen = false; root.clipOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; root.qaOpen = false;
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
        root.overviewOpen = false; root.listOpen = false; root.clipOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; root.qaOpen = false;
        root.shelfOpen = true; root.shelfPreview = false;
        root.expanded = false; root.notifOpen = false;
        hold.stop();
    }
    function openOverview() {
        root.appLauncherOpen = false;
        root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        // The double-right-click gesture toggles this overview.
        root.listOpen = false; root.clipOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; root.qaOpen = false;
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
        function toggleQa(): string {
            if (root.qaOpen) root.closeQa(); else root.openQa();
            return root.qaOpen ? "open" : "closed";
        }
        function toggleClip(): string {
            if (root.clipOpen) root.closeClip(); else root.openClip();
            return root.clipOpen ? "open" : "closed";
        }
        function toggleTranslate(): string {
            if (root.trOpen) root.closeTr(); else root.openTr();
            return root.trOpen ? "open" : "closed";
        }
        function toggleAi(): string {
            if (root.aiOpen) root.closeAi(); else root.openAi();
            return root.aiOpen ? "open" : "closed";
        }
        function toggleControl(): string {
            if (root.ctrlOpen) root.closeCtrl(); else root.openCtrl();
            return root.ctrlOpen ? "open" : "closed";
        }
        function toggleEmoji(): string {
            if (root.emojiOpen) root.closeEmoji(); else root.openEmoji();
            return root.emojiOpen ? "open" : "closed";
        }
        function openEmoji(): void { root.openEmoji(); }
        function closeEmoji(): void { root.closeEmoji(); }
        function openClip(): void { root.openClip(); }
        function closeClip(): void { root.closeClip(); }
        function openSwitcher(): void { root.openSwitcher(); }
        function closeSwitcher(): void { root.closeSwitcher(); }
        function toggleList(): string { root.toggleList(); return root.listOpen ? "open" : "closed"; }
        // SUPER + F (hypr/config/binds-island.lua): same as the double right click
        function toggleOverview(): string {
            if (root.overviewOpen) root.compactOutside(); else root.openOverview();
            return root.overviewOpen ? "open" : "closed";
        }
        // called by the non-consuming Ctrl+V binds (config/binds-island.lua)
        function paste(): string { clipSrc.paste(); return "ok"; }
        function outsideClick(): string {
            if ((!root.largeView && root.leftClickCount === 0) || root.shelfDragging || root.ctrlPicking || outsidePointer.running) return "ignored";
            outsidePointer.running = true;
            return "ok";
        }
    }

    function openApps() {
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.switcherOpen = false; root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.clipOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; root.qaOpen = false; root.expanded = false; root.notifOpen = false;
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

    function openQa() {
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.appLauncherOpen = false; root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.clipOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; root.expanded = false; root.notifOpen = false;
        root.qaOpen = true; hold.stop();
    }
    function closeQa() {
        root.qaOpen = false;
        if (root.cfg.enabled === false) return;
        if (root.current) { hold.interval = 1600; hold.restart(); }
        else if (root.queue.length) root.next();
    }
    function openClip() {
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.appLauncherOpen = false; root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.expanded = false; root.notifOpen = false;
        root.clipOpen = true; root.qaOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; hold.stop();
    }
    function openAi() {
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.appLauncherOpen = false; root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.clipOpen = false; root.qaOpen = false; root.emojiOpen = false; root.expanded = false; root.notifOpen = false;
        root.ctrlOpen = false; root.trOpen = false; root.aiOpen = true; hold.stop();
    }
    function openTr() {
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.appLauncherOpen = false; root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.clipOpen = false; root.qaOpen = false; root.emojiOpen = false; root.expanded = false; root.notifOpen = false;
        root.ctrlOpen = false; root.aiOpen = false; root.trOpen = true; hold.stop();
    }
    function closeTr() {
        root.trOpen = false;
        if (root.cfg.enabled === false) return;
        if (root.current) { hold.interval = 1600; hold.restart(); }
        else if (root.queue.length) root.next();
    }
    function closeAi() {
        root.aiOpen = false; root.trOpen = false;
        if (root.cfg.enabled === false) return;
        if (root.current) { hold.interval = 1600; hold.restart(); }
        else if (root.queue.length) root.next();
    }
    function openCtrl() {
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.appLauncherOpen = false; root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.clipOpen = false; root.qaOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.expanded = false; root.notifOpen = false;
        root.ctrlOpen = true; hold.stop();
    }
    function closeCtrl() {
        root.ctrlOpen = false; root.ctrlPicking = false;
        if (root.cfg.enabled === false) return;
        if (root.current) { hold.interval = 1600; hold.restart(); }
        else if (root.queue.length) root.next();
    }
    // Emoji picker. With the island on it is a panel of the island; with it off, standaloneEmoji (below) shows it.
    function openEmoji() {
        root.cancelLeftClicks(); rightClick.stop();
        root.appLauncherOpen = false; root.switcherOpen = false;
        root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.clipOpen = false; root.qaOpen = false; root.expanded = false; root.notifOpen = false;
        root.emojiOpen = true; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; hold.stop();
    }
    function closeEmoji() {
        root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false;
        if (root.cfg.enabled === false) return;
        if (root.current) { hold.interval = 1600; hold.restart(); }
        else if (root.queue.length) root.next();
    }
    function closeClip() {
        root.clipOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; root.qaOpen = false;
        if (root.cfg.enabled === false) return;
        if (root.current) { hold.interval = 1600; hold.restart(); }
        else if (root.queue.length) root.next();
    }

    function openSwitcher() {
        root.appLauncherOpen = false;
        if (root.cfg.enabled === false) return;
        root.cancelLeftClicks(); rightClick.stop();
        root.shelfOpen = false; root.shelfPreview = false;
        root.listOpen = false; root.overviewOpen = false; root.clipOpen = false; root.emojiOpen = false; root.aiOpen = false; root.trOpen = false; root.ctrlOpen = false; root.qaOpen = false;
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
            artworkLookup.command = ["/usr/bin/python3", Quickshell.env("HOME") + "/.local/lib/iphone-notifications/phone-artwork.py", root.artworkRequestKey];
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
        onExited: {
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
    readonly property string mode: appLauncherOpen ? "apps" : switcherOpen ? "switcher" : (shelfOpen || shelfPreview) ? "shelf" : qaOpen ? "qa" : clipOpen ? "clip" : aiOpen ? "ai" : trOpen ? "tr" : ctrlOpen ? "ctrl" : emojiOpen ? "emoji" : overviewOpen ? "overview" : listOpen ? "list" : current ? current.layout
        : (expanded && hasMusic) ? "musicExpanded" : hasMusic ? "music" : "idle"
    readonly property bool largeView: mode === "apps" || mode === "switcher" || mode === "list" || mode === "notif" || mode === "musicExpanded" || mode === "overview" || mode === "shelf" || mode === "clip" || mode === "ai" || mode === "tr" || mode === "ctrl" || mode === "emoji" || mode === "qa"

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
        WlrLayershell.keyboardFocus: (win.viewMode === "switcher" || win.viewMode === "apps" || win.viewMode === "clip" || win.viewMode === "ai" || win.viewMode === "tr" || (win.viewMode === "ctrl" && !root.ctrlPicking) || win.viewMode === "emoji" || win.viewMode === "qa" || win.viewMode === "list") && win.isFocusedMonitor ? WlrKeyboardFocus.Exclusive : (win.viewMode === "overview" && win.isFocusedMonitor ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
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
                const y = (desktopY - win.screen.y - pill.y - pill.scaleOriginY) / pill.by + pill.scaleOriginY;
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

        // notch backdrop: the body tint, the two concave shoulders and the glass lens are ONE shape that
        // follows the pill (same geometry and bubble transform), so the shoulders get the same Liquid Glass.
        Item {
            id: notchBack
            visible: root.notch && pill.width > 0
            x: pill.x; y: pill.y; width: pill.width; height: pill.height
            transform: Scale { origin.x: notchBack.width / 2; origin.y: pill.scaleOriginY; xScale: pill.bx; yScale: pill.by }
            readonly property color tint: Qt.rgba(0.08, 0.08, 0.1, root.glassAlpha)
            // the shoulders grow with the panel: 12 px on the idle notch, up to 26 px on big panels
            readonly property real wing: Math.round(Math.max(12, Math.min(26, Math.min(width / 16, height / 7))) * 2) / 2

            Rectangle {
                visible: pill.glassOn
                width: parent.width; height: parent.height
                radius: pill.radius
                topLeftRadius: 0; topRightRadius: 0
                color: notchBack.tint
            }
            // the black band below (see `band`) in pixels, so the shoulders can carry the very same fade
            readonly property real bandPeak: 0.82
            readonly property real bandSolid: 0.35 * Math.min(root.notchH, height)
            readonly property real bandEnd: Math.max(bandSolid + 1, Math.min(height, root.notchH + 34))
            // same alpha profile as the body band, so the shoulders and the body match pixel for pixel
            readonly property real shoulderPeak: 0.45   // measured on screen: the lens is dimmer in the shoulders, so they need less black than the body
            readonly property real shoulderAlpha: shoulderPeak * (1 - Math.max(0, Math.min(1, (wing - bandSolid) / (bandEnd - bandSolid))))
            property real glassMix: pill.glassOn ? 1 : 0
            Behavior on glassMix { NumberAnimation { duration: 260 } }
            // The shoulders: solid black while the notch is idle, the panel's glass tint while a Liquid Glass panel is
            // open (the lens below draws the glass in them). Anti-aliased curves (CurveRenderer; the default renderer
            // draws hard stair-stepped edges) and reach 2 px into the body, where the band is already solid black, so a
            // fractional pill position can never leave a 1 px seam between body and shoulder.
            // The arc is 0.6 px tighter than the glass lens's own edge, which covers the lens's soft fringe.
            Shape {
                preferredRendererType: Shape.CurveRenderer
                x: -notchBack.wing; y: 0
                width: notchBack.wing + 2; height: notchBack.wing
                ShapePath {
                    fillColor: pill.glassOn ? notchBack.tint : "#000000"
                    strokeWidth: -1
                    Behavior on fillColor { ColorAnimation { duration: 260 } }
                    PathSvg { path: "M 0 0 L " + (notchBack.wing + 2) + " 0 L " + (notchBack.wing + 2) + " " + notchBack.wing + " L " + (notchBack.wing - 0.6) + " " + notchBack.wing + " A " + (notchBack.wing - 0.6) + " " + (notchBack.wing - 0.6) + " 0 0 0 0 0.6 Z" }
                }
            }
            Shape {
                preferredRendererType: Shape.CurveRenderer
                x: notchBack.width - 2; y: 0
                width: notchBack.wing + 2; height: notchBack.wing
                ShapePath {
                    fillColor: pill.glassOn ? notchBack.tint : "#000000"
                    strokeWidth: -1
                    Behavior on fillColor { ColorAnimation { duration: 260 } }
                    PathSvg { path: "M " + (notchBack.wing + 2) + " 0 L 0 0 L 0 " + notchBack.wing + " L 2.6 " + notchBack.wing + " A " + (notchBack.wing - 0.6) + " " + (notchBack.wing - 0.6) + " 0 0 1 " + (notchBack.wing + 2) + " 0.6 Z" }
                }
            }
            // Expanded music card: each shoulder takes the colours of the island edge next to it (the left one
            // the left edge, the right one the right edge). A 3 px strip of the card's art wash is stretched
            // across the shoulder and cut to its concave shape, so it follows the drifting art live.
            Repeater {
                model: [ { side: "l" }, { side: "r" } ]
                Item {
                    id: shoulderTint
                    required property var modelData
                    readonly property bool isLeft: modelData.side === "l"
                    visible: opacity > 0.01
                    opacity: bigMusic.on ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: bigMusic.on ? 240 : 100 } }
                    x: isLeft ? -notchBack.wing : notchBack.width - 2
                    y: 0
                    width: notchBack.wing + 2; height: notchBack.wing
                    ShaderEffectSource {
                        id: strip
                        sourceItem: artBg
                        sourceRect: Qt.rect(shoulderTint.isLeft ? 0 : artBg.width - 3, 0, 3, notchBack.wing)
                        width: shoulderTint.width; height: shoulderTint.height
                        live: bigMusic.on
                        smooth: true
                        visible: false
                    }
                    Shape {
                        id: shoulderMask
                        preferredRendererType: Shape.CurveRenderer
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        ShapePath {
                            fillColor: "#ffffff"
                            strokeWidth: -1
                            PathSvg {
                                path: shoulderTint.isLeft
                                    ? "M 0 0 L " + (notchBack.wing + 2) + " 0 L " + (notchBack.wing + 2) + " " + notchBack.wing + " L " + (notchBack.wing - 0.6) + " " + notchBack.wing + " A " + (notchBack.wing - 0.6) + " " + (notchBack.wing - 0.6) + " 0 0 0 0 0.6 Z"
                                    : "M " + (notchBack.wing + 2) + " 0 L 0 0 L 0 " + notchBack.wing + " L 2.6 " + notchBack.wing + " A " + (notchBack.wing - 0.6) + " " + (notchBack.wing - 0.6) + " 0 0 1 " + (notchBack.wing + 2) + " 0.6 Z"
                            }
                        }
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: strip
                        maskEnabled: true
                        maskSource: shoulderMask
                    }
                }
            }
            ShaderEffect {
                x: -notchBack.wing; y: 0
                width: notchBack.width + notchBack.wing * 2; height: notchBack.height
                visible: pill.glassOn && snap.hasContent && root.refraction > 0
                property var src: backdropTexture
                property real radius: pill.radius
                property real strength: root.refraction
                property real band: Math.min(pill.radius, 14 + root.refraction * 20)
                property vector2d size: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(pill.x - notchBack.wing, pill.y)
                property vector2d screen: Qt.vector2d(win.width, win.height)
                property vector2d stretch: Qt.vector2d(pill.bx, pill.by)
                property real wing: notchBack.wing
                fragmentShader: Qt.resolvedUrl("glass-notch3.frag.qsb")
            }
            // the glass pours out of the notch: solid black at the top (the notch itself, same height as the
            // idle notch), fading into the glass below, so an open panel still reads as the notch growing down
            Rectangle {
                visible: pill.glassOn
                width: parent.width; height: parent.height
                radius: pill.radius
                topLeftRadius: 0; topRightRadius: 0
                readonly property real solid: Math.min(1, root.notchH / Math.max(1, height))
                readonly property real fade: Math.min(1, (root.notchH + 34) / Math.max(1, height))
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, notchBack.bandPeak) }
                    GradientStop { position: band.solid * 0.35; color: Qt.rgba(0, 0, 0, notchBack.bandPeak) }
                    GradientStop { position: band.fade; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                id: band
            }

            // the shoulders get the band's black fade too (drawn over the lens), so the colour runs unbroken from
            // the dark top of the body into the shoulders instead of cutting to lighter glass at their edge
            Shape {
                preferredRendererType: Shape.CurveRenderer
                visible: notchBack.glassMix > 0.01
                opacity: notchBack.glassMix
                x: -notchBack.wing; y: 0
                width: notchBack.wing; height: notchBack.wing
                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: 0; y2: notchBack.wing
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, notchBack.shoulderPeak) }
                        GradientStop { position: Math.min(1, notchBack.bandSolid / notchBack.wing); color: Qt.rgba(0, 0, 0, notchBack.shoulderPeak) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, notchBack.shoulderAlpha) }
                    }
                    PathSvg { path: "M 0 0 L " + notchBack.wing + " 0 L " + notchBack.wing + " " + notchBack.wing + " L " + (notchBack.wing - 0.6) + " " + notchBack.wing + " A " + (notchBack.wing - 0.6) + " " + (notchBack.wing - 0.6) + " 0 0 0 0 0.6 Z" }
                }
            }
            Shape {
                preferredRendererType: Shape.CurveRenderer
                visible: notchBack.glassMix > 0.01
                opacity: notchBack.glassMix
                x: notchBack.width; y: 0
                width: notchBack.wing; height: notchBack.wing
                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: 0; y2: notchBack.wing
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, notchBack.shoulderPeak) }
                        GradientStop { position: Math.min(1, notchBack.bandSolid / notchBack.wing); color: Qt.rgba(0, 0, 0, notchBack.shoulderPeak) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, notchBack.shoulderAlpha) }
                    }
                    PathSvg { path: "M " + notchBack.wing + " 0 L 0 0 L 0 " + notchBack.wing + " L 0.6 " + notchBack.wing + " A " + (notchBack.wing - 0.6) + " " + (notchBack.wing - 0.6) + " 0 0 1 " + notchBack.wing + " 0.6 Z" }
                }
            }

            // notch rim: one open line that runs up the outer edge of each shoulder (the same concave arc as the
            // glass lens), down both sides and along the bottom, so the shoulders and the panel share one outline.
            // It lives here, not in the pill, because the pill clips to its own box and the shoulders sit outside it.
            Shape {
                visible: root.notch
                preferredRendererType: Shape.CurveRenderer
                opacity: pill.glassOn ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260 } }
                ShapePath {
                    id: rim
                    readonly property real r: Math.max(1, Math.min(pill.radius, notchBack.width / 2, notchBack.height / 2))
                    readonly property real w: notchBack.width
                    readonly property real h: notchBack.height
                    readonly property real k: notchBack.wing
                    strokeColor: Qt.rgba(1, 1, 1, 0.26)
                    strokeWidth: 1
                    fillColor: "transparent"
                    PathSvg {
                        path: "M " + (-rim.k) + " -0.5 A " + (rim.k + 0.5) + " " + (rim.k + 0.5) + " 0 0 1 0.5 " + rim.k
                            + " L 0.5 " + (rim.h - rim.r) + " A " + (rim.r - 0.5) + " " + (rim.r - 0.5) + " 0 0 0 " + rim.r + " " + (rim.h - 0.5)
                            + " L " + (rim.w - rim.r) + " " + (rim.h - 0.5) + " A " + (rim.r - 0.5) + " " + (rim.r - 0.5) + " 0 0 0 " + (rim.w - 0.5) + " " + (rim.h - rim.r)
                            + " L " + (rim.w - 0.5) + " " + rim.k + " A " + (rim.k + 0.5) + " " + (rim.k + 0.5) + " 0 0 1 " + (rim.w + rim.k) + " -0.5"
                    }
                }
            }
        }

        // privacy dots: a small cluster beside the island (right of the notch shoulders), always visible while in use
        Row {
            id: privacyDots
            readonly property var dots: [
                {on: root.privacy.mic, color: "#ff9f0a"},
                {on: root.privacy.cam, color: "#30d158"},
                {on: root.privacy.screen, color: "#bf5af2"}
            ]
            visible: root.privacyOn && opacity > 0.01
            opacity: (root.privacy.mic || root.privacy.cam || root.privacy.screen) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            spacing: 4
            x: pill.x + pill.width + (root.notch ? notchBack.wing : 0) + 8
            y: pill.y + Math.min(pill.height, root.notch ? root.notchH : 34) / 2 - 3.5
            Repeater {
                model: privacyDots.dots
                delegate: Rectangle {
                    required property var modelData
                    visible: modelData.on
                    width: 7; height: 7; radius: 3.5
                    color: modelData.color
                    SequentialAnimation on opacity {
                        running: parent.visible; loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
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
            property real topY: root.notch ? -1 : root.edgeMargin + root.posY * Math.max(0, parent.height - refH - 2 * root.edgeMargin)
            Behavior on cx { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on topY { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            x: (win.viewMode === "switcher" || win.viewMode === "apps") ? Math.max(root.edgeMargin, Math.min(cx - width / 2, parent.width - width - root.edgeMargin)) : cx - width / 2
            y: topY

            readonly property bool glassOn: root.glassCfg && (win.viewMode === "notif" || win.viewMode === "musicExpanded" || win.viewMode === "overview" || win.viewMode === "shelf" || win.viewMode === "switcher" || win.viewMode === "apps" || win.viewMode === "clip" || win.viewMode === "ai" || win.viewMode === "emoji" || win.viewMode === "qa" || win.viewMode === "list")
            readonly property real listH: 150 + Math.min(6, Math.max(1, root.allItems.length)) * 52
            readonly property real notifH: Math.max(68, notificationStack.implicitHeight)

            // compact states keep the pill's height and only get wider (like the
            // real island); notifications and the music card grow downwards
            // During layer recreation the surface can briefly report zero size.
            // Evaluate only the active panel; inactive Loader geometry must not
            // become a dependency of every target-size binding.
            readonly property real availableWidth: Math.max(1,
                (win.width > 0 ? win.width : win.screen && win.screen.width > 0 ? win.screen.width : 1920)
                - 2 * root.edgeMargin)
            function panelMetric(item, key, fallback) {
                const value = item ? Number(item[key]) : NaN;
                return Number.isFinite(value) && value > 0 ? value : fallback;
            }
            readonly property real targetW: {
                switch (win.viewMode) {
                case "apps": return Math.min(availableWidth, Math.max(300, 48 + panelMetric(appsLoader.item, "columns", 5) * 88));
                case "switcher": return Math.min(availableWidth, Math.max(300, 48 + panelMetric(switcherLoader.item, "columns", 4) * 220));
                case "list": case "overview": case "shelf": case "clip": case "ai": case "tr": case "emoji": case "qa": return Math.min(availableWidth, 540);
                case "ctrl": return Math.min(availableWidth, 460);
                case "musicExpanded": return 430;
                case "notif": return 410;
                case "file": return 340;
                case "status": return 320;
                case "hud": return 300;
                case "music": return 250;
                case "idle": return panelMetric(idleLoader.item, "contentWidth", 0) > 0 ? Math.max(126, idleLoader.item.contentWidth + 34) : 126;
                default: return 126;
                }
            }
            readonly property real targetH: {
                switch (win.viewMode) {
                case "apps": return panelMetric(appsLoader.item, "preferredHeight", 396);
                case "switcher": return panelMetric(switcherLoader.item, "preferredHeight", 266);
                case "overview": return hub.preferredHeight;
                case "clip": return panelMetric(clipLoader.item, "preferredHeight", 198);
                case "ai": return panelMetric(aiLoader.item, "preferredHeight", 420);
                case "tr": return panelMetric(trLoader.item, "preferredHeight", 330);
                case "ctrl": return panelMetric(ctrlLoader.item, "preferredHeight", 330);
                case "emoji": return panelMetric(emojiLoader.item, "preferredHeight", 458);
                case "qa": return panelMetric(qaLoader.item, "preferredHeight", 226);
                case "shelf": return shelf.preferredHeight;
                case "list": return listH;
                case "musicExpanded": return (root.cfg.showLyrics !== false && root.player !== null && !root.musicLyricsHidden) ? 202 : 158;
                case "notif": return notifH;
                case "file": return 46;
                default: return 34;
                }
            }
            width: root.notch ? Math.max(targetW, root.notchW) : targetW
            height: root.notch ? Math.max(targetH, root.notchH) : targetH
            radius: root.notch ? Math.min(height / 2, height <= 48 ? 14 : 28) : (height <= 48 ? height / 2 : 34)
            topLeftRadius: root.notch ? 0 : radius
            topRightRadius: root.notch ? 0 : radius
            clip: true

            color: glassOn ? (root.notch ? "transparent" : Qt.rgba(0.08, 0.08, 0.1, root.glassAlpha)) : "#000000"
            Behavior on color { ColorAnimation { duration: 260 } }

            // Preserve the original spring feel; do not animate dimensions
            // while the layer surface is hidden or still being initialized.
            readonly property bool animateGeometry: win.visible && win.width > 0 && win.height > 0
            readonly property real damp: 0.78 - 0.56 * root.bounce
            Behavior on width {
                enabled: pill.animateGeometry
                SpringAnimation { spring: 4.2; damping: pill.damp; epsilon: 0.3; mass: 0.9 }
            }
            Behavior on height {
                enabled: pill.animateGeometry
                SpringAnimation { spring: 4.2; damping: pill.damp; epsilon: 0.3; mass: 0.9 }
            }

            // bubble: swells a little under the pointer, more while pressed, and
            // wobbles back on release (taller than wide, like a soap bubble)
            // The bubble swells and wobbles around the pill's centre; the notch pivots on its top edge instead,
            // so while it springs (even below 1.0 on release) it stays glued to the top of the screen.
            readonly property real scaleOriginY: root.notch ? 0 : height / 2
            property real bx: touch.pressed ? 1.06 : pillHover.hovered ? 1.025 : 1.0
            property real by: touch.pressed ? 1.12 : pillHover.hovered ? 1.04 : 1.0
            // bubble: quick spring with a short, damped rebound (between the original 0.18 and the too-soft 0.55)
            Behavior on bx { SpringAnimation { spring: 5.5; damping: 0.3; epsilon: 0.001 } }
            Behavior on by { SpringAnimation { spring: 5; damping: 0.28; epsilon: 0.001 } }
            transform: Scale {
                origin.x: pill.width / 2
                origin.y: pill.scaleOriginY
                xScale: pill.bx
                yScale: pill.by
            }

            ShaderEffect {
                id: lens
                anchors.fill: parent
                visible: pill.glassOn && snap.hasContent && root.refraction > 0 && !root.notch   // the notch uses notchBack
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
                anchors.topMargin: root.notch ? -8 : 0   // notch: the top rim sits outside the clip, it hangs from the screen edge
                radius: pill.radius
                topLeftRadius: pill.topLeftRadius
                topRightRadius: pill.topRightRadius
                opacity: pill.glassOn ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260 } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.notch ? 0.05 : 0.20) }   // notch: no top highlight step where the shoulders join
                    GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.03) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.07) }
                }
            }
            Rectangle {
                visible: !root.notch
                anchors.fill: parent
                radius: pill.radius
                topLeftRadius: pill.topLeftRadius
                topRightRadius: pill.topRightRadius
                color: "transparent"
                border.width: 1
                border.color: pill.glassOn ? Qt.rgba(1, 1, 1, 0.26) : "transparent"
                Behavior on border.color { ColorAnimation { duration: 260 } }
            }

            // ---- input ----
            // hover anywhere on the panel (rows, buttons and search included), not just where the pill's own
            // MouseArea is exposed: child MouseAreas with hover take the events away from it
            HoverHandler { id: pillHover }
            MouseArea {
                id: touch
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: (win.viewMode === "list" || win.viewMode === "notif" || win.viewMode === "music" || win.viewMode === "file") ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: {
                    if (root.appLauncherOpen || root.switcherOpen || root.listOpen || root.overviewOpen || root.clipOpen || root.emojiOpen || root.aiOpen || root.trOpen || root.ctrlOpen || root.qaOpen || root.shelfOpen || root.shelfPreview) return;
                    if (root.current) { hold.stop(); if (win.viewMode === "notif") root.notifOpen = true; }
                }
                onExited: {
                    root.notifOpen = false;
                    if (!root.appLauncherOpen && !root.switcherOpen && !root.listOpen && !root.overviewOpen && !root.clipOpen && !root.emojiOpen && !root.aiOpen && !root.trOpen && !root.ctrlOpen && !root.qaOpen && !root.shelfOpen && !root.shelfPreview && root.current) { hold.interval = 1200; hold.restart(); }
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
                        color: "#1c1c1e"
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

            // =================== idle strip ===================
            // Wi-Fi, Bluetooth, device batteries, open apps... picked in Super+C > Dynamic Island (only offered
            // while "Hide when idle" is off). Loaded only while the island is idle, so it costs nothing otherwise.
            Loader {
                id: idleLoader
                anchors.fill: parent
                active: win.viewMode === "idle" && root.idleItems.length > 0
                sourceComponent: Component {
                    IdleStrip {
                        items: root.idleItems
                        textFont: root.textFont; iconFont: root.iconFont
                    }
                }
            }

            // =================== notification list ===================
            // Same chrome as the clipboard panel (Super+V): see NotificationHistory.qml
            Loader {
                id: historyLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "list"
                sourceComponent: Component {
                    NotificationHistory {
                        opened: root.listOpen && win.isFocusedMonitor
                        items: root.allItems
                        timeAgo: ts => root.timeAgo(ts)
                        glassTexture: backdropTexture
                        glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                        glassStrength: root.refraction
                        glassOrigin: Qt.point(pill.x + historyLoader.x, pill.y + historyLoader.y)
                        glassScreen: Qt.vector2d(win.width, win.height)
                        textFont: root.textFont; iconFont: root.iconFont
                        onDismissed: root.closeList()
                        onClearRequested: { root.srpCall("clear", []); root.listItems = []; root.activity = []; }
                        onRemoved: item => {
                            if (item.kind === "event") root.activity = root.activity.filter(x => x.id !== item.id);
                            else {
                                root.srpCall("dismiss", [item.uid]);
                                root.listItems = root.listItems.filter(x => x.uid !== item.uid);
                            }
                        }
                        onActivated: item => {
                            if (item.kind === "event") { if (item.openPath) root.openPath(item.openPath, false); }
                            else root.srpCall("activate", [item.uid]);
                            root.closeList();
                        }
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

                ArgonGlow { inset: 0; accent: "#ff7a7a"; strength: 0.4; reach: 56 }
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
            // NotchPixel card: the album's colours wash the whole island, art with the player's badge, title,
            // transport on the right, a wavy progress line (it ripples while playing), then elapsed time, the
            // lyrics toggle, a volume slider and the remaining time. Lyrics open as one more line below.
            Item {
                id: bigMusic
                readonly property bool on: win.viewMode === "musicExpanded"
                readonly property bool lyricsOn: root.cfg.showLyrics !== false && root.player !== null && !root.musicLyricsHidden
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
                function clock(sec) {
                    sec = Math.max(0, Math.floor(sec || 0));
                    return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0");
                }
                PwObjectTracker { objects: bigMusic.on ? [Pipewire.defaultAudioSink] : [] }

                // ---- album colours: sample the art into a tiny canvas, take a deep and a bright tone
                property color deep: "#2a0f3a"
                property color bright: "#ff5f7a"
                Behavior on deep { ColorAnimation { duration: 500 } }
                Behavior on bright { ColorAnimation { duration: 500 } }
                Canvas {
                    id: sampler
                    width: 12; height: 12; visible: false
                    property string src: root.musicArt
                    onSrcChanged: if (src) loadImage(src)
                    onImageLoaded: requestPaint()
                    onPaint: {
                        if (!src || !isImageLoaded(src)) return;
                        const c = getContext("2d");
                        c.drawImage(src, 0, 0, 12, 12);
                        const d = c.getImageData(0, 0, 12, 12).data;
                        let best = null, bestScore = -1, sr = 0, sg = 0, sb = 0, n = 0;
                        for (let i = 0; i < d.length; i += 4) {
                            const r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255;
                            const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
                            const sat = mx === 0 ? 0 : (mx - mn) / mx;
                            const score = sat * 0.7 + mx * 0.3;
                            if (score > bestScore) { bestScore = score; best = [r, g, b]; }
                            sr += r; sg += g; sb += b; n++;
                        }
                        if (!n) return;
                        bigMusic.deep = Qt.rgba(sr / n * 0.55, sg / n * 0.55, sb / n * 0.55, 1);
                        bigMusic.bright = best ? Qt.rgba(best[0], best[1], best[2], 1) : "#ff5f7a";
                    }
                }
                // the song's art, blurred and zoomed, drifting slowly up and down behind everything
                Item {
                    id: artBg
                    x: -16; y: -16; width: parent.width + 32; height: parent.height + 32
                    readonly property real rTop: root.notch ? 0 : pill.radius
                    readonly property real rBottom: pill.radius
                    Item {
                        id: artLayer
                        anchors.fill: parent
                        clip: true
                        visible: false
                        layer.enabled: true
                        Image {
                            id: artDrift
                            width: artLayer.width * 1.15; height: width
                            x: (artLayer.width - width) / 2
                            source: root.musicArt
                            sourceSize: Qt.size(256, 256)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: true
                            readonly property real travel: Math.max(0, height - artLayer.height)
                            property real t: 0.35
                            y: -travel * t
                            SequentialAnimation on t {
                                running: bigMusic.on
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.85; duration: 14000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0.15; duration: 14000; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Rectangle {
                        id: artMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        topLeftRadius: artBg.rTop; topRightRadius: artBg.rTop
                        bottomLeftRadius: artBg.rBottom; bottomRightRadius: artBg.rBottom
                        color: "#ffffff"
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: artLayer
                        visible: root.musicArt !== ""
                        autoPaddingEnabled: false
                        blurEnabled: true; blurMax: 64; blur: 1.0
                        saturation: 0.15
                        brightness: -0.12
                        maskEnabled: true; maskSource: artMask
                    }
                    Rectangle {   // keep text and controls readable
                        anchors.fill: parent
                        topLeftRadius: artBg.rTop; topRightRadius: artBg.rTop
                        bottomLeftRadius: artBg.rBottom; bottomRightRadius: artBg.rBottom
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#59000000" }
                            GradientStop { position: 1.0; color: "#a6000000" }
                        }
                    }
                }

                // ---- art + badge + text + transport
                RoundedImage {
                    id: bigArt
                    width: 64; height: 64; radius: 14
                    source: root.musicArt
                }
                // the player's own icon (Spotify, Brave, Firefox…); a note when the player has no app (iPhone)
                Item {
                    id: playerBadge
                    x: bigArt.width - 18; y: bigArt.height - 18
                    width: 26; height: 26
                    readonly property string entry: root.player ? (root.player.desktopEntry || "") : ""
                    readonly property string app: root.player ? (root.player.identity || "") : ""
                    readonly property bool known: entry !== "" || (app !== "" && DesktopEntries.heuristicLookup(app) !== null)
                    Rectangle {
                        anchors.fill: parent; anchors.margins: -2; radius: 9
                        color: "#141416"
                    }
                    AppIcon {
                        anchors.fill: parent
                        visible: playerBadge.known
                        size: 26
                        app: playerBadge.app
                        entry: playerBadge.entry
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !playerBadge.known
                        text: "󰝚"; color: "#f5f5f7"; font.family: root.iconFont; font.pixelSize: 14
                    }
                }
                Column {
                    anchors.left: bigArt.right; anchors.leftMargin: 16
                    anchors.right: transport.left; anchors.rightMargin: 12
                    anchors.verticalCenter: bigArt.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.musicTitle
                        color: "#ffffff"
                        font.family: root.textFont; font.pixelSize: 18; font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.musicArtist
                        color: Qt.rgba(1, 1, 1, 0.62)
                        font.family: root.textFont; font.pixelSize: 13
                    }
                }
                Row {
                    id: transport
                    anchors.right: parent.right; anchors.rightMargin: 4
                    anchors.verticalCenter: bigArt.verticalCenter
                    spacing: 22
                    Repeater {
                        model: [
                            { t: "󰒮", a: "prev" },
                            { t: root.player && root.player.isPlaying ? "󰏤" : "󰐊", a: "toggle" },
                            { t: "󰒭", a: "next" }
                        ].concat(root.canLike ? [{ t: root.like.liked ? "󰋑" : "󰋕", a: "like" }] : [])
                        Text {
                            id: tBtn
                            required property var modelData
                            text: modelData.t
                            color: modelData.a === "like" && root.like.liked ? "#1ed760" : "#ffffff"
                            font.family: root.iconFont; font.pixelSize: modelData.a === "toggle" ? 30 : 22
                            anchors.verticalCenter: parent.verticalCenter
                            scale: tArea.pressed ? 0.85 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 180 } }
                            MouseArea {
                                id: tArea
                                anchors.fill: parent; anchors.margins: -8
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (tBtn.modelData.a === "like") { root.toggleLike(); return; }
                                    if (!root.player) return;
                                    if (tBtn.modelData.a === "prev") root.player.previous();
                                    else if (tBtn.modelData.a === "next") root.player.next();
                                    else root.player.togglePlaying();
                                }
                            }
                        }
                    }
                }

                // ---- wavy progress
                Item {
                    id: wave
                    anchors.left: parent.left; anchors.right: parent.right
                    y: bigArt.height + 12; height: 18
                    readonly property real len: root.player && root.player.length > 0 ? root.player.length : 0
                    readonly property real pos: root.player ? root.player.position : 0
                    readonly property real frac: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0
                    property real phase: 0
                    FrameAnimation {
                        running: bigMusic.on && root.player !== null && root.player.isPlaying
                        onTriggered: { wave.phase = (wave.phase + frameTime * 6) % (Math.PI * 2); waveCanvas.requestPaint(); }
                    }
                    onFracChanged: waveCanvas.requestPaint()
                    Canvas {
                        id: waveCanvas
                        anchors.fill: parent
                        onPaint: {
                            const c = getContext("2d"); c.reset();
                            const w = width, h = height, mid = h / 2, x0 = w * wave.frac;
                            c.lineCap = "round"; c.lineWidth = 3;
                            c.strokeStyle = "rgba(255,255,255,0.22)";
                            c.beginPath(); c.moveTo(Math.min(w - 2, x0 + 6), mid); c.lineTo(w - 2, mid); c.stroke();
                            if (x0 > 3) {
                                const amp = root.player && root.player.isPlaying ? 3.2 : 0.8;
                                c.strokeStyle = Qt.rgba(Math.min(1, bigMusic.bright.r * 1.2 + 0.15), Math.min(1, bigMusic.bright.g * 1.2 + 0.15), Math.min(1, bigMusic.bright.b * 1.2 + 0.15), 1);
                                c.beginPath();
                                for (let x = 2; x <= x0; x += 1.5) {
                                    const y = mid + Math.sin(x / 6 - wave.phase) * amp;
                                    if (x === 2) c.moveTo(x, y); else c.lineTo(x, y);
                                }
                                c.stroke();
                            }
                        }
                    }
                    Rectangle {   // knob
                        x: Math.max(0, wave.width * wave.frac - 2); anchors.verticalCenter: parent.verticalCenter
                        width: 4; height: 16; radius: 2; color: "#ffffff"
                    }
                    MouseArea {   // seek
                        anchors.fill: parent; anchors.topMargin: -4; anchors.bottomMargin: -4
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.player !== null && root.player.canSeek && wave.len > 0
                        onClicked: m => { root.player.position = wave.len * Math.max(0, Math.min(1, m.x / width)); }
                    }
                }

                // ---- elapsed · lyrics · volume · remaining
                Item {
                    id: bottomRow
                    anchors.left: parent.left; anchors.right: parent.right
                    y: wave.y + wave.height + 6; height: 24
                    Text {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: bigMusic.clock(wave.pos)
                        color: Qt.rgba(1, 1, 1, 0.7); font.family: "Adwaita Mono"; font.pixelSize: 12
                    }
                    Text {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: wave.len > 0 ? "-" + bigMusic.clock(wave.len - wave.pos) : ""
                        color: Qt.rgba(1, 1, 1, 0.7); font.family: "Adwaita Mono"; font.pixelSize: 12
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter
                        spacing: 14
                        Rectangle {   // lyrics toggle
                            width: 26; height: 24; radius: 7
                            visible: root.cfg.showLyrics !== false
                            color: !root.musicLyricsHidden ? Qt.rgba(1, 1, 1, 0.22) : lyArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: "󰗚"; color: "#ffffff"; font.family: root.iconFont; font.pixelSize: 14 }
                            MouseArea { id: lyArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.musicLyricsHidden = !root.musicLyricsHidden }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: volTrack.level <= 0.001 ? "󰝟" : volTrack.level < 0.5 ? "󰖀" : "󰕾"
                            color: Qt.rgba(1, 1, 1, 0.8); font.family: root.iconFont; font.pixelSize: 14
                        }
                        Rectangle {
                            id: volTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: 120; height: 5; radius: 2.5; color: Qt.rgba(1, 1, 1, 0.22)
                            readonly property bool usePlayer: root.player !== null && root.player.volumeSupported
                            readonly property real level: usePlayer ? Math.max(0, Math.min(1, root.player.volume))
                                : (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Math.min(1, Pipewire.defaultAudioSink.audio.volume) : 0)
                            Rectangle { width: parent.width * volTrack.level; height: parent.height; radius: 2.5; color: "#ffffff" }
                            MouseArea {
                                anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                                cursorShape: Qt.PointingHandCursor
                                function apply(mx) {
                                    const v = Math.max(0, Math.min(1, mx / width));
                                    if (volTrack.usePlayer) root.player.volume = v;
                                    else if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) Pipewire.defaultAudioSink.audio.volume = v;
                                }
                                onPressed: m => apply(m.x)
                                onPositionChanged: m => { if (pressed) apply(m.x); }
                            }
                        }
                    }
                }

                Loader {
                    id: bigLyrics
                    anchors.left: parent.left; anchors.right: parent.right
                    y: bottomRow.y + bottomRow.height + 6
                    height: bigMusic.lyricsOn ? 38 : 0
                    active: bigMusic.on && bigMusic.lyricsOn
                    sourceComponent: Component {
                        IslandLyrics {
                            player: root.player
                            position: root.player ? root.player.position : 0
                            textFont: root.textFont
                        }
                    }
                }
                FrameAnimation {
                    running: bigMusic.on && root.player !== null && root.player.isPlaying
                    onTriggered: root.player.positionChanged()
                }
            }
            // Overview shares the island's shape, palette and expansion springs.
            // Double right-click: the tabbed hub (NotchHub.qml); the old Overview is its "Resumen" tab.
            NotchHub {
                id: hub
                anchors.fill: parent; anchors.margins: 24
                opened: win.viewMode === "overview"
                tab: root.hubTab
                onTabPicked: id => root.hubTab = id
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
                srpShell: root.srpShell
                notifItems: root.allItems
                timeAgo: ts => root.timeAgo(ts)
                onNotifClear: { root.srpCall("clear", []); root.listItems = []; root.activity = []; }
                onNotifRemoved: item => {
                    if (item.kind === "event") root.activity = root.activity.filter(x => x.id !== item.id);
                    else {
                        root.srpCall("dismiss", [item.uid]);
                        root.listItems = root.listItems.filter(x => x.uid !== item.uid);
                    }
                }
                onNotifActivated: item => {
                    if (item.kind === "event") { if (item.openPath) root.openPath(item.openPath, false); }
                    else root.srpCall("activate", [item.uid]);
                    root.compactOutside();
                }
                onOpenClipboardPanel: root.openClip()
                onDismissed: root.compactOutside()
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
                id: qaLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "qa"
                sourceComponent: Component {
                    QuickActions {
                        opened: root.qaOpen && win.isFocusedMonitor
                        glassTexture: backdropTexture
                        glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                        glassStrength: root.refraction
                        glassOrigin: Qt.point(pill.x + qaLoader.x, pill.y + qaLoader.y)
                        glassScreen: Qt.vector2d(win.width, win.height)
                        textFont: root.textFont; iconFont: root.iconFont
                        onDismissed: root.closeQa()
                    }
                }
            }
            Loader {
                id: clipLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "clip"
                sourceComponent: Component {
                    ClipboardPanel {
                        opened: root.clipOpen && win.isFocusedMonitor
                        glassTexture: backdropTexture
                        glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                        glassStrength: root.refraction
                        glassOrigin: Qt.point(pill.x + clipLoader.x, pill.y + clipLoader.y)
                        glassScreen: Qt.vector2d(win.width, win.height)
                        textFont: root.textFont; iconFont: root.iconFont
                        onDismissed: root.closeClip()
                    }
                }
            }
            Loader {
                id: trLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "tr"
                sourceComponent: Component {
                    TranslatorPanel {
                        opened: root.trOpen && win.isFocusedMonitor
                        textFont: root.textFont; iconFont: root.iconFont
                        onDismissed: root.closeTr()
                    }
                }
            }
            Loader {
                id: aiLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "ai"
                sourceComponent: Component {
                    AiPanel {
                        opened: root.aiOpen && win.isFocusedMonitor
                        glassTexture: backdropTexture
                        glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                        glassStrength: root.refraction
                        glassOrigin: Qt.point(pill.x + aiLoader.x, pill.y + aiLoader.y)
                        glassScreen: Qt.vector2d(win.width, win.height)
                        textFont: root.textFont; iconFont: root.iconFont
                        onDismissed: root.closeAi()
                    }
                }
            }
            Loader {
                id: ctrlLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "ctrl"
                sourceComponent: Component {
                    ControlPanel {
                        opened: root.ctrlOpen && win.isFocusedMonitor
                        glassTexture: backdropTexture
                        glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                        glassStrength: root.refraction
                        glassOrigin: Qt.point(pill.x + ctrlLoader.x, pill.y + ctrlLoader.y)
                        glassScreen: Qt.vector2d(win.width, win.height)
                        textFont: root.textFont; iconFont: root.iconFont
                        onPickingChanged: root.ctrlPicking = picking
                        glowRadius: pill.radius
                        onDismissed: root.closeCtrl()
                    }
                }
            }
            Loader {
                id: emojiLoader
                anchors.fill: parent; anchors.margins: 24
                active: win.viewMode === "emoji"
                sourceComponent: Component {
                    EmojiPanel {
                        opened: root.emojiOpen && win.isFocusedMonitor
                        glassTexture: backdropTexture
                        glassEnabled: pill.glassOn && snap.hasContent && root.refraction > 0
                        glassStrength: root.refraction
                        glassOrigin: Qt.point(pill.x + emojiLoader.x, pill.y + emojiLoader.y)
                        glassScreen: Qt.vector2d(win.width, win.height)
                        textFont: root.textFont; iconFont: root.iconFont
                        onDismissed: root.closeEmoji()
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
                        textFont: root.textFont; iconFont: root.iconFont
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
                    if (!root.shelfOpen && !root.listOpen && !root.overviewOpen && !root.clipOpen && !root.emojiOpen && !root.aiOpen && !root.trOpen && !root.ctrlOpen && !root.qaOpen && root.current) {
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

    // Emoji picker when the island is off: same panel, solid black rounded window centred on the focused
    // screen (like Caelestia's picker). Sized to the panel only, so the rest of the desktop keeps its input.
    PanelWindow {
        id: emojiWin
        readonly property var focusedScreen: {
            const fm = Hyprland.focusedMonitor;
            return (fm ? Quickshell.screens.find(x => x.name === fm.name) : null) || Quickshell.screens[0];
        }
        screen: emojiWin.focusedScreen
        visible: root.emojiOpen && root.cfg.enabled === false
        WlrLayershell.namespace: "astrax-emoji"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: emojiWin.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 540
        implicitHeight: 458

        Connections {
            target: root
            function onDesktopClicked(desktopX, desktopY) {
                if (!emojiWin.visible || !emojiWin.screen) return;
                const left = emojiWin.screen.x + (emojiWin.screen.width - emojiWin.width) / 2;
                const top = emojiWin.screen.y + (emojiWin.screen.height - emojiWin.height) / 2;
                if (desktopX < left || desktopX > left + emojiWin.width || desktopY < top || desktopY > top + emojiWin.height)
                    root.closeEmoji();
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 34; color: "#000000"
            border.width: 1; border.color: "#1affffff"
            Loader {
                anchors.fill: parent; anchors.margins: 24
                active: emojiWin.visible
                sourceComponent: Component {
                    EmojiPanel {
                        opened: root.emojiOpen
                        textFont: root.textFont; iconFont: root.iconFont
                        onDismissed: root.closeEmoji()
                    }
                }
            }
        }
    }
}
