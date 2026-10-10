import QtQuick
import QtQuick.Window

// The Serpantinum intro/outro waves (astrax-intro / astrax-power-wave) on
// the login screen, so the whole boot reads as a single animation:
//   Plymouth (base background + grey logo) -> SDDM starts covered (base bg +
//   padlock off) and the waves drop revealing the login -> on login the
//   waves rise and cover, the padlock lights up and only then the session
//   sesion ->
//   Hyprland starts with the same background + grey logo (intro --boot).
// Colors: theme.conf (waveColors), written by
// boot-splash/sync-theme.sh from the active Serpantinum theme.
Item {
    id: curtain
    anchors.fill: parent
    z: 1000

    property var layers: {
        const c = (typeof config !== "undefined" && config.waveColors) ? String(config.waveColors) : "";
        const l = c.split(",").map(x => x.trim()).filter(x => x.length > 0);
        return l.length >= 2 ? l : ["#e5b6f2", "#f5b7b4", "#d4c0d7", "#5d386b", "#110d12"];
    }

    property real p: 0        // 0 covered .. 1 uncovered (same as the intro)
    property real glow: 0     // padlock: 0 off (grey) .. 1 lit
    property real phase: 0
    readonly property bool busy: flow.running
    property var after: null

    NumberAnimation on phase { from: 0; to: Math.PI * 2 * 1000; duration: 4500 * 1000; loops: Animation.Infinite; running: curtain.p < 1 }

    // ---- secuencias ----
    // 1. when the greeter loads: the logo lights up (flicker) and the waves drop
    function reveal() {
        flow.stop();
        revealAnim.restart();
    }
    // 2. the waves rise, the logo turns off and then fn runs
    function cover(fn) {
        if (flow.running) return;
        revealAnim.stop(); uncoverAnim.stop();
        after = fn;
        flow.restart();
    }
    // 3. failed login: the padlock turns off and the waves drop again
    function uncover() {
        flow.stop();
        uncoverAnim.restart();
    }

    // on load: padlock off and the waves drop. On exit: the waves rise
    // and the padlock lights up with the intro's neon-tube flicker
    SequentialAnimation {
        id: revealAnim
        PauseAnimation { duration: 600 }
        NumberAnimation { target: curtain; property: "p"; to: 1; duration: 3500; easing.type: Easing.InOutCubic }
    }
    SequentialAnimation {
        id: flow
        NumberAnimation { target: curtain; property: "p"; to: 0; duration: 2000; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 200 }
        NumberAnimation { target: curtain; property: "glow"; to: 0.65; duration: 70 }
        NumberAnimation { target: curtain; property: "glow"; to: 0.05; duration: 60 }
        PauseAnimation { duration: 90 }
        NumberAnimation { target: curtain; property: "glow"; to: 0.85; duration: 60 }
        NumberAnimation { target: curtain; property: "glow"; to: 0.2; duration: 50 }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: curtain; property: "glow"; to: 0.55; duration: 40 }
        NumberAnimation { target: curtain; property: "glow"; to: 0.3; duration: 60 }
        NumberAnimation { target: curtain; property: "glow"; to: 1.0; duration: 380; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 400 }
        ScriptAction { script: { const f = curtain.after; curtain.after = null; if (f) f(); } }
    }
    ParallelAnimation {
        id: uncoverAnim
        NumberAnimation { target: curtain; property: "glow"; to: 0; duration: 300 }
        NumberAnimation { target: curtain; property: "p"; to: 1; duration: 1500; easing.type: Easing.InOutCubic }
    }

    // while covering, the login can't be touched
    MouseArea { anchors.fill: parent; enabled: curtain.p < 0.5 || curtain.busy; hoverEnabled: enabled }

    // ---- drawing (same as astrax-intro/shell.qml) ----
    // the greeter runs on X11 with HiDPI (its own devicePixelRatio); the intro
    // measures in Hyprland px (laptop at scale 1.25). k converts between them
    // so the waves have the same physical size on the real screen
    readonly property real k: 1.25 / (Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1)
    readonly property real baseAmp: 14 * k
    readonly property real amp: baseAmp * (1 + 0.7 + 0.4) * 0.5 + 1
    readonly property real stripH: amp * 2 + 2
    // ~5cm between layers (Screen.pixelDensity = px per mm)
    readonly property real gap: {
        const g = Screen.pixelDensity > 0 ? 50 * Screen.pixelDensity * k : height * 0.15;
        return Math.max(height * 0.08, Math.min(height * 0.22, g));
    }
    readonly property int n: layers.length
    readonly property real leadStart: -(n - 1) * gap - stripH
    readonly property real leadY: leadStart + p * (height + (n - 1) * gap + stripH)
    readonly property real drop: leadY - leadStart

    Repeater {
        model: curtain.n
        Item {
            id: layer
            required property int index
            width: curtain.width
            height: curtain.height + curtain.stripH
            y: curtain.leadY + index * curtain.gap
            visible: y < curtain.height
            z: index

            Canvas {
                width: parent.width; height: curtain.stripH
                property real phase: curtain.phase
                property color fill: curtain.layers[layer.index]
                onPhaseChanged: if (layer.visible) requestPaint()
                onFillChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d"), w = width, h = height;
                    ctx.clearRect(0, 0, w, h);
                    ctx.fillStyle = fill;
                    ctx.beginPath(); ctx.moveTo(0, h);
                    for (let x = 0; x <= w + 8; x += 8) {
                        let wh = 0;
                        for (let k = 1; k <= 3; k++) {
                            const f = k * 1.5;
                            wh += Math.sin(phase * f + x / curtain.k * 0.015 * f) * curtain.baseAmp * (1 - (k - 1) * 0.3);
                        }
                        ctx.lineTo(x, curtain.amp + wh * 0.5);
                    }
                    ctx.lineTo(w, h); ctx.closePath(); ctx.fill();
                }
            }
            Rectangle {
                y: curtain.stripH - 1
                width: parent.width; height: parent.height - y
                color: curtain.layers[layer.index]
            }
        }
    }

    // logo mounted on the front layer
    Item {
        id: stage
        z: 100
        width: curtain.width; height: curtain.height
        y: curtain.drop
        visible: y < curtain.height

        readonly property real logoSize: Math.min(200 * curtain.k, curtain.height * 0.22)
        readonly property real cx: width / 2
        readonly property real cy: height / 2 - 20 * curtain.k

        // padlock off (faint grey, like the intro's off logo)
        Image {
            source: "lock-off.svg"
            sourceSize: Qt.size(stage.logoSize * 2, stage.logoSize * 2)
            width: stage.logoSize * 0.7; height: stage.logoSize * 0.7
            x: stage.cx - width / 2
            y: stage.cy - height / 2
            smooth: true; mipmap: true; antialiasing: true
            opacity: 0.6 * (1 - curtain.glow)
        }
        // padlock lit (theme primary color)
        Image {
            source: "lock-on.svg"
            sourceSize: Qt.size(stage.logoSize * 2, stage.logoSize * 2)
            width: stage.logoSize * 0.7; height: stage.logoSize * 0.7
            x: stage.cx - width / 2
            y: stage.cy - height / 2
            smooth: true; mipmap: true; antialiasing: true
            opacity: curtain.glow
        }
    }
}
