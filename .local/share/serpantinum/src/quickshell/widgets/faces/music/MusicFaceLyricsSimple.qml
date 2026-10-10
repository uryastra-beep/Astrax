import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import "../../../reusables"
import "../../../"

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 180
    property real minHeight: 60
    property real maxWidth: 2400
    property real maxHeight: 1200
    property real minAspect: 0.5
    property real maxAspect: 8.0
    property bool isRound: false

    property bool lyricsSubscribed: false

    property int lyricsLines: 1
    property string lyricsAlignment: "left"

    function getThemePrimaryColor() {
        if (typeof ThemeBackend !== "undefined") {
            if (ThemeBackend.primary) return Qt.color(ThemeBackend.primary);
            if (ThemeBackend.blue) return Qt.color(ThemeBackend.blue);
            if (ThemeBackend.mauve) return Qt.color(ThemeBackend.mauve);
        }
        if (typeof MprisController !== "undefined" && MprisController.primaryColor) {
            return Qt.color(MprisController.primaryColor);
        }
        return Qt.color("#89b4fa");
    }

    function syncSubscription() {
        if (root.visible && !root.lyricsSubscribed) {
            root.lyricsSubscribed = true;
            Lyrics.subscribe();
        } else if (!root.visible && root.lyricsSubscribed) {
            root.lyricsSubscribed = false;
            Lyrics.unsubscribe();
        }
    }

    readonly property color primaryColor: getThemePrimaryColor()
    // light purple + thin black outline (custom)
    readonly property color activeLineColor: {
        if (typeof ThemeBackend === "undefined" || !ThemeBackend.tvGirl) return "#d8b4fe";
        const c = ThemeBackend.tvLyricCycle;
        if (c && c.length > 0) return Qt.color(c[Math.max(Lyrics.currentIndex, 0) % c.length]);
        return ThemeBackend.mauve;
    }

    readonly property real sideMargin: Math.max(Scaler.s(12), root.width * 0.05)
    readonly property real refWidth: Scaler.s(320)
    readonly property real refHeight: Scaler.s(100)
    readonly property real effectiveSize: Math.sqrt((root.width / Math.max(1, refWidth)) * (root.height / Math.max(1, refHeight)))
    readonly property real fontScale: Math.pow(Math.max(0.3, effectiveSize), 0.38)

    readonly property real baseActiveFont: Math.max(Scaler.s(14), Math.min(root.height * 0.30, Scaler.s(19) * fontScale))

    onVisibleChanged: syncSubscription()

    Component.onCompleted: {
        syncSubscription();
    }

    Component.onDestruction: {
        if (root.lyricsSubscribed) {
            root.lyricsSubscribed = false;
            Lyrics.unsubscribe();
        }
    }

    LyricsView {
        id: lyricsViewport
        anchors.fill: parent
        alignment: root.lyricsAlignment
        singleWord: true
        showBackground: true
        visible: opacity > 0.0
        opacity: (Lyrics.isMediaActive && Lyrics.hasLyrics) ? 1.0 : 0.0
        linesBehind: Math.max(0, Math.min(4, Math.round(root.lyricsLines)))
        linesAfter: Math.max(0, Math.min(4, Math.round(root.lyricsLines)))
        sideMargin: root.sideMargin
        baseActiveFont: root.baseActiveFont
        lineHeight: Math.max(Scaler.s(18), root.baseActiveFont * 1.4)
        lineSpacing: Math.max(Scaler.s(2), root.baseActiveFont * 0.25)
        activeLineColor: root.activeLineColor
        inactiveLineColor: "#ffffff"
        textStyle: Text.Outline
        textStyleColor: "#000000"
        inactiveOpacity: 0.70
        fontFamily: (typeof ThemeBackend !== "undefined" && ThemeBackend.fontFamily) ? ThemeBackend.fontFamily : "sans-serif"

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowVerticalOffset: Scaler.s(1.5)
            shadowHorizontalOffset: 0
            shadowBlur: 0.35
            shadowOpacity: 0.55
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutQuad
            }
        }
    }

    // No lyrics: instead of "No lyrics available" it shows what's playing.
    // "Nothing playing" and "searching" stay as they were.
    readonly property string listeningText: {
        let t = MprisController.trackTitle;
        let a = MprisController.trackArtist;
        if (!t) return "";
        return a ? ("Listening to " + t + " - " + a) : ("Listening to " + t);
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - root.sideMargin * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        visible: !(Lyrics.isMediaActive && Lyrics.hasLyrics)
        style: Text.Outline
        styleColor: "#000000"
        text: {
            if (typeof I18n !== "undefined") {
                if (!Lyrics.isMediaActive) return "";
                if (Lyrics.loading) return I18n.t("music.searching_lyrics");
                return root.listeningText || I18n.t("music.no_lyrics");
            }
            if (!Lyrics.isMediaActive) return "";
            if (Lyrics.loading) return "Searching lyrics...";
            return root.listeningText || "No lyrics available";
        }
        font.family: (typeof ThemeBackend !== "undefined" && ThemeBackend.fontFamily) ? ThemeBackend.fontFamily : "sans-serif"
        font.weight: Font.DemiBold
        font.pixelSize: Scaler.s(12)
        color: (typeof ThemeBackend !== "undefined" && ThemeBackend.subtext0) ? ThemeBackend.subtext0 : "#a6adc8"

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowVerticalOffset: Scaler.s(1.5)
            shadowHorizontalOffset: 0
            shadowBlur: 0.35
            shadowOpacity: 0.55
        }
    }
}
