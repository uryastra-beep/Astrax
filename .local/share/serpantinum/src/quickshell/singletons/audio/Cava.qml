pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property int barCount: 64
    property var barLevels: {
        let arr = [];
        for (let i = 0; i < barCount; i++) arr.push(0.0);
        return arr;
    }
    property int activeConsumers: 0
    property bool isPlaying: MprisController.isPlaying
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
    property bool isRestarting: false
    property bool processEnabled: activeConsumers > 0 && (isPlaying || wallpaperAudioActive || decayTimer.running) && !isRestarting

    function registerConsumer() {
        activeConsumers++;
    }

    function unregisterConsumer() {
        activeConsumers = Math.max(0, activeConsumers - 1);
    }

    function resetBars() {
        let empty = [];
        for (let i = 0; i < root.barCount; i++) {
            empty.push(0.0);
        }
        root.barLevels = empty;
    }

    function restartCava() {
        if (!processEnabled) return;
        isRestarting = true;
        restartTimer.restart();
    }

    onIsPlayingChanged: {
        if (isPlaying) {
            decayTimer.stop();
        } else if (activeConsumers > 0) {
            decayTimer.restart();
        } else {
            resetBars();
        }
    }

    // same treatment as onIsPlayingChanged above, for the other
    // source of "real audio playing" (the wallpaper, not MPRIS).
    onWallpaperAudioActiveChanged: {
        if (wallpaperAudioActive) {
            decayTimer.stop();
        } else if (activeConsumers > 0 && !isPlaying) {
            decayTimer.restart();
        }
    }

    onProcessEnabledChanged: {
        if (!processEnabled) {
            resetBars();
        }
    }

    Timer {
        id: decayTimer
        interval: 1000
        repeat: false
    }

    Timer {
        id: restartTimer
        interval: 500
        repeat: false
        onTriggered: root.isRestarting = false
    }

    Timer {
        id: dataWatchdog
        interval: 2000
        running: cavaProcess.running && root.isPlaying
        repeat: false
        onTriggered: root.restartCava()
    }

    Process {
        id: cavaProcess
        running: root.processEnabled
        onExited: root.restartCava()
        // explicit [input]/source -- it had none before and cava fell back to its
        // default ("auto" = monitor of the SYSTEM default sink, which
        // may be bluetooth). The wallpaper audio ("quickshell" stream
        // in pactl) always goes through EasyEffects (easyeffects_sink),
        // not the default sink -- confirmed live with
        // "pactl list sink-inputs" (we first tried the internal speaker's
        // monitor, it didn't work either: the real audio is
        // pre-EasyEffects processing, not on the final sink).
        command: [
            "bash", "-c",
            "cava -p <(printf '[general]\\nbars = %d\\nframerate = 60\\nsensitivity = 150\\n[input]\\nmethod = pulse\\nsource = easyeffects_sink.monitor\\n[output]\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 1000\\nbar_delimiter = 59\\n' " + root.barCount + ")"
        ]
        stdout: SplitParser {
            onRead: data => {
                if (!root.processEnabled) return;
                dataWatchdog.restart();
                let str = data.trim();
                if (str.length === 0) return;
                let parts = str.split(";");
                let count = Math.min(parts.length, root.barCount);
                let newLevels = [];
                for (let i = 0; i < root.barCount; i++) {
                    let val = i < count ? (parseInt(parts[i]) || 0) : 0;
                    newLevels.push(Math.max(0.0, Math.min(1.0, val / 1000.0)));
                }
                root.barLevels = newLevels;
            }
        }
    }
}
