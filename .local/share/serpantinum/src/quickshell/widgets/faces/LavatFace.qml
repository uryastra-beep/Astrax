import QtQuick
import Quickshell.Io
import "../../"

// Lavat: lava-lamp style metaballs, reimplemented natively in QML/Canvas
// (it used to be the "lavat" binary running inside a real kitty window --
// see widget4-ctl.sh). It's the ONLY one of the old
// widgets4 widgets that reacted to the current song color (via
// /tmp/widget-colors.json) -- the same reactivity is kept here.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 150
    property real minHeight: 120
    property real maxWidth: 1400
    property real maxHeight: 1000

    readonly property string colorsFile: "/tmp/widget-colors.json"
    property color primaryColor: "#cfbfeb"
    property color tertiaryColor: "#ffdcf0"

    property int ballCount: 10
    property var balls: []

    function hexToColor(hex) {
        if (!hex) return undefined;
        const h = hex.replace("#", "");
        if (h.length !== 6) return undefined;
        return Qt.rgba(parseInt(h.substr(0, 2), 16) / 255,
                        parseInt(h.substr(2, 2), 16) / 255,
                        parseInt(h.substr(4, 2), 16) / 255, 1);
    }

    FileView {
        path: root.colorsFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.primaryColor = root.hexToColor(c.primary) || root.primaryColor;
                root.tertiaryColor = root.hexToColor(c.tertiary) || root.tertiaryColor;
            } catch (e) {
                console.warn("LavatFace: could not parse widget-colors.json:", e);
            }
        }
        onLoadFailed: {
            root.primaryColor = "#cfbfeb";
            root.tertiaryColor = "#ffdcf0";
        }
    }

    function resetBalls() {
        const arr = [];
        for (let i = 0; i < root.ballCount; i++) {
            arr.push({
                x: Math.random() * canvas.width,
                y: Math.random() * canvas.height,
                vx: (Math.random() - 0.5) * 1.6,
                vy: (Math.random() - 0.5) * 1.6,
                r: canvas.width * (0.08 + Math.random() * 0.06)
            });
        }
        balls = arr;
    }

    onWidthChanged: resetBalls()
    onHeightChanged: resetBalls()
    Component.onCompleted: resetBalls()

    function colorRgb(c) {
        return Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255);
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.globalCompositeOperation = "source-over";
            ctx.fillStyle = "rgba(0,0,0,0)";
            ctx.fillRect(0, 0, width, height);

            ctx.globalCompositeOperation = "lighter";

            const primaryRgb = root.colorRgb(root.primaryColor);
            const tertiaryRgb = root.colorRgb(root.tertiaryColor);

            for (let i = 0; i < root.balls.length; i++) {
                const b = root.balls[i];
                const t = root.balls.length > 1 ? i / (root.balls.length - 1) : 0;
                const rgb = t < 0.5 ? primaryRgb : tertiaryRgb;

                const grad = ctx.createRadialGradient(b.x, b.y, 0, b.x, b.y, b.r);
                grad.addColorStop(0, "rgba(" + rgb + ", 0.9)");
                grad.addColorStop(0.6, "rgba(" + rgb + ", 0.45)");
                grad.addColorStop(1, "rgba(" + rgb + ", 0)");

                ctx.fillStyle = grad;
                ctx.beginPath();
                ctx.arc(b.x, b.y, b.r, 0, Math.PI * 2);
                ctx.fill();

                b.x += b.vx;
                b.y += b.vy;

                if (b.x - b.r < 0 || b.x + b.r > width) b.vx *= -1;
                if (b.y - b.r < 0 || b.y + b.r > height) b.vy *= -1;
                b.x = Math.max(b.r, Math.min(width - b.r, b.x));
                b.y = Math.max(b.r, Math.min(height - b.r, b.y));
            }
        }
    }

    Timer {
        interval: 33
        running: root.visible
        repeat: true
        onTriggered: canvas.requestPaint()
    }
}
