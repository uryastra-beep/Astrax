pragma Singleton
import QtQuick
import Quickshell

// Elevation in dark: tinted neutrals, one accent. Layers get lighter as they rise (window < sidebar < group < hover).
Singleton {
    readonly property color window: "#101015"
    readonly property color sidebar: "#15151b"
    readonly property color surface: "#1b1b22"
    readonly property color surfaceHi: "#24242d"
    readonly property color line: "#2b2b36"
    readonly property color text: "#ececf2"
    readonly property color textDim: "#9797a6"
    readonly property color accent: "#8f7cf4"
    readonly property color danger: "#e5646e"
    readonly property string font: "Rubik"
    readonly property string iconFont: "Iosevka Nerd Font"
    // type scale (5 sizes) and spacing (4/8)
    readonly property int t1: 11
    readonly property int t2: 13
    readonly property int t3: 15
    readonly property int t4: 22
    readonly property int t5: 30
    readonly property int sp1: 4
    readonly property int sp2: 8
    readonly property int sp3: 16
    readonly property int sp4: 24
    readonly property int sp5: 32
    readonly property int windowRadius: 36
    readonly property int groupRadius: 22
    readonly property int controlRadius: 12
    readonly property int rowH: 56      // touch target >= 44, whole row clickable
    readonly property int ease: 200
}
