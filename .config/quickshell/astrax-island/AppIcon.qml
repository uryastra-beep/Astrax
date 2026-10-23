import QtQuick
import Quickshell

// The icon of the app a notification comes from, in Apple's squircle proportions.
// Resolution order: a real image file (a screenshot thumbnail) -> the app's desktop
// entry -> the icon name the sender gave -> a generated tile (gradient + initial).
Item {
    id: ic
    property string app: ""
    property string entry: ""
    property string icon: ""
    property string image: ""
    property real size: 40
    width: size; height: size

    function isPath(s) { return s.startsWith("/") || s.startsWith("file://"); }
    function asUrl(s) { return s.startsWith("/") ? "file://" + s : s; }

    function resolve() {
        let img = ic.image.startsWith("image://icon/") ? ic.image.substring(13) : ic.image;
        let nm = ic.icon.startsWith("image://icon/") ? ic.icon.substring(13) : ic.icon;
        if (img !== "" && isPath(img)) return asUrl(img);                       // screenshot thumbnail etc.
        let e = ic.entry !== "" ? DesktopEntries.byId(ic.entry) : null;
        if (e && e.icon) return isPath(e.icon) ? asUrl(e.icon) : (Quickshell.iconPath(e.icon, true) || "");
        for (const n of [nm, img]) {
            if (n === "") continue;
            if (isPath(n) || n.startsWith("http")) return asUrl(n);
            if (n.indexOf("://") < 0) { const p = Quickshell.iconPath(n, true); if (p) return p; }
        }
        if (ic.app !== "" && ic.app !== "System") {
            e = DesktopEntries.heuristicLookup(ic.app);
            if (e && e.icon) return isPath(e.icon) ? asUrl(e.icon) : (Quickshell.iconPath(e.icon, true) || "");
        }
        return "";
    }

    readonly property string src: resolve()
    readonly property real hue: {
        let h = 0;
        for (let i = 0; i < ic.app.length; i++) h = (h * 31 + ic.app.charCodeAt(i)) % 360;
        return h / 360;
    }

    Rectangle {
        anchors.fill: parent
        visible: !img.loaded
        radius: ic.size * 0.225
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.hsla(ic.hue, 0.62, 0.58, 1) }
            GradientStop { position: 1.0; color: Qt.hsla((ic.hue + 0.06) % 1, 0.68, 0.40, 1) }
        }
        Text {
            anchors.centerIn: parent
            text: (ic.app || "!").charAt(0).toUpperCase()
            color: "#ffffff"
            font.family: "Rubik"; font.pixelSize: ic.size * 0.46; font.weight: Font.Bold
        }
    }
    RoundedImage {
        id: img
        anchors.fill: parent
        radius: ic.size * 0.225
        source: ic.src
    }
}
