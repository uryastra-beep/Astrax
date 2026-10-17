import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtMultimedia
import Quickshell.Hyprland
import "../"

ShellRoot {
    id: globalRoot

    // Global wallpaper audio toggle (CTRL+SUPER+S). We added an
    // AudioOutput to the MediaPlayers because they had none (that's why they
    // were silent); this mutes that audio, not the system.
    property bool audioMuted: true

    // Persisted to disk so external scripts (e.g. border_colors.py)
    // know whether the wallpaper "sound mode" is on -- this used to
    // live ONLY in this QML process's memory, with no way to query it
    // from outside (the IpcHandler below only had toggle(), no
    // getter). Widgets reacting to the wallpaper should only
    // "detect" it while this mode is on.
    FileView {
        id: audioStateFile
        path: `${Quickshell.env("HOME")}/.local/state/serpantinum/wallpaper_audio_muted`
        printErrors: false
    }
    function persistAudioMuted() {
        audioStateFile.setText(globalRoot.audioMuted ? "1" : "0");
    }
    onAudioMutedChanged: persistAudioMuted()
    Component.onCompleted: persistAudioMuted()

    // Registry of per-screen instances (one per monitor, via the Variants
    // below) so the video position can be synced between p1/p2
    // when they share the same wallpaper -- see hasAppOnThisScreen.
    property var wallpaperScreens: ({})

    // "floating"/"fullscreen" are NOT reactive properties exposed by
    // Quickshell.Hyprland (unlike .monitors/.workspaces, which really
    // are reactive) -- so to know whether an app covers the
    // wallpaper under the current rule (only pause with
    // 1+ TILED app or one in fullscreen; floating/empty/terminal/
    // widgets don't pause) we need to poll "hyprctl clients -j".
    // The rest (which workspace each screen is on) stays 100% reactive
    // via Hyprland.monitors -- this only provides floating/fullscreen per
    // client.
    property var clientsInfo: []

    Process {
        id: clientsPoller
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let arr = JSON.parse(text);
                    globalRoot.clientsInfo = arr.map(c => ({
                        wclass: c.class,
                        floating: !!c.floating,
                        fullscreen: c.fullscreen || 0,
                        workspaceId: c.workspace ? c.workspace.id : -1
                    }));
                } catch (e) {}
            }
        }
    }
    // before: polled every 1s (one hyprctl + JSON per second forever).
    // Now it's only requested when Hyprland reports a window change
    // (with a small debounce), plus a slow fallback poll every 10s.
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clientsPoller.running = true
    }
    Timer {
        id: clientsDebounce
        interval: 120
        onTriggered: clientsPoller.running = true
    }
    readonly property var clientEvents: ["openwindow", "closewindow", "movewindow", "movewindowv2",
        "changefloatingmode", "fullscreen", "workspace", "workspacev2", "focusedmon", "moveworkspace", "moveworkspacev2"]
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (globalRoot.clientEvents.indexOf(event.name) !== -1) clientsDebounce.restart();
        }
    }

    // astrax-power-wave cover (outro / `outro per`): the screen isn't visible,
    // so the video pauses. The daemon writes 1/0 to this file.
    FileView {
        id: astraxCoverFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/astrax-covered"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property bool astraxCovered: astraxCoverFile.text().trim() === "1"

    IpcHandler {
        target: "wallpaperAudio"

        function toggle(): string {
            globalRoot.audioMuted = !globalRoot.audioMuted;
            return globalRoot.audioMuted ? "muted" : "unmuted";
        }
    }

    // Global toggle (CTRL+SUPER+A): when on, the video wallpaper
    // keeps playing and stays VISIBLE even if an app covers the screen -- by
    // default (off) it pauses and gets covered by the static snapshot, as
    // usual.
    property bool forceAnimatedThroughApps: false

    IpcHandler {
        target: "wallpaperKeepAnimated"

        function toggle(): string {
            globalRoot.forceAnimatedThroughApps = !globalRoot.forceAnimatedThroughApps;
            return globalRoot.forceAnimatedThroughApps ? "animated" : "static";
        }
    }

    // Global toggle (CTRL+SUPER+SHIFT+S): when on, the wallpaper sound
    // keeps playing even if app(s) cover the screen(s)
    // -- independent from forceAnimatedThroughApps (you can have the video
    // paused/covered by an app and still force it to keep playing). The
    // fixed p1-first priority (see eligibleForAudio/playsAudio below)
    // doesn't change: if p1 has a video wallpaper set, it's still the
    // one playing.
    property bool forceAudioThroughApps: false

    IpcHandler {
        target: "wallpaperAudioThroughApps"

        function toggle(): string {
            globalRoot.forceAudioThroughApps = !globalRoot.forceAudioThroughApps;
            return globalRoot.forceAudioThroughApps ? "on" : "off";
        }
    }

    Variants {
        id: root
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: barWindow

                required property var modelData
                screen: modelData

                WlrLayershell.namespace: "wallpaper-bg"
                WlrLayershell.layer: WlrLayer.Background

                focusable: false
                exclusionMode: ExclusionMode.Ignore
                color: "#0a0a0f"

                anchors { top: true; bottom: true; left: true; right: true }

                readonly property string wpCacheDir: Caching.getCacheDir("wallpaper")
                readonly property string wpStatePath: wpCacheDir + "/current_" + barWindow.screen.name
                readonly property string wpCopyDir: wpCacheDir + "/copy_" + barWindow.screen.name
                readonly property string wpSnapshotPath: wpCacheDir + "/current_wallpaper.png"
                readonly property string wpMonitorSnapshotPath: wpCacheDir + "/current_wallpaper_" + barWindow.screen.name + ".png"

                property string currentWallpaperPath: ""
                property string originalFileName: ""
                property int activeLayer: 0
                property string pathA: ""
                property bool isVideoA: false
                property string pathB: ""
                property bool isVideoB: false
                property bool playbackPaused: false
                property bool snapReadyA: false
                property bool snapReadyB: false
                property int snapRevA: 0
                property int snapRevB: 0
                readonly property string layerSnapshotPathA: wpCacheDir + "/layer_" + barWindow.screen.name + "_a.png"
                readonly property string layerSnapshotPathB: wpCacheDir + "/layer_" + barWindow.screen.name + "_b.png"

                // Pauses/resumes the video wallpaper ONLY ON THIS screen
                // with an explicit rule: it RUNS if the
                // screen is empty, if all the apps on it are
                // floating and none is fullscreen, or if the only thing present
                // is the terminal/custom widgets. It does NOT run (pauses) if there's 1+
                // TILED app or any app in fullscreen (regardless of
                // floating). The workspace-per-screen is truly reactive
                // (Quickshell.Hyprland); floating/fullscreen aren't,
                // so those two come from globalRoot.clientsInfo
                // (poll of "hyprctl clients -j", see above).
                //
                // Classes that DON'T count as "app covering the screen": the
                // terminal (kitty, without --class = class "kitty") and the
                // custom widgets (widgets 1-3 and widgets4), which are overlays
                // meant to live with the wallpaper, not cover it.
                readonly property var ignoredWallpaperClasses: [
                    "kitty",
                    "widget-clock", "widget-clock-ghost",
                    "widget-cava", "widget-cava-ghost", "widget-lavat",
                    "widget4-term", "widget4-btop", "widget4-unimatrix", "widget4-lavat"
                ]

                readonly property bool hasAppOnThisScreen: {
                    if (globalRoot.astraxCovered) return true;
                    if (typeof Hyprland === "undefined") return false;
                    if (!barWindow.screen || !Hyprland.monitors || !Hyprland.monitors.values) return false;
                    let mon = Hyprland.monitors.values.find(m => m.name === barWindow.screen.name);
                    if (!mon || !mon.activeWorkspace) return false;
                    let wsId = mon.activeWorkspace.id;

                    let relevant = globalRoot.clientsInfo.filter(c => {
                        if (c.workspaceId !== wsId) return false;
                        return barWindow.ignoredWallpaperClasses.indexOf(c.wclass) === -1;
                    });
                    if (relevant.length === 0) return false;

                    return relevant.some(c => c.fullscreen !== 0) || relevant.some(c => !c.floating);
                }

                // Periodic drift correction: the sync above only
                // happens ONCE when a screen is freed; after that each
                // MediaPlayer runs on its own clock and they slowly
                // drift apart (found live: 0.5-1s noticeable at times).
                // Every 3s, if two free screens share the same video
                // and drifted more than 200ms, they're realigned. The
                // "names[i] < screen.name" check makes only ONE screen
                // of the pair correct (so they don't push each other).
                Timer {
                    interval: 3000
                    running: true
                    repeat: true
                    onTriggered: {
                        if (barWindow.hasAppOnThisScreen) return;
                        let myPath = barWindow.currentVideoPath();
                        if (!myPath) return;
                        let names = Object.keys(globalRoot.wallpaperScreens);
                        for (let i = 0; i < names.length; i++) {
                            if (names[i] === barWindow.screen.name) continue;
                            if (names[i] < barWindow.screen.name) continue;
                            let other = globalRoot.wallpaperScreens[names[i]];
                            if (other && !other.hasAppOnThisScreen && other.currentVideoPath() === myPath) {
                                let diff = Math.abs(barWindow.currentPosition() - other.currentPosition());
                                if (diff > 200) {
                                    barWindow.seekActive(other.currentPosition());
                                }
                                break;
                            }
                        }
                    }
                }

                // Only the layer (A or B) that is active AND is a video
                // counts as "playing video now" (the other layer may be
                // a static transition image).
                readonly property bool hasVideoNow: (barWindow.activeLayer === 0 && barWindow.isVideoA) || (barWindow.activeLayer === 1 && barWindow.isVideoB)

                // Can play sound: free (no app covering it) and with a video set
                // right now -- or, if CTRL+SUPER+SHIFT+S is active
                // (forceAudioThroughApps), regardless of app(s)
                // covering it (both screens busy included).
                readonly property bool eligibleForAudio: (globalRoot.forceAudioThroughApps || !barWindow.hasAppOnThisScreen) && barWindow.hasVideoNow

                // FIXED priority for audio (replaces
                // the previous focus-based rule): p1 (eDP-1) always wins
                // when it can play -- even if p2 is free too, p1 keeps
                // playing (focus alone doesn't "steal" the audio). p2 only
                // plays when p1 CAN'T (covered by a real app, or
                // no video wallpaper set). If neither can,
                // neither plays (there's no video wallpaper visible on
                // any screen in that case).
                readonly property bool playsAudio: {
                    if (!barWindow.eligibleForAudio) return false;
                    if (barWindow.screen.name === "eDP-1") return true;
                    let p1 = globalRoot.wallpaperScreens["eDP-1"];
                    return !(p1 && p1.eligibleForAudio);
                }

                onHasAppOnThisScreenChanged: {
                    // pause() instead of stop(): stop() reset the frame and
                    // left the screen black (found live).
                    // pause() keeps the last frame, and it's also covered by
                    // the static snapshot (fallbackStaticWallpaper) in the
                    // meantime. CTRL+SUPER+A (forceAnimatedThroughApps) skips
                    // all of this -- the video keeps playing/showing with
                    // an app on top.
                    if (hasAppOnThisScreen) {
                        if (globalRoot.forceAnimatedThroughApps) return;
                        if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.pauseA();
                        if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.pauseB();
                        return;
                    }

                    // When freed: if ANOTHER screen has exactly
                    // the SAME wallpaper set and is free (not covered) right
                    // now, that one is the time reference (it has been free
                    // longer, either because it was never covered or because it was
                    // freed before this one) -- jump to its position before
                    // resuming. If both share the wallpaper but the other one is
                    // ALSO covered, there's nothing to sync with yet
                    // (it'll happen when the other one is freed and uses us
                    // as the reference).
                    let myPath = barWindow.currentVideoPath();
                    if (myPath) {
                        let names = Object.keys(globalRoot.wallpaperScreens);
                        for (let i = 0; i < names.length; i++) {
                            if (names[i] === barWindow.screen.name) continue;
                            let other = globalRoot.wallpaperScreens[names[i]];
                            if (other && !other.hasAppOnThisScreen && other.currentVideoPath() === myPath) {
                                barWindow.seekActive(other.currentPosition());
                                break;
                            }
                        }
                    }

                    if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                    if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                }

                // Reacts IMMEDIATELY to the bind (not only the next time an app
                // covers/uncovers): if an app is covering right now,
                // resumes or pauses again according to the toggle's new state.
                Connections {
                    target: globalRoot
                    function onForceAnimatedThroughAppsChanged() {
                        if (!barWindow.hasAppOnThisScreen) return;
                        if (globalRoot.forceAnimatedThroughApps) {
                            if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                            if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                        } else {
                            if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.pauseA();
                            if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.pauseB();
                        }
                    }
                }

                readonly property int fadeDuration: 1000
                readonly property int maskDuration: 1600
                property real transitionProgress: 1.0
                property bool isPreloading: false
                property int activeTransitionType: 0
                property bool wipeIsVertical: false
                property int swipeDirection: 0
                property real transitionOriginX: 0.5
                property real transitionOriginY: 0.5
                property bool isInitialLoad: true

                Component.onCompleted: {
                    restorePoller.running = true;
                    Wallpaper.registerEngine(barWindow.screen ? barWindow.screen.name : "", barWindow);
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, globalRoot.wallpaperScreens);
                        map[barWindow.screen.name] = barWindow;
                        globalRoot.wallpaperScreens = map;

                        let videoMap = Object.assign({}, Wallpaper.screenIsVideo);
                        videoMap[barWindow.screen.name] = barWindow.hasVideoNow;
                        Wallpaper.screenIsVideo = videoMap;
                    }
                }

                Component.onDestruction: Wallpaper.unregisterEngine(barWindow.screen ? barWindow.screen.name : "", barWindow)

                onCurrentWallpaperPathChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpaperPaths);
                        map[barWindow.screen.name] = currentWallpaperPath;
                        Wallpaper.screenWallpaperPaths = map;
                    }
                }

                onHasVideoNowChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenIsVideo);
                        map[barWindow.screen.name] = barWindow.hasVideoNow;
                        Wallpaper.screenIsVideo = map;
                    }
                }

                onOriginalFileNameChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpapers);
                        map[barWindow.screen.name] = originalFileName;
                        Wallpaper.screenWallpapers = map;
                    }
                }

                Connections {
                    target: Wallpaper

                    function onWallpaperChanged(screenName, path, transition) {
                        if (screenName === "all" || screenName === barWindow.screen.name)
                            barWindow.changeWallpaper(path, transition);
                    }

                    function onPlaybackChanged(screenName, state) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            if (state === "pause") {
                                barWindow.playbackPaused = true;
                                barWindow.stopA();
                                barWindow.stopB();
                            } else if (state === "play") {
                                barWindow.playbackPaused = false;
                                if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                                if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                            }
                        }
                    }

                    function onWallpaperCleared(screenName) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            barWindow.currentWallpaperPath = "";
                            barWindow.pathA = "";
                            barWindow.pathB = "";
                            barWindow.isVideoA = false;
                            barWindow.isVideoB = false;
                            barWindow.originalFileName = "";
                            barWindow.stopA();
                            barWindow.stopB();
                            Quickshell.execDetached(["bash", "-c", "rm -f '" + barWindow.wpStatePath + "' '" + barWindow.wpStatePath + "_name'"]);
                        }
                    }
                }

                Process {
                    id: restorePoller
                    running: false
                    command: [
                        "bash", "-c",
                        "F1='" + barWindow.wpStatePath + "'; F2='" + barWindow.wpStatePath + "_name'; [ -f \"$F1\" ] && cat \"$F1\" || true; echo '---SPLIT---'; [ -f \"$F2\" ] && cat \"$F2\" || true"
                    ]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let parts = this.text.split("---SPLIT---");
                            let savedPath = parts[0] ? parts[0].trim() : "";
                            let savedName = parts[1] ? parts[1].trim() : "";
                            if (savedPath !== "") {
                                barWindow.originalFileName = savedName;
                                barWindow._loadNew(savedPath, false);
                                if (barWindow.isVideo(savedPath)) {
                                    videoSnapshotProcess.targetPath = savedPath;
                                    videoSnapshotProcess.running = false;
                                    videoSnapshotProcess.running = true;
                                }
                                if (savedName !== "") {
                                    let histFile = barWindow.wpCacheDir + "/history.txt";
                                    // file names go in as arguments ($1/$2), never into the
                                    // script text: a name with quotes can't inject shell code
                                    Quickshell.execDetached(["bash", "-c",
                                        'HIST="$1"; NAME="$2"; if [ -f "$HIST" ]; then if [ "$(head -n 1 "$HIST" 2>/dev/null)" != "$NAME" ]; then grep -v -F -x -- "$NAME" "$HIST" > "$HIST.tmp" 2>/dev/null || true; printf "%s\\n" "$NAME" | cat - "$HIST.tmp" > "$HIST"; rm -f "$HIST.tmp"; fi; else printf "%s\\n" "$NAME" > "$HIST"; fi',
                                        "_", histFile, savedName
                                    ]);
                                }
                            }
                        }
                    }
                }

                Timer {
                    id: videoWarmUpTimer
                    interval: 250
                    repeat: false
                    onTriggered: barWindow.triggerTransition()
                }

                Process {
                    id: layerSnapshotA
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null",
                        "_",
                        targetPath,
                        barWindow.layerSnapshotPathA
                    ]
                    onExited: exitCode => {
                        if (exitCode === 0) {
                            barWindow.snapReadyA = true;
                            barWindow.snapRevA++;
                        }
                    }
                }

                Process {
                    id: layerSnapshotB
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null",
                        "_",
                        targetPath,
                        barWindow.layerSnapshotPathB
                    ]
                    onExited: exitCode => {
                        if (exitCode === 0) {
                            barWindow.snapReadyB = true;
                            barWindow.snapRevB++;
                        }
                    }
                }

                Process {
                    id: videoSnapshotProcess
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null; cp -f \"$2\" \"$3\" 2>/dev/null || true",
                        "_",
                        targetPath,
                        barWindow.wpSnapshotPath,
                        barWindow.wpMonitorSnapshotPath
                    ]
                    onExited: exitCode => {
                        if (exitCode === 0 && typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                            Matugen.generate(barWindow.wpSnapshotPath);
                        }
                    }
                }

                function snapshotLayer(slot, path) {
                    let proc = slot === 0 ? layerSnapshotA : layerSnapshotB;
                    if (slot === 0) barWindow.snapReadyA = false;
                    else barWindow.snapReadyB = false;
                    proc.targetPath = path;
                    proc.running = false;
                    proc.running = true;
                }

                function isVideo(p) {
                    let lp = p.toLowerCase();
                    return lp.endsWith(".mp4") || lp.endsWith(".mkv") ||
                           lp.endsWith(".mov") || lp.endsWith(".webm");
                }

                function isSupportedMedia(p) {
                    if (!p) return false;
                    let lp = p.toLowerCase();
                    return lp.endsWith(".jpg") || lp.endsWith(".jpeg") || lp.endsWith(".png") ||
                           lp.endsWith(".webp") || lp.endsWith(".gif") || lp.endsWith(".bmp") ||
                           lp.endsWith(".avif") || barWindow.isVideo(p);
                }

                function playA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.play === "function") {
                        videoLoaderA.item.play();
                    }
                }

                function stopA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.stop === "function") {
                        videoLoaderA.item.stop();
                    }
                }

                function pauseA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.pause === "function") {
                        videoLoaderA.item.pause();
                    }
                }

                function playB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.play === "function") {
                        videoLoaderB.item.play();
                    }
                }

                function stopB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.stop === "function") {
                        videoLoaderB.item.stop();
                    }
                }

                function pauseB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.pause === "function") {
                        videoLoaderB.item.pause();
                    }
                }

                // Path of the video shown RIGHT NOW (activeLayer),
                // empty if it isn't a video. Used to know whether another screen
                // has the SAME wallpaper set (sync only applies there).
                function currentVideoPath() {
                    if (barWindow.activeLayer === 0 && barWindow.isVideoA) return barWindow.pathA;
                    if (barWindow.activeLayer === 1 && barWindow.isVideoB) return barWindow.pathB;
                    return "";
                }

                function currentPosition() {
                    if (barWindow.activeLayer === 0 && videoLoaderA.item) return videoLoaderA.item.position || 0;
                    if (barWindow.activeLayer === 1 && videoLoaderB.item) return videoLoaderB.item.position || 0;
                    return 0;
                }

                function seekActive(ms) {
                    if (barWindow.activeLayer === 0 && videoLoaderA.item && typeof videoLoaderA.item.seek === "function") {
                        videoLoaderA.item.seek(ms);
                    } else if (barWindow.activeLayer === 1 && videoLoaderB.item && typeof videoLoaderB.item.seek === "function") {
                        videoLoaderB.item.seek(ms);
                    }
                }

                function triggerTransition() {
                    videoWarmUpTimer.stop();
                    barWindow.isPreloading = false;
                    transitionAnim.restart();
                }

                function _loadNew(path, force) {
                    if (!path) return;
                    if (!force && path === barWindow.currentWallpaperPath) return;

                    let cleanPath = String(path).trim();
                    let vid = barWindow.isVideo(cleanPath);
                    if (vid) barWindow.snapshotLayer(barWindow.activeLayer === 1 ? 0 : 1, cleanPath);

                    let slash = cleanPath.lastIndexOf("/");
                    let filename = cleanPath.substring(slash + 1);
                    if (!filename.startsWith("wallpaper.")) {
                        barWindow.originalFileName = filename;
                    }

                    if (barWindow.isInitialLoad) {
                        barWindow.isInitialLoad = false;
                        barWindow.transitionProgress = 1.0;
                        barWindow.isPreloading = false;
                        if (barWindow.activeLayer === 1) {
                            barWindow.pathA = cleanPath;
                            barWindow.isVideoA = vid;
                            barWindow.activeLayer = 0;
                            if (vid) barWindow.playA();
                        } else {
                            barWindow.pathB = cleanPath;
                            barWindow.isVideoB = vid;
                            barWindow.activeLayer = 1;
                            if (vid) barWindow.playB();
                        }
                        barWindow.currentWallpaperPath = cleanPath;
                        return;
                    }

                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    barWindow.transitionProgress = 0.0;
                    barWindow.isPreloading = true;

                    if (barWindow.activeLayer === 1) {
                        barWindow.pathA = cleanPath;
                        barWindow.isVideoA = vid;
                        barWindow.activeLayer = 0;
                        if (vid) {
                            barWindow.playA();
                            videoWarmUpTimer.restart();
                        } else {
                            barWindow.triggerTransition();
                        }
                    } else {
                        barWindow.pathB = cleanPath;
                        barWindow.isVideoB = vid;
                        barWindow.activeLayer = 1;
                        if (vid) {
                            barWindow.playB();
                            videoWarmUpTimer.restart();
                        } else {
                            barWindow.triggerTransition();
                        }
                    }

                    barWindow.currentWallpaperPath = cleanPath;
                }

                function changeWallpaper(path, ttype) {
                    if (!path) return;

                    let isInterrupted = transitionAnim.running && barWindow.transitionProgress > 0.1 && barWindow.transitionProgress < 0.85;

                    barWindow.isInitialLoad = false;

                    let fromMenu = false;
                    let customOriginX = -1;
                    let customOriginY = -1;
                    let chosenType = -1;

                    if (typeof ttype === "object" && ttype !== null) {
                        if (ttype.type !== undefined) chosenType = Number(ttype.type);
                        if (ttype.originX !== undefined) customOriginX = Number(ttype.originX);
                        if (ttype.originY !== undefined) customOriginY = Number(ttype.originY);
                        fromMenu = true;
                    } else if (typeof ttype === "string" && ttype.indexOf("circle") !== -1) {
                        chosenType = 2;
                        let parts = ttype.split(":");
                        if (parts.length >= 3) {
                            customOriginX = parseFloat(parts[1]);
                            customOriginY = parseFloat(parts[2]);
                        }
                        fromMenu = true;
                    } else if (typeof ttype === "number" && ttype >= 0) {
                        chosenType = ttype;
                    }

                    if (typeof DesktopMenuController !== "undefined" && DesktopMenuController.isMenuShuffle) {
                        let isTargetScreen = !DesktopMenuController.screen || !DesktopMenuController.screen.name || (barWindow.screen && DesktopMenuController.screen.name === barWindow.screen.name);
                        if (isTargetScreen) {
                            fromMenu = true;
                            chosenType = 2;
                            customOriginX = DesktopMenuController.menuOriginX;
                            customOriginY = DesktopMenuController.menuOriginY;
                        }
                    }

                    if (isInterrupted) {
                        barWindow.activeTransitionType = 0;
                    } else if (chosenType >= 0) {
                        barWindow.activeTransitionType = chosenType;
                    } else {
                        barWindow.activeTransitionType = Math.floor(Math.random() * 4);
                    }

                    barWindow.wipeIsVertical = Math.random() < 0.5;
                    barWindow.swipeDirection = Math.floor(Math.random() * 8);

                    if (fromMenu && customOriginX >= 0 && customOriginY >= 0) {
                        barWindow.transitionOriginX = customOriginX;
                        barWindow.transitionOriginY = customOriginY;
                    } else {
                        barWindow.transitionOriginX = 0.15 + Math.random() * 0.70;
                        barWindow.transitionOriginY = 0.15 + Math.random() * 0.70;
                    }

                    if (typeof DesktopMenuController !== "undefined") {
                        DesktopMenuController.isMenuShuffle = false;
                    }

                    let cleanPath = String(path).trim();
                    let slash = cleanPath.lastIndexOf("/");
                    let origName = cleanPath.substring(slash + 1);
                    let dot = cleanPath.lastIndexOf(".");
                    let ext = (dot !== -1 && dot > slash) ? cleanPath.substring(dot) : "";
                    let dest = wpCopyDir + "/wallpaper" + ext;
                    let histFile = wpCacheDir + "/history.txt";
                    let vid = barWindow.isVideo(cleanPath);
                    let snapshotPath = barWindow.wpSnapshotPath;
                    let monSnapshotPath = barWindow.wpMonitorSnapshotPath;
                    // Every path/name is passed as a positional argument and only ever
                    // referenced quoted ("$2", ...) -- never concatenated into the script,
                    // so a wallpaper file name can't inject shell code.
                    Quickshell.execDetached(["bash", "-c",
                        'mkdir -p "$1" && printf "%s" "$2" > "$3" && printf "%s" "$4" > "${3}_name"' +
                        ' && cp -f -- "$2" "$5"' +
                        ' && { [ -n "$6" ] || { cp -f -- "$2" "$7" && cp -f -- "$2" "$8"; }; }' +
                        ' && ( HIST="$9"; if [ -f "$HIST" ]; then grep -v -F -x -- "$4" "$HIST" > "$HIST.tmp" 2>/dev/null || true; printf "%s\\n" "$4" | cat - "$HIST.tmp" > "$HIST"; rm -f "$HIST.tmp"; else printf "%s\\n" "$4" > "$HIST"; fi )',
                        "_", wpCopyDir, cleanPath, wpStatePath, origName, dest, vid ? "1" : "",
                        snapshotPath, monSnapshotPath, histFile
                    ]);

                    if (vid) {
                        videoSnapshotProcess.targetPath = cleanPath;
                        videoSnapshotProcess.running = false;
                        videoSnapshotProcess.running = true;
                    } else {
                        if (typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                            Matugen.generate(cleanPath);
                        }
                    }

                    barWindow._loadNew(cleanPath, true);
                }

                function handleDrop(drop) {
                    let raw = "";
                    if (drop.hasUrls && drop.urls.length > 0) {
                        raw = drop.urls[0].toString();
                    } else if (drop.hasText && drop.text.length > 0) {
                        let lines = drop.text.trim().split("\n");
                        raw = lines[0].trim();
                    }
                    if (!raw) return;

                    let cleanPath = decodeURIComponent(raw.replace(/^file:\/\//, "")).trim();
                    if (!barWindow.isSupportedMedia(cleanPath)) return;

                    let scrW = barWindow.width > 0 ? barWindow.width : (barWindow.screen && barWindow.screen.geometry ? barWindow.screen.geometry.width : 1920);
                    let scrH = barWindow.height > 0 ? barWindow.height : (barWindow.screen && barWindow.screen.geometry ? barWindow.screen.geometry.height : 1080);
                    let normX = scrW > 0 ? Math.max(0.0, Math.min(1.0, drop.x / scrW)) : 0.5;
                    let normY = scrH > 0 ? Math.max(0.0, Math.min(1.0, drop.y / scrH)) : 0.5;

                    barWindow.changeWallpaper(cleanPath, {
                        type: 2,
                        originX: normX,
                        originY: normY
                    });
                }

                NumberAnimation {
                    id: transitionAnim
                    target: barWindow
                    property: "transitionProgress"
                    from: 0.0
                    to: 1.0
                    duration: barWindow.activeTransitionType === 0 ? barWindow.fadeDuration : barWindow.maskDuration
                    easing.type: Easing.InOutCubic

                    onFinished: {
                        if (barWindow.activeLayer === 0) {
                            barWindow.stopB();
                            barWindow.pathB = "";
                            barWindow.isVideoB = false;
                        } else {
                            barWindow.stopA();
                            barWindow.pathA = "";
                            barWindow.isVideoA = false;
                        }
                    }
                }

                Component {
                    id: videoLayerCompA
                    Item {
                        anchors.fill: parent
                        function play() { playerA.play(); }
                        function stop() { playerA.stop(); }
                        function pause() { playerA.pause(); }
                        function seek(ms) { playerA.position = ms; }
                        readonly property alias position: playerA.position

                        AudioOutput {
                            id: audioOutputA
                            // Real BUG: pause() kept playing the audio.
                            // It's also muted while an app covers
                            // this screen (independent from the manual mute
                            // CTRL+SUPER+S), and if there's video on BOTH
                            // screens at once, only the focused one plays
                            // (Hyprland.focusedMonitor) so audio doesn't
                            // overlap.
                            muted: globalRoot.audioMuted || !barWindow.playsAudio
                            // Real BUG: the stream stayed stuck to the sink
                            // that was active when the shell started (the
                            // laptop speakers) and didn't move to the
                            // headphones when they were plugged in -- binding it to
                            // MediaDevices.defaultAudioOutput keeps it
                            // following the system default sink.
                            device: MediaDevices.defaultAudioOutput
                        }

                        MediaPlayer {
                            id: playerA
                            source: barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                            videoOutput: videoOutputA
                            audioOutput: audioOutputA
                            loops: MediaPlayer.Infinite
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    playerA.play();
                                }
                            }
                        }

                        // Real BUG (still happens even with audioOutputA.device
                        // bound to MediaDevices.defaultAudioOutput): the
                        // "device" binding updates the property, but
                        // QtMultimedia's ffmpeg backend doesn't reconnect an
                        // ALREADY OPEN stream to the new sink -- it stays stuck
                        // to the headphones/speaker that was active when
                        // the video started until restart. We force a short
                        // pause/play when the real system default output changes
                        // so it reopens the audio pipeline
                        // on the new sink.
                        Connections {
                            target: MediaDevices
                            function onDefaultAudioOutputChanged(): void {
                                if (playerA.playbackState === MediaPlayer.PlayingState) {
                                    playerA.pause();
                                    audioKickA.restart();
                                }
                            }
                        }
                        Timer { id: audioKickA; interval: 150; onTriggered: playerA.play() }

                        VideoOutput {
                            id: videoOutputA
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Component {
                    id: videoLayerCompB
                    Item {
                        anchors.fill: parent
                        function play() { playerB.play(); }
                        function stop() { playerB.stop(); }
                        function pause() { playerB.pause(); }
                        function seek(ms) { playerB.position = ms; }
                        readonly property alias position: playerB.position

                        AudioOutput {
                            id: audioOutputB
                            muted: globalRoot.audioMuted || !barWindow.playsAudio
                            device: MediaDevices.defaultAudioOutput
                        }

                        MediaPlayer {
                            id: playerB
                            source: barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                            videoOutput: videoOutputB
                            audioOutput: audioOutputB
                            loops: MediaPlayer.Infinite
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    playerB.play();
                                }
                            }
                        }

                        // same treatment as playerA (see the comment there).
                        Connections {
                            target: MediaDevices
                            function onDefaultAudioOutputChanged(): void {
                                if (playerB.playbackState === MediaPlayer.PlayingState) {
                                    playerB.pause();
                                    audioKickB.restart();
                                }
                            }
                        }
                        Timer { id: audioKickB; interval: 150; onTriggered: playerB.play() }

                        VideoOutput {
                            id: videoOutputB
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Item {
                    id: scene
                    anchors.fill: parent
                    clip: true

                    ShaderEffect {
                        id: transitionShaderA
                        anchors.fill: parent
                        visible: false
                        layer.enabled: layerA.layer.enabled

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real progress: barWindow.transitionProgress
                        property real transitionType: barWindow.activeTransitionType
                        property vector2d origin: Qt.vector2d(barWindow.transitionOriginX, barWindow.transitionOriginY)
                        property vector4d params: Qt.vector4d(barWindow.wipeIsVertical ? 1.0 : 0.0, barWindow.swipeDirection, 0.0, 0.0)

                        fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/transitions/wallpaper_transition.frag.qsb"
                    }

                    Item {
                        id: layerA
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 0
                        readonly property real p: barWindow.transitionProgress

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || p < 1.0

                        opacity: {
                            if (barWindow.isPreloading && isIncoming) return 0.0;
                            if (barWindow.activeTransitionType !== 0) return 1.0;
                            return isIncoming ? p : 1.0 - p;
                        }

                        layer.enabled: barWindow.activeTransitionType !== 0 && isIncoming && !barWindow.isPreloading && p < 1.0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: transitionShaderA
                            maskThresholdMin: 0.0
                            maskSpreadAtMin: 0.0
                        }

                        Image {
                            id: imgA
                            anchors.fill: parent
                            source: !barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoA && barWindow.pathA !== ""
                            cache: true
                            sourceSize.width: parent.width > 0 ? Math.ceil(parent.width * (Screen.devicePixelRatio || 1)) : 0
                            sourceSize.height: parent.height > 0 ? Math.ceil(parent.height * (Screen.devicePixelRatio || 1)) : 0
                        }

                        Loader {
                            id: videoLoaderA
                            anchors.fill: parent
                            active: barWindow.isVideoA && barWindow.pathA !== ""
                            asynchronous: false
                            sourceComponent: videoLayerCompA
                            visible: barWindow.isVideoA
                            onLoaded: {
                                if (item && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    item.play();
                                }
                            }
                        }
                    }

                    ShaderEffect {
                        id: transitionShaderB
                        anchors.fill: parent
                        visible: false
                        layer.enabled: layerB.layer.enabled

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real progress: barWindow.transitionProgress
                        property real transitionType: barWindow.activeTransitionType
                        property vector2d origin: Qt.vector2d(barWindow.transitionOriginX, barWindow.transitionOriginY)
                        property vector4d params: Qt.vector4d(barWindow.wipeIsVertical ? 1.0 : 0.0, barWindow.swipeDirection, 0.0, 0.0)

                        fragmentShader: "file://" + Caching.serpantinumDir + "/assets/shaders/transitions/wallpaper_transition.frag.qsb"
                    }

                    Item {
                        id: layerB
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 1
                        readonly property real p: barWindow.transitionProgress

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || p < 1.0

                        opacity: {
                            if (barWindow.isPreloading && isIncoming) return 0.0;
                            if (barWindow.activeTransitionType !== 0) return 1.0;
                            return isIncoming ? p : 1.0 - p;
                        }

                        layer.enabled: barWindow.activeTransitionType !== 0 && isIncoming && !barWindow.isPreloading && p < 1.0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: transitionShaderB
                            maskThresholdMin: 0.0
                            maskSpreadAtMin: 0.0
                        }

                        Image {
                            id: imgB
                            anchors.fill: parent
                            source: !barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoB && barWindow.pathB !== ""
                            cache: true
                            sourceSize.width: parent.width > 0 ? Math.ceil(parent.width * (Screen.devicePixelRatio || 1)) : 0
                            sourceSize.height: parent.height > 0 ? Math.ceil(parent.height * (Screen.devicePixelRatio || 1)) : 0
                        }

                        Loader {
                            id: videoLoaderB
                            anchors.fill: parent
                            active: barWindow.isVideoB && barWindow.pathB !== ""
                            asynchronous: false
                            sourceComponent: videoLayerCompB
                            visible: barWindow.isVideoB
                            onLoaded: {
                                if (item && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    item.play();
                                }
                            }
                        }
                    }
                }

                DropArea {
                    anchors.fill: parent

                    onEntered: drag => {
                        if (drag.hasUrls || drag.hasText) {
                            if (typeof drag.acceptProposedAction === "function") {
                                drag.acceptProposedAction();
                            } else if (typeof drag.accept === "function") {
                                drag.accept();
                            }
                            drag.accepted = true;
                        }
                    }

                    onDropped: drop => {
                        barWindow.handleDrop(drop);
                        if (typeof drop.acceptProposedAction === "function") {
                            drop.acceptProposedAction();
                        } else if (typeof drop.accept === "function") {
                            drop.accept();
                        }
                        drop.accepted = true;
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton | Qt.LeftButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                DesktopMenuController.toggle(barWindow.screen, mouse.x, mouse.y, "desktop");
                            } else {
                                DesktopMenuController.hide();
                            }
                        }
                    }
                }

                // Shown ON TOP of everything (declared after "scene")
                // while there's a real app on this screen AND the wallpaper
                // is a VIDEO: covers the paused video with this specific
                // still image (~/Pictures/Wallpapers/fallback.jpg, not the
                // auto-cached snapshot) instead of black. If the file is missing nothing is drawn.
                // Real BUG: this used to show with ANY
                // wallpaper (static too) as soon as an app covered the
                // screen, replacing the chosen static wallpaper with
                // this still image instead of leaving it as it was
                // -- added the missing hasVideoNow check.
                readonly property string fallbackStaticWallpaper: (Quickshell.env("HOME") || "") + "/Pictures/Wallpapers/fallback.jpg"
                // CTRL+SUPER+A (forceAnimatedThroughApps) skips the
                // fallback too -- the video stays VISIBLE through the
                // app, without being covered by this still image.
                readonly property bool showVideoFallback: !globalRoot.forceAnimatedThroughApps && barWindow.hasAppOnThisScreen && barWindow.hasVideoNow

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: barWindow.showVideoFallback
                    source: barWindow.showVideoFallback ? "file://" + barWindow.fallbackStaticWallpaper : ""
                }
            }
        }
    }
}
