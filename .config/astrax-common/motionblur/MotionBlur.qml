import QtQuick

// Real motion blur for one item. Not a ghost copy: while the item moves or changes size, the picture is
// averaged over the positions it passed through during a virtual shutter (motionblur.frag), so the longer it
// travels per frame, the longer the smear. At rest nothing is drawn through it and it costs nothing:
// no frames are requested and the item is shown directly.
//
//   Item { id: art ... }
//   MotionBlur { target: art; enabled: MotionBlurSettings.on("dock") }
//
// Place it as a sibling of `target` (it draws next to it, in the same parent). It follows `target` moving in the
// scene (any ancestor included, as long as something calls poke()), `target` resizing (zoom blur around anchorX/Y)
// and, for windows that are moved by the compositor, whatever `extraX` / `extraY` track.
Item {
    id: mb
    required property Item target
    property bool enabled: true
    property real strength: MotionBlurSettings.strength   // 0..2, 1 is a 1/60 s shutter
    property real pad: 48                                  // room around the item for the smear to spill into
    property real maxBlur: 56                              // longest smear, in px
    property real anchorX: 0.5                             // the point a growing/shrinking item scales around
    property real anchorY: 0.5
    property real extraX: 0                                // movement that is not visible from inside the item
    property real extraY: 0
    property real extraWeight: 1                           // how much of extraX/Y's movement counts (0..1), e.g. icons near the pointer follow it more
    property real boost: 1                                 // multiplies the exposure for this item (a longer shutter)
    property real zoomWeight: 0.5                          // how much a size change adds to the smear
    property var effectTransform: []                // the target's own transform (scale, ...), repeated on the smeared copy, with origins relative to it (pad included)
    property bool liveContent: false                       // true if what is inside the target changes while it moves (island panels, widget faces); false re-renders it only when it changes size
    property size fixedSize: Qt.size(0, 0)                  // for targets that change size a lot: capture a fixed area (this big) so the picture and its mapping can never disagree for a frame
    property bool suppressOnResize: false                   // no blur at all while the target changes size (and shortly after): for shapes made of several layers, like the island
    property real quiet: 140                               // ms without changes before it stops tracking
    readonly property bool blurring: mb.enabled && mb._on && !mb._resizing
    readonly property real exposure: 0.0165 * mb.strength * mb.boost  // seconds the virtual shutter stays open

    property bool _moving: false
    property bool _on: false
    property real _vx: 0
    property real _vy: 0
    property real _zx: 0
    property real _zy: 0
    property real _lastX: 0
    property real _lastY: 0
    property real _lastW: 0
    property real _lastEx: 0
    property real _lastEy: 0
    property real _lastH: 0
    property bool _primed: false
    property bool _dirty: false
    property bool _resizing: false

    width: 0; height: 0

    function poke(ms) {
        if (!mb.enabled || !mb.target) return;
        if (!mb._moving) {
            mb._primed = false;
            mb._moving = true;
            src.scheduleUpdate();
        }
        quietTimer.interval = Math.max(mb.quiet, ms || 0);
        quietTimer.restart();
    }
    Timer {
        id: quietTimer
        interval: mb.quiet
        onTriggered: mb._moving = false
    }

    Connections {
        target: mb.enabled ? mb.target : null
        function onXChanged() { mb.poke(0); }
        function onYChanged() { mb.poke(0); }
        function onWidthChanged() { mb.poke(0); mb._dirty = true; dirtyTimer.restart(); if (mb.suppressOnResize) { mb._resizing = true; resizeTimer.restart(); } }
        function onHeightChanged() { mb.poke(0); mb._dirty = true; dirtyTimer.restart(); if (mb.suppressOnResize) { mb._resizing = true; resizeTimer.restart(); } }
    }
    Timer { id: resizeTimer; interval: 280; onTriggered: mb._resizing = false }
    Timer { id: dirtyTimer; interval: 110; onTriggered: { mb._dirty = false; src.scheduleUpdate(); } }
    Connections {
        target: mb.enabled && mb.target ? mb.target.parent : null
        function onXChanged() { mb.poke(0); }
        function onYChanged() { mb.poke(0); }
        function onWidthChanged() { mb.poke(0); }
        function onHeightChanged() { mb.poke(0); }
        function onScaleChanged() { mb.poke(0); }
    }
    onExtraXChanged: poke(0)
    onExtraYChanged: poke(0)
    onEnabledChanged: if (!enabled) { _moving = false; _on = false; }

    FrameAnimation {
        running: mb._moving
        onTriggered: {
            const t = mb.target;
            if (!t) return;
            // measured in the scene, so transforms of any ancestor (slides, scales, bounces) count too
            const p0 = t.mapToItem(null, 0, 0), p1 = t.mapToItem(null, t.width, t.height);
            const w = Math.max(1, Math.abs(p1.x - p0.x)), h = Math.max(1, Math.abs(p1.y - p0.y));
            // follow the point the item scales around, so growing in place is not read as moving
            const px = Math.min(p0.x, p1.x) + mb.anchorX * w, py = Math.min(p0.y, p1.y) + mb.anchorY * h;
            const ex = mb.extraX, ey = mb.extraY;
            if (!mb._primed) {
                mb._lastX = px; mb._lastY = py; mb._lastW = w; mb._lastH = h; mb._lastEx = ex; mb._lastEy = ey;
                mb._vx = 0; mb._vy = 0; mb._zx = 0; mb._zy = 0; mb._primed = true;
                return;
            }
            const dt = Math.max(0.001, frameTime);
            const k = 1 - Math.exp(-dt / 0.03);   // smoothing: a frame of jitter must not flicker the smear
            mb._vx += (((px - mb._lastX) + (ex - mb._lastEx) * mb.extraWeight) / dt - mb._vx) * k;
            mb._vy += (((py - mb._lastY) + (ey - mb._lastEy) * mb.extraWeight) / dt - mb._vy) * k;
            mb._zx += (((w - mb._lastW) / mb._lastW) / dt - mb._zx) * k;
            mb._zy += (((h - mb._lastH) / mb._lastH) / dt - mb._zy) * k;
            mb._lastX = px; mb._lastY = py; mb._lastW = w; mb._lastH = h; mb._lastEx = ex; mb._lastEy = ey;
            const smear = Math.hypot(mb._vx, mb._vy) * mb.exposure + Math.max(Math.abs(mb._zx) * w, Math.abs(mb._zy) * h) * mb.exposure * mb.zoomWeight;
            if (smear > 0.9) mb._on = true;
            else if (smear < 0.5) mb._on = false;
        }
    }

    readonly property real _tw: fixedSize.width > 0 ? fixedSize.width + 2 * pad : (target ? target.width + 2 * pad : 1)
    readonly property real _th: fixedSize.height > 0 ? fixedSize.height + 2 * pad : (target ? target.height + 2 * pad : 1)

    ShaderEffectSource {
        id: src
        parent: mb.parent
        sourceItem: mb.target
        sourceRect: mb.target ? Qt.rect(-mb.pad, -mb.pad, mb._tw, mb._th) : Qt.rect(0, 0, 1, 1)
        // the picture of the item only has to be redrawn when its content changes; just moving it does not change it
        live: mb._moving && (mb.liveContent || mb._dirty)
        hideSource: mb.blurring
        visible: false
    }
    // smear in px (along the motion) and the zoom over the exposure; the quad only has to cover what they can reach
    readonly property real _dxPx: { const l = Math.hypot(_vx, _vy) * exposure; const f = l > maxBlur ? maxBlur / l : 1; return _vx * exposure * f; }
    readonly property real _dyPx: { const l = Math.hypot(_vx, _vy) * exposure; const f = l > maxBlur ? maxBlur / l : 1; return _vy * exposure * f; }
    readonly property real _zxC: Math.max(-0.6, Math.min(0.6, _zx * exposure))
    readonly property real _zyC: Math.max(-0.6, Math.min(0.6, _zy * exposure))
    readonly property real insetX: Math.min(pad, Math.ceil(Math.abs(_dxPx) / 2 + Math.abs(_zxC) * (target ? target.width : 0) * 0.5) + 3)
    readonly property real insetY: Math.min(pad, Math.ceil(Math.abs(_dyPx) / 2 + Math.abs(_zyC) * (target ? target.height : 0) * 0.5) + 3)

    ShaderEffect {
        parent: mb.parent
        visible: mb.blurring
        enabled: false     // never takes input: the real item underneath keeps its mouse areas
        transform: mb.effectTransform
        x: mb.target ? mb.target.x - mb.insetX : 0
        y: mb.target ? mb.target.y - mb.insetY : 0
        z: mb.target ? mb.target.z : 0
        width: mb.target ? mb.target.width + 2 * mb.insetX : 1
        height: mb.target ? mb.target.height + 2 * mb.insetY : 1
        property var source: src
        property vector2d dir: Qt.vector2d(mb._dxPx / mb._tw, mb._dyPx / mb._th)
        property vector2d zoom: Qt.vector2d(mb._zxC, mb._zyC)
        property vector2d anchor: Qt.vector2d((mb.pad + mb.anchorX * (mb.target ? mb.target.width : 0)) / mb._tw,
                                              (mb.pad + mb.anchorY * (mb.target ? mb.target.height : 0)) / mb._th)
        property vector4d uvRect: Qt.vector4d((mb.pad - mb.insetX) / mb._tw, (mb.pad - mb.insetY) / mb._th,
                                              (mb.target ? mb.target.width + 2 * mb.insetX : 1) / mb._tw,
                                              (mb.target ? mb.target.height + 2 * mb.insetY : 1) / mb._th)
        fragmentShader: Qt.resolvedUrl("motionblur.frag.qsb")
    }
}
