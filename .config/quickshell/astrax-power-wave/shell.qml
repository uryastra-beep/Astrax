import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit

// Power-off animation = the splash screen (astrax-intro) IN REVERSE:
//   1. the theme's wave formation RISES from the bottom (3.5s) covering everything;
//      the front layer (base color) carries the lit logo
//   2. once covered, the logo turns off with a tube flicker and stays grey
//   3. only then the action runs (power off / reboot)
// Daemon (autostart) controlled via IPC:
//   qs -c astrax-power-wave ipc call wave hold             -> rises (3.5s); full = power off
//   qs -c astrax-power-wave ipc call wave holdFor reboot   -> same but reboots
//   qs -c astrax-power-wave ipc call wave release          -> drops if it didn't reach the top
//   qs -c astrax-power-wave ipc call wave toggle           -> alternates hold/release
//   qs -c astrax-power-wave ipc call wave play             -> rises by itself and stays covered
//                                                          (the caller performs the action)
//   qs -c astrax-power-wave ipc call wave preview          -> the whole animation WITHOUT powering off:
//                                                          disappears 2s later (`outro` command)
//   qs -c astrax-power-wave ipc call wave cover            -> the whole animation and stays COVERED without
//                                                          doing anything (lock/suspend/hibernate)
//   qs -c astrax-power-wave ipc call wave clear            -> removes the cover instantly
// Used by: the physical button (binds-serpantinum.lua), Serpantinum's SystemPanel
// (hold reboot/power off) and ~/scripts/power-wave.sh (lock screen, etc).
ShellRoot {
    id: root

    property real level: 0          // 0 nothing .. 1 fully covered (linear, = time held)
    property bool holding: false
    property bool committed: false
    property string action: "poweroff"
    property bool runAction: true   // false with play(): the caller performs the action
    property real glow: 1           // logo: 1 lit .. 0 off
    property real phase: 0
    property bool previewing: false

    property var layers: ["#e5b6f2", "#f5b7b4", "#d4c0d7", "#5d386b", "#110d12"]
    property color primary: "#e5b6f2"

    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.local/state/serpantinum/qs_colors.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
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
    // the theme can change while the daemon runs: re-read on every use
    function loadColors() {
        try {
            const c = JSON.parse(colorsFile.text());
            const pick = [c.mauve, c.peach, c.green, c.sapphire, c.base];
            if (pick.every(x => typeof x === "string")) root.layers = pick;
            if (typeof c.mauve === "string") root.primary = c.mauve;
        } catch (e) {}
    }

    // same curve as the intro, run in reverse
    function ease(x) { x = Math.max(0, Math.min(1, x)); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }
    readonly property real p: 1 - ease(level)   // the intro's p: 1 = uncovered, 0 = covered

    // fully covered and still = no edge in sight -> nothing animates
    NumberAnimation on phase { from: 0; to: Math.PI * 2 * 1000; duration: 4500 * 1000; running: root.level > 0 && root.level < 1 }

    // movement with inertia: level doesn't jump from rising to falling, the speed
    // brakes and accelerates in ~0.35s -> the change of direction looks smooth.
    // Top speed = 3.5s from empty to full (same as before, rising and falling)
    property real vel: 0
    readonly property real vmax: 1 / 3.5
    readonly property real accel: vmax / 0.35
    FrameAnimation {
        id: mover
        running: root.holding ? root.level < 1 : (root.level > 0 || root.vel !== 0)
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            const tv = root.holding ? root.vmax : -root.vmax;
            const dv = Math.max(-root.accel * dt, Math.min(root.accel * dt, tv - root.vel));
            root.vel += dv;
            const l = root.level + root.vel * dt;
            if (l >= 1) {
                root.vel = 0; root.level = 1;
                if (root.holding || root.committed) { root.committed = true; offAnim.start(); }
            } else if (l <= 0) {
                root.vel = 0; root.level = 0;
            } else root.level = l;
        }
    }
    // the intro in reverse: the neon turns off with a flicker and then the action
    SequentialAnimation {
        id: offAnim
        PauseAnimation { duration: 250 }
        NumberAnimation { target: root; property: "glow"; to: 0.3; duration: 380; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "glow"; to: 0.55; duration: 60 }
        NumberAnimation { target: root; property: "glow"; to: 0.2; duration: 40 }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: root; property: "glow"; to: 0.85; duration: 50 }
        NumberAnimation { target: root; property: "glow"; to: 0.05; duration: 60 }
        PauseAnimation { duration: 90 }
        NumberAnimation { target: root; property: "glow"; to: 0.65; duration: 60 }
        NumberAnimation { target: root; property: "glow"; to: 0.0; duration: 70 }
        PauseAnimation { duration: 300 }
        ScriptAction { script: if (root.runAction) powerProc.running = true; else if (root.previewing) previewEnd.start(); }
    }
    // preview: 2s after finishing it vanishes at once and is ready again
    Timer {
        id: previewEnd; interval: 2000
        onTriggered: { root.vel = 0; root.level = 0; root.glow = 1; root.committed = false; root.holding = false; root.previewing = false; }
    }
    Process {
        id: powerProc
        command: ["env", "POWER_WAVE_DONE=1", "bash",
                  Quickshell.env("HOME") + "/.local/share/serpantinum/src/scripts/system/" + root.action + ".sh"]
    }

    function start(act, run) {
        if (committed) return;
        if (level <= 0.001) { loadColors(); glow = 1; }
        action = act; runAction = run; holding = true;
    }

    IpcHandler {
        target: "wave"
        function hold(): void { root.start("poweroff", true); }
        function holdFor(act: string): void { root.start(act === "reboot" ? "reboot" : "poweroff", true); }
        function release(): void { if (root.committed) return; root.holding = false; }
        // physical button (sends press+release together): tap = rise, another tap = drop
        function toggle(): void { console.log("TOGGLE holding=" + root.holding + " level=" + root.level.toFixed(3) + " committed=" + root.committed); if (root.holding) release(); else hold(); }
        function play(): void { root.start("poweroff", false); root.committed = true; }
        function cover(): void { if (root.committed) return; root.start("poweroff", false); root.committed = true; }
        function clear(): void {
            offAnim.stop(); previewEnd.stop();
            root.vel = 0; root.level = 0; root.glow = 1; root.committed = false; root.holding = false; root.previewing = false;
        }
        function preview(): void { if (root.committed) return; root.start("poweroff", false); root.previewing = true; root.committed = true; }
    }

    Variants {
        // virtual outputs (HEADLESS-*) are never covered
        model: Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS"))
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.level > 0.001
            WlrLayershell.namespace: "astrax-power-wave"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            mask: Region {}

            // ---- same drawing as astrax-intro (see that shell.qml) ----
            readonly property real baseAmp: 14
            readonly property real amp: baseAmp * (1 + 0.7 + 0.4) * 0.5 + 1
            readonly property real stripH: amp * 2 + 2
            readonly property real gap: {
                const ppmm = (modelData.physicalPixelDensity || 0) / (modelData.devicePixelRatio || 1);
                const g = ppmm > 0 ? 50 * ppmm : height * 0.15;
                return Math.max(height * 0.08, Math.min(height * 0.22, g));
            }
            readonly property int n: root.layers.length
            readonly property real leadStart: -(n - 1) * gap - stripH
            readonly property real leadY: leadStart + root.p * (height + (n - 1) * gap + stripH)
            readonly property real drop: leadY - leadStart

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
                        property color fill: root.layers[layer.index]
                        onPhaseChanged: if (layer.edgeOnScreen) requestPaint()
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

            // logo mounted on the front layer
            Item {
                id: stage
                z: 100
                width: win.width; height: win.height
                y: win.drop
                visible: y < win.height

                readonly property real logoSize: Math.min(200, win.height * 0.22)
                readonly property real cx: width / 2
                readonly property real cy: height / 2 - 20

                Image {
                    source: root.tinted("#3a3340")
                    sourceSize: Qt.size(stage.logoSize * 2, stage.logoSize * 2)
                    width: stage.logoSize; height: stage.logoSize
                    x: stage.cx - width / 2
                    y: stage.cy - height / 2
                    smooth: true; mipmap: true; antialiasing: true
                    opacity: 0.6 * (1 - root.glow)
                }
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

    // ---- own polkit agent while covered (`outro per`) ----
    // the hyprpolkitagent window is a normal window and ends up UNDER the
    // cover (overlay layer). outro.sh stops hyprpolkitagent and enables this
    // agent; its dialog is another overlay layer that opens above the cover.
    // intro.sh go turns it off and starts hyprpolkitagent again.
    property bool ownAgent: false

    // tells Serpantinum (WallpaperEngine) the screen is covered so
    // it pauses the video background
    readonly property bool fullyCovered: root.level >= 1
    onFullyCoveredChanged: {
        coverFlag.command = ["sh", "-c", "echo " + (root.fullyCovered ? 1 : 0) + " > \"${XDG_RUNTIME_DIR:-/tmp}/astrax-covered\""];
        coverFlag.running = true;
    }
    Process { id: coverFlag }
    IpcHandler {
        target: "agent"
        function on(): void { root.ownAgent = true; }
        function off(): void { root.ownAgent = false; }
    }
    LazyLoader {
        active: root.ownAgent
        Item {
            id: pk
            property string err: ""
            PolkitAgent { id: agent }
            Connections {
                target: agent.flow
                ignoreUnknownSignals: true
                function onAuthenticationFailed() { pk.err = (agent.flow && agent.flow.supplementaryMessage) || "Wrong password"; pass.text = ""; }
                function onAuthenticationSucceeded() { pk.err = ""; pass.text = ""; }
                function onAuthenticationRequestCancelled() { pk.err = ""; pass.text = ""; }
            }
            PanelWindow {
                visible: agent.isActive
                screen: Quickshell.screens.filter(s => !s.name.startsWith("HEADLESS"))[0]
                WlrLayershell.namespace: "astrax-power-wave-polkit"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: agent.isActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                anchors { top: true; bottom: true; left: true; right: true }
                color: "transparent"
                onVisibleChanged: if (visible) { pk.err = ""; pass.text = ""; pass.forceActiveFocus(); }

                Rectangle {
                    anchors.centerIn: parent
                    width: 420; height: col.implicitHeight + 48
                    radius: 22
                    color: Qt.lighter(root.layers[root.layers.length - 1], 1.9)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    Column {
                        id: col
                        anchors.centerIn: parent
                        width: parent.width - 48
                        spacing: 14
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: "󰌾  Your password is required"
                            font.family: "Iosevka Nerd Font"; font.pixelSize: 18
                            color: root.primary
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: agent.flow ? agent.flow.message : ""
                            font.family: "Iosevka Nerd Font"; font.pixelSize: 13
                            color: "#cec3cd"; opacity: 0.85
                        }
                        Rectangle {
                            width: parent.width; height: 44; radius: 14
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.color: pk.err !== "" ? "#ffb4ab" : Qt.rgba(1, 1, 1, 0.12)
                            TextInput {
                                id: pass
                                anchors.fill: parent; anchors.margins: 12
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                font.family: "Iosevka Nerd Font"; font.pixelSize: 16
                                color: "#e9e0e7"
                                focus: true
                                onAccepted: if (agent.flow && text !== "") agent.flow.submit(text)
                                Keys.onEscapePressed: if (agent.flow) agent.flow.cancelAuthenticationRequest()
                            }
                        }
                        Text {
                            visible: pk.err !== ""
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: pk.err
                            font.family: "Iosevka Nerd Font"; font.pixelSize: 12
                            color: "#ffb4ab"
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: "Enter to accept · Esc to cancel"
                            font.family: "Iosevka Nerd Font"; font.pixelSize: 11
                            color: "#988e97"
                        }
                    }
                }
            }
        }
    }
}
