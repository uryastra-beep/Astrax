import QtQuick
import "../../../"

// Bar "Lyrics" module: only the lyric line currently playing.
// SUPER+A shows/hides it (bar.lyricsHidden, see Main.qml handleCommand).
// Subscribes to Lyrics only while visible.
Item {
    id: root

    property var module: null
    property var widget: module

    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null
    readonly property bool isPreview: module ? !!module.isPreview : (!barWindow)

    property int configRevision: 0
    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsLoaded() { root.configRevision++; }
        function onRawSettingsChanged() { root.configRevision++; }
    }

    readonly property bool hiddenByUser: {
        let dummy = configRevision;
        return !isPreview && typeof Config !== "undefined" && !!Config.rawSettings && !!Config.rawSettings.bar && Config.rawSettings.bar.lyricsHidden === true;
    }
    readonly property bool shouldShow: !hiddenByUser && (module ? module.moduleActive : true)

    property bool isSubscribed: false
    onShouldShowChanged: syncSub()
    Component.onCompleted: syncSub()
    Component.onDestruction: { if (isSubscribed) { isSubscribed = false; Lyrics.unsubscribe(); } }
    function syncSub() {
        if (shouldShow && !isSubscribed) { isSubscribed = true; Lyrics.subscribe(); }
        else if (!shouldShow && isSubscribed) { isSubscribed = false; Lyrics.unsubscribe(); }
    }

    readonly property var line: (Lyrics.hasLyrics && Lyrics.currentIndex >= 0 && Lyrics.currentIndex < Lyrics.lyrics.length) ? Lyrics.lyrics[Lyrics.currentIndex] : null
    // Always word by word (like the simple lyrics widget); the
    // estimate for line-only songs lives in the Lyrics singleton.
    readonly property bool wordSynced: !!(line && line.words && line.words.length > 0)
    // activeWordText already estimates the timing when the line has no words
    readonly property string lineText: line ? Lyrics.activeWordText(line, Lyrics.currentPosition) : ""

    // fixed width (otherwise the bar shifts on every word)
    property real wordWidth: barWindow ? barWindow.s(150) : 150
    property real targetWidth: shouldShow ? wordWidth + pad * 2 : 0
    property real pad: barWindow ? barWindow.s(isCompact ? 12 : 16) : (isCompact ? 12 : 16)

    implicitWidth: targetWidth
    implicitHeight: parent ? parent.height : 0
    readonly property bool isFaceVisible: shouldShow

    readonly property bool hasBg: Lyrics.activeBgText !== ""
    // without background vocals the word is centred; with them it moves up and the background
    // vocals show below, smaller and in another color (kept until they stop)
    Text {
        id: lyricText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        height: root.hasBg ? parent.height * 0.56 : parent.height
        y: 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: root.hasBg ? Text.AlignBottom : Text.AlignVCenter
        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        // long line: shrink the text so it fits the max width
        // (otherwise it overlaps the other bar modules)
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: barWindow ? barWindow.s(8) : 8
        elide: Text.ElideRight
        text: root.lineText !== "" ? root.lineText : "♫"
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Black
        font.pixelSize: barWindow ? barWindow.s(root.isCompact ? 14 : 15) : (root.isCompact ? 14 : 15)
        color: ThemeBackend.lyricLineColor(Lyrics.currentIndex, ThemeBackend.mauve)
    }

    Text {
        id: bgText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.top: lyricText.bottom
        anchors.bottom: parent.bottom
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignTop
        visible: root.hasBg
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: barWindow ? barWindow.s(7) : 7
        elide: Text.ElideRight
        text: Lyrics.activeBgText
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Bold
        font.pixelSize: barWindow ? barWindow.s(10) : 10
        color: ThemeBackend.peach
    }
}
