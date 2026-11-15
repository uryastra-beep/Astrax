import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../../../reusables"
import "../../../"
import "../../../../../../../../.config/astrax-common/lg"

// iPhone lock-screen style clock: date on top + tall "glass" digits (translucent gradient fill +
// rim light + soft shadow). Reuses the stroke-glyph engine of ClockFaceStretched (same geometry).
Item {
    id: root
    anchors.fill: parent

    property real minWidth: 100
    property real minHeight: 140
    property real maxWidth: 900
    property real maxHeight: 1400
    property real minAspect: 0.3
    property real maxAspect: 2.5
    property bool isRound: false
    property bool showDate: true
    // On the lock screen the glass uses the lock's own blurred background (not the screen capture)
    property var ctx: null
    readonly property bool inLock: ctx !== null && ctx !== undefined && ctx.glassSourceItem !== undefined && ctx.glassSourceItem !== null

    // always 12h, no leading zero (like the iPhone lock screen)
    readonly property var nowDate: DateTime.now || new Date()
    readonly property string hourStr: String((nowDate.getHours() % 12) || 12)
    readonly property string minuteStr: Qt.formatDateTime(nowDate, "mm")
    readonly property var chars: (hourStr + ":" + minuteStr).split("")
    readonly property int digitCount: chars.length - 1

    readonly property string dateStr: {
        let d = DateTime.now || new Date();
        let s = Qt.locale("es_ES").toString(d, "ddd d MMM").replace(/\./g, "");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    readonly property real dateH: showDate ? Math.max(Scaler.s(18), height * 0.075) : 0
    readonly property real areaTop: showDate ? dateH + height * 0.04 : height * 0.03
    readonly property real areaWidth: width * 0.94
    readonly property real areaHeight: Math.max(1, height - areaTop - height * 0.03)
    readonly property real gapRatio: 0.12
    readonly property real colonRatio: 0.4
    readonly property real cw: Math.max(1, Math.min(areaHeight * 0.34,
        areaWidth / (digitCount + colonRatio + (digitCount + 1) * gapRatio)))
    readonly property real gap: cw * gapRatio
    readonly property real colonW: cw * colonRatio
    readonly property real contentWidth: cw * (digitCount + colonRatio) + gap * digitCount
    readonly property real stroke: cw * 0.26
    readonly property real rim: Math.max(1, cw * 0.035)

    function roundRect(x0, y0, x1, y1, r) {
        return "M" + (x0 + r) + " " + y0
            + " H" + (x1 - r) + " A" + r + " " + r + " 0 0 1 " + x1 + " " + (y0 + r)
            + " V" + (y1 - r) + " A" + r + " " + r + " 0 0 1 " + (x1 - r) + " " + y1
            + " H" + (x0 + r) + " A" + r + " " + r + " 0 0 1 " + x0 + " " + (y1 - r)
            + " V" + (y0 + r) + " A" + r + " " + r + " 0 0 1 " + (x0 + r) + " " + y0 + " Z";
    }

    function glyphPath(ch, w, h, s) {
        let x0 = s / 2, x1 = w - s / 2, y0 = s / 2, y1 = h - s / 2;
        let ym = h / 2, r = (x1 - x0) / 2;
        switch (ch) {
        case "0":
            return roundRect(x0, y0, x1, y1, r);
        case "1":
            return "M" + x0 + " " + (y0 + r) + " L" + x1 + " " + y0 + " V" + y1;
        case "2": {
            let d = (y1 - y0 - r) * 0.45;
            return "M" + x0 + " " + (y0 + r) + " A" + r + " " + r + " 0 0 1 " + x1 + " " + (y0 + r)
                + " C" + x1 + " " + (y0 + r + d) + " " + x0 + " " + (y1 - d) + " " + x0 + " " + y1
                + " H" + x1;
        }
        case "3":
            return "M" + x0 + " " + (y0 + r) + " A" + r + " " + r + " 0 0 1 " + x1 + " " + (y0 + r)
                + " V" + (ym - r) + " A" + r + " " + r + " 0 0 1 " + (x1 - r) + " " + ym
                + " H" + (x0 + r * 0.3)
                + " M" + (x1 - r) + " " + ym + " A" + r + " " + r + " 0 0 1 " + x1 + " " + (ym + r)
                + " V" + (y1 - r) + " A" + r + " " + r + " 0 0 1 " + x0 + " " + (y1 - r);
        case "4": {
            let xs = x0 + (x1 - x0) * 0.68, yb = y0 + (y1 - y0) * 0.7;
            return "M" + xs + " " + y1 + " V" + y0 + " L" + x0 + " " + yb + " H" + x1;
        }
        case "5": {
            let yq = ym + 0.04 * h;
            return "M" + x1 + " " + y0 + " H" + x0 + " V" + yq + " H" + (x1 - r)
                + " A" + r + " " + r + " 0 0 1 " + x1 + " " + (yq + r)
                + " V" + (y1 - r) + " A" + r + " " + r + " 0 0 1 " + (x1 - r) + " " + y1 + " H" + x0;
        }
        case "6":
        case "9": {
            let yq = ym + 0.04 * h;
            return "M" + x1 + " " + y0 + " H" + (x0 + r)
                + " A" + r + " " + r + " 0 0 0 " + x0 + " " + (y0 + r)
                + " V" + (y1 - r) + " A" + r + " " + r + " 0 0 0 " + (x0 + r) + " " + y1
                + " H" + (x1 - r) + " A" + r + " " + r + " 0 0 0 " + x1 + " " + (y1 - r)
                + " V" + (yq + r) + " A" + r + " " + r + " 0 0 0 " + (x1 - r) + " " + yq
                + " H" + x0;
        }
        case "7":
            return "M" + x0 + " " + y0 + " H" + x1 + " L" + (x0 + (x1 - x0) * 0.3) + " " + y1;
        case "8":
            return roundRect(x0, y0, x1, ym, r) + " " + roundRect(x0, ym, x1, y1, r);
        }
        return "";
    }

    // one drawn character (stroke digit, or the colon)
    component GlyphShape: Item {
        id: gs
        property string ch: ""
        property real strokeW: root.stroke
        property color col: "white"
        readonly property bool isColon: ch === ":"

        Shape {
            anchors.fill: parent
            visible: !gs.isColon && gs.ch !== ""
            rotation: gs.ch === "9" ? 180 : 0
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: gs.strokeW
                strokeColor: gs.col
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: root.glyphPath(gs.ch, gs.width, gs.height, root.stroke)
                }
            }
        }

        Repeater {
            model: gs.isColon ? 2 : 0

            Rectangle {
                required property int index
                width: Math.max(1, root.stroke * 1.1 - (root.stroke - gs.strokeW))
                height: width
                radius: width / 2
                color: gs.col
                x: (gs.width - width) / 2
                y: gs.height * (index === 0 ? 0.35 : 0.65) - height / 2
            }
        }
    }

    // row of characters; each position is persistent and only fades
    // (old -> new) when ITS character changes
    component Glyphs: Row {
        id: glyphs
        property real strokeW: root.stroke
        property color col: "white"
        spacing: root.gap

        Repeater {
            model: root.chars.length

            Item {
                id: cell
                required property int index
                readonly property string ch: root.chars[index] !== undefined ? root.chars[index] : ""
                readonly property bool isColon: ch === ":"
                property string curCh: ch
                property string prevCh: ""
                property real fadeT: 1

                width: isColon ? root.colonW : root.cw
                height: root.areaHeight

                // The old one goes away almost at once (~50 ms); the new one is revealed from the bottom up with a
                // very soft gradient (~0.7 s), like the iPhone's time change (measured from a 50 % slowed recording).
                property real oldAlpha: 1
                NumberAnimation { id: oldOut; target: cell; property: "oldAlpha"; from: 1; to: 0; duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation {
                    id: fadeAnim
                    target: cell
                    property: "fadeT"
                    from: 0
                    to: 1
                    duration: 700
                    easing.type: Easing.InOutSine
                    onFinished: cell.prevCh = ""
                }
                onChChanged: {
                    if (ch === curCh) return;
                    prevCh = curCh;
                    curCh = ch;
                    oldAlpha = 1;
                    oldOut.restart();
                    fadeAnim.restart();
                }

                GlyphShape {
                    anchors.fill: parent
                    ch: cell.prevCh
                    strokeW: glyphs.strokeW
                    col: glyphs.col
                    opacity: cell.oldAlpha
                    visible: cell.prevCh !== "" && opacity > 0.001
                }
                GlyphShape {
                    anchors.fill: parent
                    ch: cell.curCh
                    strokeW: glyphs.strokeW
                    col: glyphs.col
                    layer.enabled: cell.prevCh !== ""
                    layer.effect: ShaderEffect {
                        property real progress: cell.fadeT
                        property real band: 0.5
                        fragmentShader: Qt.resolvedUrl("reveal.frag.qsb")
                    }
                }
            }
        }
    }

    // ---- date ----
    Text {
        id: dateLabel
        visible: root.showDate
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.01
        height: root.dateH
        verticalAlignment: Text.AlignVCenter
        text: root.dateStr
        color: ThemeBackend.text
        opacity: 0.85
        font.family: ThemeBackend.fontFamily
        font.weight: Font.DemiBold
        font.pixelSize: root.dateH * 0.8
    }

    // ---- glass digits ----
    Item {
        id: digits
        x: (root.width - root.contentWidth) / 2
        y: root.areaTop
        width: root.contentWidth
        height: root.areaHeight

        // shape of the digits (opaque) -> mask texture for the shader
        Glyphs {
            id: maskGlyphs
            anchors.fill: parent
            col: "white"
        }
        ShaderEffectSource {
            id: maskTexture
            sourceItem: maskGlyphs
            hideSource: true
            visible: false
            live: true
            smooth: true
        }

        // Liquid Glass of the island (glass-glyph-lg.frag = glass-soft-blur adapted to
        // the shape of the digits): refraction at the edge + translucent interior
        ShaderEffect {
            anchors.fill: parent
            opacity: root.glassOn ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            property var src: root.useStatic ? wallTex : backdropTexture
            property var maskTex: maskTexture
            property real strength: 0.9
            property real band: Math.max(3, root.stroke * 0.55)
            property real hasBackdrop: root.useStatic ? (wall.hasContent ? 1 : 0) : (root.inLock ? 1 : (snap.hasContent ? 1 : 0))
            property real vignette: 0.65
            property real outline: 0.9
            property vector2d size: Qt.vector2d(width, height)
            property vector2d origin: root.useStatic ? Qt.vector2d(root.wallMargin, root.wallMargin) : root.glassOrigin
            property vector2d screen: root.useStatic ? Qt.vector2d(root.wallRegion.width, root.wallRegion.height) : (root.inLock ? Qt.vector2d(root.ctx.width, root.ctx.height) : Qt.vector2d(snap.width, snap.height))
            property color tint: ThemeBackend.mauve
            fragmentShader: Qt.resolvedUrl("glass-glyph-lg.frag.qsb")
        }
    }

    // ---- background for the glass: screen capture (same as the island) ----
    readonly property var win: QsWindow.window
    property bool glassOn: true
    property bool capturing: false
    property vector2d glassOrigin: Qt.vector2d(0, 0)

    function updateOrigin() {
        if (inLock) {
            let q = digits.mapToItem(ctx.glassSourceItem, 0, 0);
            glassOrigin = Qt.vector2d(q.x, q.y);
            return;
        }
        if (!win) return;
        let p = digits.mapToItem(null, 0, 0);
        glassOrigin = Qt.vector2d((win.margins.left || 0) + p.x, (win.margins.top || 0) + p.y);
    }

    // ---- wallpaper (still, lava or video): the glass projects ITS copy (only the back part) ----
    readonly property bool useStatic: !inLock && wall.hasContent
    readonly property real wallMargin: 80   // the edge refracts up to ~60 px outside the digit
    readonly property rect wallRegion: Qt.rect(glassOrigin.x - wallMargin, glassOrigin.y - wallMargin,
                                               digits.width + 2 * wallMargin, digits.height + 2 * wallMargin)
    WallBackdrop {
        id: wall
        screenName: root.win && root.win.screen ? root.win.screen.name : ""
        width: root.win && root.win.screen ? root.win.screen.width : 1920
        height: root.win && root.win.screen ? root.win.screen.height : 1080
        active: !root.inLock && root.visible
    }
    ShaderEffectSource {
        id: wallTex
        sourceItem: wall
        sourceRect: root.wallRegion
        hideSource: true
        // still: refreshed only for a while after loading/moving (the image loads async, otherwise the texture stays empty); lava/video: always
        live: wall.animated || wallRefresh.running || !wall.hasContent
        smooth: true
        visible: false
    }
    Timer { id: wallRefresh; interval: 2500 }
    Connections { target: wall; function onHasContentChanged() { wallRefresh.restart(); } function onPathChanged() { wallRefresh.restart(); } }
    onWallRegionChanged: wallRefresh.restart()

    ScreencopyView {
        id: snap
        captureSource: (!root.inLock && !root.useStatic && root.win) ? root.win.screen : null
        live: true
        visible: true
        width: root.win && root.win.screen ? root.win.screen.width : 1
        height: root.win && root.win.screen ? root.win.screen.height : 1
    }
    ShaderEffectSource {
        id: backdropTexture
        sourceItem: root.inLock ? root.ctx.glassSourceItem : snap
        hideSource: !root.inLock
        live: true
        visible: false
    }

    // capture without the glass on (otherwise the glass would see itself)
    function recapture() {
        updateOrigin();
    }
    Timer { id: hideWait; interval: 160; onTriggered: { root.updateOrigin(); root.capturing = true; snap.captureFrame(); showWait.restart(); } }
    Timer { id: showWait; interval: 400; onTriggered: { root.capturing = false; root.glassOn = true } }
    Timer { id: periodic; interval: 600000; running: root.visible; repeat: true; onTriggered: root.recapture() }
    Timer { interval: 700; running: true; onTriggered: root.recapture() }

    Timer { interval: 400; running: root.visible; repeat: true; onTriggered: root.updateOrigin() }
    onWidthChanged: updateOrigin()
    onHeightChanged: updateOrigin()
}
