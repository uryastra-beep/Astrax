import QtQuick
import Quickshell
import "AppleAppIcons.js" as AppleIcons

// The icon of the app a notification comes from, in Apple's squircle proportions.
// Resolution order: a real image file (a screenshot thumbnail) -> the app's desktop
// entry -> the icon name the sender gave -> a generated tile (gradient + initial).
Item {
    id: ic
    property bool appleStyle: false
    property string app: ""
    property string entry: ""
    property string icon: ""
    property string image: ""
    property real size: 40
    width: size; height: size

    function isPath(s) { return s.startsWith("/") || s.startsWith("file://"); }
    function asUrl(s) { return s.startsWith("/") ? "file://" + s : s; }

    // The Apple-style artwork is an optional download (`astrax-icons install`); it is not part of
    // the repo. Without the pack the probe below never gets ready and the normal icons are used.
    readonly property string packDir: "file://" + Quickshell.env("HOME") + "/.local/share/astrax/icons/"
    readonly property string appleAsset: {
        if (!appleStyle) return "";
        const entry = ic.entry !== "" ? DesktopEntries.byId(ic.entry) : null;
        const inferred = entry || (ic.app ? DesktopEntries.heuristicLookup(ic.app) : null);
        return AppleIcons.find([ic.entry, ic.app, ic.icon, inferred ? inferred.id : "", inferred ? inferred.name : ""]);
    }

    Image {
        id: appleProbe
        visible: false
        asynchronous: true
        source: ic.appleAsset !== "" ? ic.packDir + ic.appleAsset : ""
        sourceSize.width: 8; sourceSize.height: 8
    }
    readonly property bool useApple: ic.appleAsset !== "" && appleProbe.status === Image.Ready

    function resolve() {
        let img = ic.image.startsWith("image://icon/") ? ic.image.substring(13) : ic.image;
        let nm = ic.icon.startsWith("image://icon/") ? ic.icon.substring(13) : ic.icon;
        if (ic.useApple) return ic.packDir + ic.appleAsset;
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
        visible: ic.appleStyle && ic.useApple
        radius: ic.size * 0.225
        color: "#2c2c2e"
        border.width: ic.useApple ? 0 : 0.5
        border.color: "#20ffffff"
    }
    Rectangle {
        anchors.fill: parent
        visible: !img.loaded && !ic.useApple
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
