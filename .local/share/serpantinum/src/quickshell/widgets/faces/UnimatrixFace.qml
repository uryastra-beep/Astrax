import QtQuick
import "../../"

// Unimatrix: Matrix-style character rain, reimplemented natively in
// QML/Canvas (it used to be the "unimatrix" binary running inside a
// real kitty window -- see widget4-ctl.sh). Purely
// decorative, doesn't react to the song color (same as the original,
// which always ran in green by default).
//
Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 120
    property real minHeight: 100
    property real maxWidth: 1400
    property real maxHeight: 1000

    readonly property int fontSize: 16
    readonly property string glyphs: "アイウエオカキクケコサシスセソタチツテト0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    property var cols: []

    function resetColumns() {
        const count = Math.max(1, Math.floor(canvas.width / fontSize));
        const arr = [];
        for (let i = 0; i < count; i++) {
            arr.push({
                y: -Math.floor(Math.random() * 40),
                speed: 0.4 + Math.random() * 0.9,
                len: 8 + Math.floor(Math.random() * 14)
            });
        }
        cols = arr;
    }

    onWidthChanged: resetColumns()
    onHeightChanged: resetColumns()
    Component.onCompleted: resetColumns()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            const ctx = getContext("2d");
            const rows = Math.ceil(height / root.fontSize) + 2;

            // fade instead of clearing completely: leaves the classic matrix trail
            ctx.fillStyle = "rgba(0, 0, 0, 0.18)";
            ctx.fillRect(0, 0, width, height);

            ctx.font = root.fontSize + "px monospace";
            ctx.textBaseline = "top";

            for (let i = 0; i < root.cols.length; i++) {
                const col = root.cols[i];
                const x = i * root.fontSize;

                for (let j = 0; j < col.len; j++) {
                    const rowY = col.y - j;
                    if (rowY < 0 || rowY > rows) continue;
                    const py = rowY * root.fontSize;
                    const ch = root.glyphs[Math.floor(Math.random() * root.glyphs.length)];

                    if (j === 0) {
                        ctx.fillStyle = "#d8ffe4";
                    } else {
                        const fade = 1 - (j / col.len);
                        ctx.fillStyle = "rgba(" + root.matrixRgb + ", " + Math.max(0.05, fade) + ")";
                    }
                    ctx.fillText(ch, x, py);
                }

                col.y += col.speed;
                if ((col.y - col.len) * root.fontSize > height) {
                    col.y = -Math.floor(Math.random() * 20);
                    col.speed = 0.4 + Math.random() * 0.9;
                    col.len = 8 + Math.floor(Math.random() * 14);
                }
            }
        }
    }

    // Fixed classic matrix green (not tied to the theme): the original always
    // ran green by default regardless of wallpaper/theme, and the
    // current theme maps "green" to white (monochrome) -- using ThemeBackend.green
    // here completely lost the effect's visual identity.
    readonly property string matrixRgb: "51,255,87"

    Timer {
        interval: 60
        running: root.visible
        repeat: true
        onTriggered: canvas.requestPaint()
    }
}
