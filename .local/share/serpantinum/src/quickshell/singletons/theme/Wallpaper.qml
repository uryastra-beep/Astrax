pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    signal wallpaperChanged(string screenName, string path, string transition)
    signal playbackChanged(string screenName, string state)
    signal wallpaperCleared(string screenName)

    property var screenWallpapers: ({})
    property var screenWallpaperPaths: ({})
    property var engines: ({})

    function registerEngine(screenName: string, engine: var): void {
        if (!screenName) return;
        let map = Object.assign({}, root.engines);
        map[screenName] = engine;
        root.engines = map;
    }

    function unregisterEngine(screenName: string, engine: var): void {
        if (!screenName || root.engines[screenName] !== engine) return;
        let map = Object.assign({}, root.engines);
        delete map[screenName];
        root.engines = map;
    }

    // Which screens have a VIDEO wallpaper set right now (not a
    // static image) -- updated by WallpaperEngine.qml for each
    // instance (one per monitor). ThemeBackend uses it to react to the
    // song color ONLY when at least one animated wallpaper is
    // set (don't touch the theme if the background is static).
    property var screenIsVideo: ({})
    readonly property bool anyVideoActive: {
        let keys = Object.keys(root.screenIsVideo);
        for (let i = 0; i < keys.length; i++) {
            if (root.screenIsVideo[keys[i]]) return true;
        }
        return false;
    }

    // WORT: when Serpantinum starts and the saved wallpaper is lava-live, start the lava again
    Timer {
        id: lavaBootTimer
        interval: 4000
        running: true
        onTriggered: Quickshell.execDetached(["sh", "-c",
            "grep -q lava-live \"$HOME\"/.cache/serpantinum/wallpaper/current_* 2>/dev/null && lava-wallpaper on"])
    }

    Timer {
        id: lavaPauseTimer
        interval: 1500
        onTriggered: root.setPlayback("all", "pause")
    }

    function setWallpaper(screenName: string, path: string, transition: string): void {
        // WORT ("lava-live"): the lava-live.* file is only a placeholder/thumbnail
        let isLava = (path || "").split("/").pop().toLowerCase().indexOf("lava-live") === 0;
        Quickshell.execDetached(["lava-wallpaper", isLava ? "on" : "off"]);
        root.wallpaperChanged(screenName, path, transition ? transition : "fade");
        // With the lava on, the placeholder video is paused (once loaded); any other wallpaper resumes it
        if (isLava) lavaPauseTimer.restart();
        else { lavaPauseTimer.stop(); root.setPlayback("all", "play"); }
    }

    function getWallpaper(screenName: string): string {
        if (!screenName || screenName === "") {
            let keys = Object.keys(root.screenWallpapers);
            return keys.length > 0 ? root.screenWallpapers[keys[0]] : "";
        }
        return root.screenWallpapers[screenName] || "";
    }

    function getWallpaperPath(screenName: string): string {
        if (!screenName || screenName === "") {
            let keys = Object.keys(root.screenWallpaperPaths);
            return keys.length > 0 ? root.screenWallpaperPaths[keys[0]] : "";
        }
        return root.screenWallpaperPaths[screenName] || "";
    }

    function setPlayback(screenName: string, state: string): void {
        root.playbackChanged(screenName, state);
    }

    function clearWallpaper(screenName: string): void {
        root.wallpaperCleared(screenName);
    }

    IpcHandler {
        target: "wallpaper"

        function setWallpaper(screenName: string, path: string, transition: string): void {
            root.setWallpaper(screenName, path, transition);
        }

        function getWallpaper(screenName: string): string {
            return root.getWallpaper(screenName);
        }

        function getWallpaperPath(screenName: string): string {
            return root.getWallpaperPath(screenName);
        }

        function setPlayback(screenName: string, state: string): void {
            root.setPlayback(screenName, state);
        }

        function clearWallpaper(screenName: string): void {
            root.clearWallpaper(screenName);
        }
    }
}
