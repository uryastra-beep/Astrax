import QtQuick
import Quickshell

// iOS-style square clock: a near-black rounded square, 60 ticks around the edge (one per second, a bright trail behind the
// second hand that fades out) and the time in tall condensed white digits with round colon dots.
Item {
    id: root
    anchors.fill: parent

    property real minWidth: 120
    property real minHeight: 120
    property real maxWidth: 700
    property real maxHeight: 700
    property real minAspect: 0.9
    property real maxAspect: 1.1
    property bool isRound: false

    readonly property real sz: Math.min(width, height)
    property date now: new Date()
    readonly property int sec: now.getSeconds()
    readonly property int hour12: (now.getHours() % 12) || 12
    readonly property string minuteStr: Qt.formatDateTime(now, "mm")
    readonly property string hourTens: hour12 >= 10 ? "1" : ""
    readonly property string hourUnits: String(hour12 % 10)

    // Digits: a real condensed face if one is installed, else the closest one the system has
    FontLoader { id: barlow; source: "file://" + Quickshell.env("HOME") + "/.local/share/fonts/BarlowCondensed-Bold.ttf" }
    readonly property string face: barlow.status === FontLoader.Ready ? barlow.name : "Open Sans Condensed ExtraBold"
    readonly property real capRatio: barlow.status === FontLoader.Ready ? 0.70 : 0.714
    readonly property real squeeze: barlow.status === FontLoader.Ready ? 0.8 : 0.66
    readonly property real capH: sz * 0.367

    Timer { interval: 250; running: true; repeat: true; triggeredOnStart: true; onTriggered: { const d = new Date(); if (d.getSeconds() !== root.now.getSeconds() || d.getMinutes() !== root.now.getMinutes()) root.now = d; } }


    // One digit slot: when its value changes the digit ROLLS like the iPhone time-picker drum (measured from a recording):
    // the old digit turns up and away (foreshortened, fading) while the new one turns in from below. Only the slot that
    // changes spins; the others are not touched. Its width follows the glyph, so "1" <-> "10" glides.
    Component {
        id: digitComp
        Item {
            id: slot
            required property int index
            property string value: root.digit(parent.base + index)
            property string shown: value
            property string prev: ""
            property real spin: 1                                  // 0..1 progress of the roll (decelerates like the picker)
            // Drum: each row sits 40 deg further round a cylinder. Row pitch ~ a digit and a bit; things far from the
            // centre get shorter (cos), dimmer and are clipped by the card, like the wheel in the iPhone time picker.
            readonly property real rowAng: 40 * Math.PI / 180
            readonly property real pitch: root.capH * 1.30
            readonly property real dOld: -spin              // the old digit rolls up one row
            readonly property real dNew: 1 - spin            // the new one comes up from one row below
            function yAt(d) { return (pitch / rowAng) * Math.sin(d * rowAng); }
            function sAt(d) { return Math.max(0.05, Math.cos(d * rowAng)); }
            function aAt(d) { return Math.max(0, 1 - 0.45 * Math.abs(d)); }
            readonly property real targetW: cur.contentWidth * squeeze
            width: targetW
            height: cur.height
            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            onValueChanged: { prev = shown; shown = value; swap.restart(); }
            NumberAnimation { id: swap; target: slot; property: "spin"; from: 0; to: 1; duration: 620; easing.type: Easing.InOutQuad }
            Text {
                id: old
                text: slot.prev
                visible: slot.spin < 1 && slot.prev !== ""
                opacity: slot.aAt(slot.dOld) * (1 - Math.min(1, Math.max(0, (slot.spin - 0.55) / 0.45)))
                y: slot.yAt(slot.dOld)
                color: "#ffffff"; font.family: root.face; font.pixelSize: (root.capH / root.capRatio); font.weight: Font.Bold
                transform: [Scale { xScale: root.squeeze }, Scale { origin.y: old.height / 2; yScale: slot.sAt(slot.dOld) }]
            }
            Text {
                id: cur
                text: slot.shown
                opacity: slot.spin < 1 && slot.prev !== "" ? slot.aAt(slot.dNew) : 1
                y: slot.spin < 1 && slot.prev !== "" ? slot.yAt(slot.dNew) : 0
                color: "#ffffff"; font.family: root.face; font.pixelSize: (root.capH / root.capRatio); font.weight: Font.Bold
                transform: [Scale { xScale: root.squeeze }, Scale { origin.y: cur.height / 2; yScale: slot.spin < 1 && slot.prev !== "" ? slot.sAt(slot.dNew) : 1 }]
            }
        }
    }

    function digit(i) {
        if (i === 0) return root.hourTens;
        if (i === 1) return root.hourUnits;
        return root.minuteStr.charAt(i - 2);
    }

    // Where ray number k (0 = 12 o'clock, clockwise) meets a rounded square of half-size a and corner radius r
    function onPath(k, a, r) {
        const th = k * Math.PI / 30, dx = Math.sin(th), dy = -Math.cos(th);
        let t = a / Math.max(Math.abs(dx), Math.abs(dy));
        let px = t * dx, py = t * dy;
        const lim = a - r;
        if (Math.abs(px) > lim && Math.abs(py) > lim) {
            const cx = (dx < 0 ? -lim : lim), cy = (dy < 0 ? -lim : lim);
            const b = dx * cx + dy * cy;
            t = b + Math.sqrt(b * b - (cx * cx + cy * cy - r * r));
            px = t * dx; py = t * dy;
        }
        return Qt.point(px, py);
    }
    function tickColor(k) {
        const age = (root.sec - k + 60) % 60;           // 0 = the second being shown
        const f = age <= 30 ? 1 : (age >= 50 ? 0 : 1 - (age - 30) / 20);
        const lo = 0.31, v = lo + (1 - lo) * f;
        return Qt.rgba(v, v, v, 1);
    }

    Item {
        id: card
        width: root.sz; height: root.sz
        anchors.centerIn: parent

        Rectangle {
            anchors.fill: parent
            radius: root.sz * 0.175
            color: "#1a1a1a"
            border.width: 1; border.color: "#2a2a2a"
        }
        Repeater {
            model: 60
            Rectangle {
                required property int index
                readonly property point p: root.onPath(index, root.sz * 0.432, root.sz * 0.107)
                width: root.sz * 0.036; height: root.sz * 0.0085; radius: height / 2
                x: card.width / 2 + p.x - width / 2
                y: card.height / 2 + p.y - height / 2
                rotation: index * 6 - 90
                color: root.tickColor(index)
                Behavior on color { ColorAnimation { duration: 1000; easing.type: Easing.Linear } }
            }
        }
        // time (the drum is clipped to the inside of the card, inside the ticks)
        Item {
            id: drumClip
            anchors.centerIn: parent
            width: root.sz * 0.92; height: root.sz * 0.80
            clip: true
        Row {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -root.sz * 0.02
            spacing: root.sz * 0.026
            Row {
                property int base: 0
                anchors.verticalCenter: parent.verticalCenter
                Repeater { model: 2; delegate: digitComp }
            }
            Item {   // colon: two round dots
                width: root.sz * 0.067; height: root.capH
                anchors.verticalCenter: parent.verticalCenter
                Rectangle { width: parent.width; height: width; radius: width / 2; color: "#ffffff"; x: 0; y: root.capH * 0.26 - height / 2 }
                Rectangle { width: parent.width; height: width; radius: width / 2; color: "#ffffff"; x: 0; y: root.capH * 0.76 - height / 2 }
            }
            Row {
                property int base: 2
                anchors.verticalCenter: parent.verticalCenter
                Repeater { model: 2; delegate: digitComp }
            }
        }
        }
    }
}
