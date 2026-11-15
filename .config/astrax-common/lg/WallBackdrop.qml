pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// "Clean" copy of the current wallpaper for Liquid Glass (no widgets, no dock, no island).
// Supports: still image, lava (live copy of the shader: same palette/bass/clock), video/gif.
// Size = full screen (logical px). Use `active` to pay CPU/GPU only while the glass is visible.
Item {
    id: root
    property bool active: true
    readonly property bool hasContent: lavaOn ? true : (isVideo ? video.hasVideo : (isGif ? gif.status === AnimatedImage.Ready : img.status === Image.Ready))
    readonly property bool animated: lavaOn || isVideo || isGif
    property string path: ""
    property string screenName: ""
    property bool lavaOn: false

    readonly property string ext: path.indexOf(".") >= 0 ? path.split(".").pop().toLowerCase() : ""
    readonly property bool isVideo: !lavaOn && ["mp4", "webm", "mkv", "mov", "avi", "m4v"].indexOf(ext) >= 0
    readonly property bool isGif: !lavaOn && ext === "gif"
    readonly property bool isStill: !lavaOn && path !== "" && !isVideo && !isGif

    Process {
        id: pathProc
        command: root.screenName !== "" ? ["serpantinum", "info", "wallpaper", root.screenName] : ["serpantinum", "info", "wallpaper"]
        stdout: StdioCollector { onStreamFinished: { const p = text.trim().split("\n")[0]; if (p !== root.path) root.path = p; } }
    }
    Process {
        id: lavaProc
        command: ["pgrep", "-f", "^quickshell -c lava-wallpaper"]
        onExited: (code) => { if ((code === 0) !== root.lavaOn) root.lavaOn = (code === 0); }
    }
    Timer {
        interval: 3000; running: root.active; repeat: true; triggeredOnStart: true
        onTriggered: { if (!pathProc.running) pathProc.running = true; if (!lavaProc.running) lavaProc.running = true; }
    }

    Rectangle { anchors.fill: parent; color: "#101014" }

    // ---- imagen fija ----
    Image {
        id: img
        anchors.fill: parent
        visible: root.isStill
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: root.isStill ? "file://" + root.path : ""
        sourceSize: Qt.size(root.width, root.height)
    }
    AnimatedImage {
        id: gif
        anchors.fill: parent
        visible: root.isGif
        fillMode: Image.PreserveAspectCrop
        playing: root.active && root.isGif
        source: root.isGif ? "file://" + root.path : ""
    }

    // ---- video (own copy of the video: not phase-locked to the real wallpaper) ----
    MediaPlayer {
        id: player
        source: root.isVideo && root.active ? "file://" + root.path : ""
        videoOutput: video
        loops: MediaPlayer.Infinite
        audioOutput: null
        onSourceChanged: if (source.toString() !== "") play()
    }
    VideoOutput {
        id: video
        anchors.fill: parent
        visible: root.isVideo
        fillMode: VideoOutput.PreserveAspectCrop
        readonly property bool hasVideo: player.mediaStatus === MediaPlayer.BufferedMedia || player.mediaStatus === MediaPlayer.LoadedMedia
    }

    // ---- lava: same shader, palette, bass and clock as lava-wallpaper ----
    readonly property var defaults: ["#a855f7", "#7552b3", "#5b3a9e", "#c084fc", "#3b2470", "#8b5cf6", "#2a1a4e"]
    property var target: defaults.map(h => Qt.color(h))
    property var weights: [1, 1, 1, 1, 1, 1, 1]
    property color k0: target[0]; property color k1: target[1]; property color k2: target[2]; property color k3: target[3]
    property color k4: target[4]; property color k5: target[5]; property color k6: target[6]
    Behavior on k0 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k1 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k2 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k3 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k4 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k5 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    Behavior on k6 { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } }
    FileView {
        path: "/tmp/lava-palette.json"
        watchChanges: root.lavaOn
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                const mx = Math.max(...j.map(e => e.w), 0.0001);
                root.target = j.slice(0, 7).map(e => Qt.color("#" + e.hex));
                root.weights = j.slice(0, 7).map(e => e.w / mx);
            } catch (e) {}
        }
    }
    property real bass: 0
    property real bassAvg: 0
    property real loud: 0
    property real loudAvg: 0
    readonly property real pulseGain: {
        let white = 0;
        for (const c of target) {
            const mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b);
            const sat = mx > 0 ? (mx - mn) / mx : 0;
            const w = Math.max(0, Math.min(1, (mx - 0.65) / 0.25)) * Math.max(0, Math.min(1, (0.45 - sat) / 0.3));
            white = Math.max(white, w);
        }
        return 1.0 - 0.7 * white;
    }
    Process {
        id: cavaProc
        running: root.lavaOn && root.active
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/lava-wallpaper/cava.conf"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const p = data.split(";").filter(s => s.length > 0).map(s => parseInt(s, 10) || 0);
                if (p.length < 2) return;
                const b = (p[0] + p[1]) / 2 / 1000;
                root.bassAvg = root.bassAvg * 0.98 + b * 0.02;
                root.bass = Math.min(1, Math.max(0, b - root.bassAvg * 1.15 - 0.05) * 3.5);
                const l = p.reduce((a, v) => a + v, 0) / p.length / 1000;
                root.loudAvg = root.loudAvg * 0.98 + l * 0.02;
                root.loud = Math.min(1, Math.max(0, l - root.loudAvg * 1.15 - 0.04) * 3.5);
            }
        }
        onExited: cavaRestart.restart()
    }
    Timer { id: cavaRestart; interval: 500; onTriggered: cavaProc.running = root.lavaOn && root.active }
    property real t: (Date.now() % 100000000) / 1000
    Timer { interval: 33; running: root.lavaOn && root.active; repeat: true; onTriggered: root.t = (Date.now() % 100000000) / 1000 }

    ShaderEffect {
        anchors.fill: parent
        visible: root.lavaOn
        layer.enabled: root.lavaOn
        layer.smooth: true
        layer.textureSize: Qt.size(Math.max(1, width / 3), Math.max(1, height / 3))
        property real time: root.t
        property real aspect: width / Math.max(1, height)
        property real bass: root.bass * root.pulseGain
        property real loud: root.loud * root.pulseGain
        property vector4d k0: Qt.vector4d(root.k0.r, root.k0.g, root.k0.b, root.weights[0])
        property vector4d k1: Qt.vector4d(root.k1.r, root.k1.g, root.k1.b, root.weights[1])
        property vector4d k2: Qt.vector4d(root.k2.r, root.k2.g, root.k2.b, root.weights[2])
        property vector4d k3: Qt.vector4d(root.k3.r, root.k3.g, root.k3.b, root.weights[3])
        property vector4d k4: Qt.vector4d(root.k4.r, root.k4.g, root.k4.b, root.weights[4])
        property vector4d k5: Qt.vector4d(root.k5.r, root.k5.g, root.k5.b, root.weights[5])
        property vector4d k6: Qt.vector4d(root.k6.r, root.k6.g, root.k6.b, root.weights[6])
        fragmentShader: Qt.resolvedUrl("lava.frag.qsb")
    }
}
