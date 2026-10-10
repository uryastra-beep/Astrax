import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Splash screen (one-shot, closes by itself). Launched on hyprland.start.
//   1. the Serpantinum logo lights up with a flicker (theme primary color)
//   2. as soon as it's lit, a formation of waves (same shape, ~5cm between layers, each
//      in a theme color) drains downwards in 3.5s. The top one
//      leads; the others follow it and its edge reveals the desktop.
// Colors: ~/.local/state/serpantinum/qs_colors.json (the active theme).
// Try it by hand:  intro
ShellRoot {
    id: root

    readonly property int waveMs: 3500
    // from back (the top one, leader) to front (the logo one)
    property var layers: ["#e5b6f2", "#f5b7b4", "#d4c0d7", "#5d386b", "#110d12"]
    property color primary: "#e5b6f2"
    property color tipColor: "#cec3cd"

    // messages at the bottom while loading (fun facts + rice tips); they're
    // mounted on the front layer, so they fall together with the logo
    readonly property var tips: [
        "Snakes smell with their tongue: they flick it out to catch scents from the air.",
        "Octopuses have three hearts and blue blood.",
        "A day on Venus lasts longer than a year on Venus.",
        "Honey never spoils: edible honey has been found in Egyptian tombs.",
        "The first documented \"bug\" was a real moth stuck in a computer (1947).",
        "Linux was born in 1991 as a hobby project by Linus Torvalds.",
        "The Ouroboros, the snake eating its own tail, symbolizes the infinite cycle.",
        "Some snakes can go months without eating.",
        "A lightning bolt is about five times hotter than the surface of the Sun.",
        "Flamingos are pink because of what they eat, not from birth.",
        "There are more trees on Earth than stars in the Milky Way.",
        "Your brain uses roughly the same energy as a 20 W light bulb.",
        "CachyOS builds its packages optimized for modern CPUs.",
        "Serpantinum is built with Quickshell: it's all QML, just like this animation.",
        "Tip: type  intro  in the terminal to watch this animation any time.",
        "Tip:  outro  shows you the shutdown animation without powering off.",
        "Tip: SUPER + Power reboots straight into CachyOS, skipping the GRUB menu.",
        "The Linux penguin is called Tux, and Linus picked it because one once bit him.",
        "More than 90% of internet servers run Linux.",
        "The 500 fastest supercomputers in the world run Linux.",
        "Android uses the Linux kernel: you probably carry it in your pocket.",
        "The Linux kernel has more than 30 million lines of code.",
        "Linus Torvalds created Git in 2005 to manage the Linux source code.",
        "Arch Linux, the base of CachyOS, follows the KISS philosophy: Keep It Simple, Stupid.",
        "On Linux everything is a file: even your keyboard lives in /dev.",
        "The sudo command comes from \"superuser do\".",
        "Wayland replaces X11, a windowing system born in 1984.",
        "Python is named after Monty Python, not the snake.",
        "Snakes have no eyelids: they sleep with their eyes open.",
        "Snakes have no external ears: they feel vibrations through the ground.",
        "Pythons can sense their prey's body heat with sensors on their face.",
        "Some snakes can \"fly\" by gliding between trees.",
        "Snakes shed their whole skin in one piece, like a sock.",
        "There are snakes on every continent except Antarctica.",
        "The longest snake ever recorded was a reticulated python of almost 10 metres.",
        "The symbol of medicine carries a snake: the Rod of Asclepius."
    ]
    property int tipIdx: Math.floor(Math.random() * tips.length)
    property real tipOpacity: 0
    SequentialAnimation {
        id: tipCycle
        running: true
        PauseAnimation { duration: 500 }
        NumberAnimation { target: root; property: "tipOpacity"; to: 1; duration: 450; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 4200 }
        NumberAnimation { target: root; property: "tipOpacity"; to: 0; duration: 350; easing.type: Easing.InCubic }
        ScriptAction { script: root.tipIdx = (root.tipIdx + 1) % root.tips.length }
        // still loading, another message
        ScriptAction { script: if (!waveAnim.running) tipCycle.restart() }
    }

    // animation state (drawn by each screen's windows)
    property real glow: 0      // 0 off .. 1 neon lit
    property real p: 0         // leading wave progress
    // wave phase (like Serpantinum's wavePhase: 2pi every 4.5s).
    // no loop -> no jump on restart
    property real phase: 0
    NumberAnimation on phase { from: 0; to: Math.PI * 2 * 4; duration: 18000 }

    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.local/state/serpantinum/qs_colors.json"
        blockLoading: true
    }
    FileView {
        id: logoFile
        path: Qt.resolvedUrl("logo.svg").toString().replace("file://", "")
        blockLoading: true
    }
    readonly property string logoSvg: logoFile.text()
    function tinted(c) {
        return "data:image/svg+xml;utf8," + encodeURIComponent(logoSvg.replace(/fill:#000000/g, "fill:" + c));
    }

    Component.onCompleted: {
        try {
            const c = JSON.parse(colorsFile.text());
            const pick = [c.mauve, c.peach, c.green, c.sapphire, c.base];
            if (pick.every(x => typeof x === "string")) root.layers = pick;
            if (typeof c.mauve === "string") root.primary = c.mauve;
            if (typeof c.subtext0 === "string") root.tipColor = c.subtext0;
        } catch (e) {}
    }

    SequentialAnimation {
        id: igniteAnim
        // on boot (ASTRAX_INTRO_WAIT=1) the logo stays OFF (grey)
        // until intro.sh signals that Serpantinum finished loading (ipc go):
        // lighting up is the "loaded" signal, then the waves drop
        running: !root.waitForReady
        PauseAnimation { duration: 350 }
        // 1. neon lighting up with a tube flicker
        NumberAnimation { target: root; property: "glow"; to: 0.65; duration: 70 }
        NumberAnimation { target: root; property: "glow"; to: 0.05; duration: 60 }
        PauseAnimation { duration: 90 }
        NumberAnimation { target: root; property: "glow"; to: 0.85; duration: 60 }
        NumberAnimation { target: root; property: "glow"; to: 0.2; duration: 50 }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: root; property: "glow"; to: 0.55; duration: 40 }
        NumberAnimation { target: root; property: "glow"; to: 0.3; duration: 60 }
        NumberAnimation { target: root; property: "glow"; to: 1.0; duration: 380; easing.type: Easing.OutCubic }
        ScriptAction { script: waveAnim.start() }
    }
    SequentialAnimation {
        id: waveAnim
        PauseAnimation { duration: 300 }
        // 2. waves
        NumberAnimation { target: root; property: "p"; to: 1; duration: root.waveMs; easing.type: Easing.InOutCubic }
        // ends right when the leader exits at the bottom (on every screen)
        ScriptAction { script: Qt.quit() }
    }
    readonly property bool waitForReady: Quickshell.env("ASTRAX_INTRO_WAIT") === "1"
    property bool ready: false
    function go() {
        if (root.ready || !root.waitForReady) return;
        root.ready = true;
        igniteAnim.start();
    }
    IpcHandler {
        target: "intro"
        function go(): void { root.go(); }
    }
    // if the signal never arrives, light up and drop anyway after 30s
    Timer { interval: 30000; running: root.waitForReady; onTriggered: root.go() }
    // safety net: never leave the screen covered
    Timer { interval: 45000; running: true; onTriggered: Qt.quit() }

    Variants {
        // skip virtual outputs (HEADLESS-*)
        model: Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS"))
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            WlrLayershell.namespace: "astrax-intro"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            mask: Region {}

            // small, short waves like Serpantinum's (drawWaterWipe):
            // sum of 3 sines, base 14px -> edge of about +-15px
            readonly property real baseAmp: 14
            readonly property real amp: baseAmp * (1 + 0.7 + 0.4) * 0.5 + 1
            readonly property real stripH: amp * 2 + 2
            // spacing between layers: ~5cm real on each screen
            // (physicalPixelDensity = physical px per mm), capped in case
            // the monitor reports a weird size
            readonly property real gap: {
                const ppmm = (modelData.physicalPixelDensity || 0) / (modelData.devicePixelRatio || 1);
                const g = ppmm > 0 ? 50 * ppmm : height * 0.15;
                return Math.max(height * 0.08, Math.min(height * 0.22, g));
            }
            readonly property int n: root.layers.length
            readonly property real leadStart: -(n - 1) * gap - stripH
            readonly property real leadY: leadStart + root.p * (height + (n - 1) * gap + stripH)
            // how far the front layer drops (the logo is mounted on it)
            readonly property real drop: leadY - leadStart

            // all layers have THE SAME wave as the leader and stay a
            // fixed distance behind (like the logo's bands). Only the
            // narrow edge strip is redrawn; the rest is a rectangle
            // -> cheap and smooth at the monitor's Hz
            Repeater {
                model: win.n
                Item {
                    id: layer
                    required property int index
                    width: win.width
                    height: win.height + win.stripH
                    y: win.leadY + index * win.gap
                    // only if something is visible: the front layer fully covers
                    // the back one once its edge has passed the top
                    visible: y < win.height && (index === win.n - 1 || y + win.gap > -win.stripH)
                    // the edge (canvas) is only redrawn while on screen
                    readonly property bool edgeOnScreen: visible && y > -win.stripH
                    z: index

                    Canvas {
                        width: parent.width; height: win.stripH
                        property real phase: root.phase
                        onPhaseChanged: if (layer.edgeOnScreen) requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d"), w = width, h = height;
                            ctx.clearRect(0, 0, w, h);
                            ctx.fillStyle = root.layers[layer.index];
                            ctx.beginPath(); ctx.moveTo(0, h);
                            for (let x = 0; x <= w + 8; x += 8) {
                                let wh = 0;
                                for (let k = 1; k <= 3; k++) {
                                    const f = k * 1.5;
                                    wh += Math.sin(phase * f + x * 0.015 * f) * win.baseAmp * (1 - (k - 1) * 0.3);
                                }
                                ctx.lineTo(x, win.amp + wh * 0.5);
                            }
                            ctx.lineTo(w, h); ctx.closePath(); ctx.fill();
                        }
                    }
                    Rectangle {
                        y: win.stripH - 1
                        width: parent.width; height: parent.height - y
                        color: root.layers[layer.index]
                    }
                }
            }

            // ---- logo (sits on the front layer) ----
            Item {
                id: stage
                z: 100
                width: win.width; height: win.height
                y: win.drop

                readonly property real logoSize: Math.min(200, win.height * 0.22)
                readonly property real cx: width / 2
                readonly property real cy: height / 2 - 20

                // the svg is single-color (black fill): we repaint it with the
                // right color and let the svg renderer draw it, so the
                // edges are anti-aliased (it used to be a hard mask = jagged).
                // sourceSize doubled + mipmap so it's also clean
                // on the screen at scale 1.25
                // "off" tube (faint grey) visible before lighting up
                Image {
                    source: root.tinted("#3a3340")
                    sourceSize: Qt.size(stage.logoSize * 2, stage.logoSize * 2)
                    width: stage.logoSize; height: stage.logoSize
                    x: stage.cx - width / 2
                    y: stage.cy - height / 2
                    smooth: true; mipmap: true; antialiasing: true
                    opacity: 0.6 * (1 - root.glow)
                }
                // bottom message (fun fact / tip)
                Text {
                    text: root.tips[root.tipIdx]
                    width: Math.min(stage.width * 0.8, 900)
                    x: (stage.width - width) / 2
                    y: stage.height - 64 - height / 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: 15
                    color: root.tipColor
                    opacity: 0.75 * root.tipOpacity
                }
                // logo lit in the primary color
                Image {
                    source: root.tinted(Qt.lighter(root.primary, 1.08).toString())
                    sourceSize: Qt.size(stage.logoSize * 2, stage.logoSize * 2)
                    width: stage.logoSize; height: stage.logoSize
                    x: stage.cx - width / 2
                    y: stage.cy - height / 2
                    smooth: true; mipmap: true; antialiasing: true
                    opacity: root.glow
                }
            }
        }
    }
}
