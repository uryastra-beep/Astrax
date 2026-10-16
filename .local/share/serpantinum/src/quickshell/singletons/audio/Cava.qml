pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property int barCount: 64
    readonly property var emptyLevels: {
        let arr = [];
        for (let i = 0; i < barCount; i++) arr.push(0.0);
        return Object.freeze(arr);
    }
    property var barLevels: emptyLevels
    property int activeConsumers: 0
    property bool isPlaying: MprisController.isPlaying || Audio.hasActiveStream
    property bool isDecaying: false
    property bool hasActiveAudio: false
    property bool isRestarting: false
    property int consecutiveCrashes: 0
    // The wallpaper sound (CTRL+SUPER+S) isn't an MPRIS player, so
    // "isPlaying" alone never counted it -- the cava process never
    // started with the wallpaper playing and no Spotify/etc (the widgets
    // must react to the wallpaper audio too).
    // WallpaperEngine.qml persists its mute state here (see that file).
    property bool wallpaperAudioActive: false
    FileView {
        id: wallpaperAudioState
        path: `${Quickshell.env("HOME")}/.local/state/serpantinum/wallpaper_audio_muted`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.wallpaperAudioActive = text().trim() === "0"
    }
    property bool processEnabled: activeConsumers > 0 && (isPlaying || wallpaperAudioActive || isDecaying) && !isRestarting

    function registerConsumer() {
        activeConsumers++;
    }

    function unregisterConsumer() {
        activeConsumers = Math.max(0, activeConsumers - 1);
    }

    function resetBars() {
        root.barLevels = root.emptyLevels;
    }

    function restartCava() {
        if (!processEnabled || consecutiveCrashes >= 5) return;
        consecutiveCrashes++;
        isRestarting = true;
        restartTimer.restart();
    }

    onActiveConsumersChanged: {
        if (activeConsumers === 0) {
            root.isDecaying = false;
            decayTimer.stop();
        }
    }

    onIsPlayingChanged: {
        if (isPlaying) {
            root.isDecaying = false;
            decayTimer.stop();
        } else if (activeConsumers > 0) {
            root.isDecaying = true;
            decayTimer.restart();
        } else {
            root.isDecaying = false;
            decayTimer.stop();
            resetBars();
        }
    }

    // same treatment as onIsPlayingChanged above, for the other
    // source of "real audio playing" (the wallpaper, not MPRIS).
    onWallpaperAudioActiveChanged: {
        if (wallpaperAudioActive) {
            root.isDecaying = false;
            decayTimer.stop();
        } else if (activeConsumers > 0 && !isPlaying) {
            root.isDecaying = true;
            decayTimer.restart();
        }
    }

    onProcessEnabledChanged: {
        if (!processEnabled) {
            root.hasActiveAudio = false;
            root.consecutiveCrashes = 0;
            dataWatchdog.stop();
            resetBars();
        }
    }

    Timer {
        id: decayTimer
        interval: 1200
        repeat: false
        onTriggered: root.isDecaying = false
    }

    Timer {
        id: restartTimer
        interval: 500
        repeat: false
        onTriggered: root.isRestarting = false
    }

    Timer {
        id: dataWatchdog
        interval: 2500
        running: cavaProcess.running && (root.isPlaying || root.wallpaperAudioActive)
        repeat: false
        onTriggered: root.restartCava()
    }

    Process {
        id: cavaProcess
        running: root.processEnabled
        onExited: root.restartCava()
        command: [
            "bash", "-c",
            "exec cava -p <(printf '[general]\\nbars = %d\\nframerate = 60\\nsensitivity = 150\\n[input]\\nmethod = pulse\\nsource = easyeffects_sink.monitor\\n[output]\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 1000\\nbar_delimiter = 59\\n' " + root.barCount + ")"
        ]
        stdout: SplitParser {
            onRead: data => {
                if (!root.processEnabled) return;
                let str = data.trim();
                if (str.length === 0) return;
                root.consecutiveCrashes = 0;
                dataWatchdog.restart();

                let hasAudio = /[1-9]/.test(str);
                if (!hasAudio) {
                    if (root.hasActiveAudio) {
                        root.hasActiveAudio = false;
                        root.resetBars();
                    }
                    return;
                }

                root.hasActiveAudio = true;

                let parts = str.split(";");
                let count = Math.min(parts.length, root.barCount);
                let newLevels = new Array(root.barCount);
                for (let i = 0; i < root.barCount; i++) {
                    let val = i < count ? (parseInt(parts[i]) || 0) : 0;
                    newLevels[i] = Math.max(0.0, Math.min(1.0, val / 1000.0));
                }
                root.barLevels = newLevels;
            }
        }
    }
}
