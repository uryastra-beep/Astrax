import QtQuick

// Argon look: a soft accent glow rising from the island's bottom edge. Put it as the first child of a
// panel that sits in the island with `inset` px margins: it reaches the island's edges and follows its
// rounded bottom (34 covers both the notch's 28 and the floating island's 34 without poking out).
Rectangle {
    id: glow
    property color accent: "#d97757"
    property real strength: 1
    property real inset: 24
    property real reach: 120          // how far above the panel's bottom edge the glow starts
    property real bottomRadius: 34
    function tint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a * strength); }
    x: -inset; width: parent ? parent.width + inset * 2 : 0
    y: parent ? parent.height - reach : 0
    height: reach + inset
    bottomLeftRadius: bottomRadius; bottomRightRadius: bottomRadius
    gradient: Gradient {
        GradientStop { position: 0.0; color: glow.tint(0) }
        GradientStop { position: 0.45; color: glow.tint(0.06) }
        GradientStop { position: 0.8; color: glow.tint(0.17) }
        GradientStop { position: 1.0; color: glow.tint(0.28) }
    }
}
