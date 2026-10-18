import QtQuick
import "../../../"

// Bar "Lyrics" module: only the lyric line currently playing.
// ALT+SUPER+A shows/hides it (bar.lyricsHidden, see Main.qml handleCommand).
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
        visible: !root.rating && root.resultText === ""
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
        visible: root.hasBg && !root.rating && root.resultText === ""
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: barWindow ? barWindow.s(7) : 7
        elide: Text.ElideRight
        text: Lyrics.activeBgText
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Bold
        font.pixelSize: barWindow ? barWindow.s(10) : 10
        color: ThemeBackend.peach
    }

    // ---- rate how well the lyrics synced ----
    // Click the module: five stars for the song on screen, or for the one that just
    // ended (a small ★ shows for a minute after a song ends). The rating goes to
    // astrax-lyrics-rating, which keeps the best-scored lyrics for every player to use.
    property bool rating: false
    property var ratingTarget: null
    property int hoverStar: 0
    property string resultText: ""
    readonly property bool hasPending: Lyrics.pendingRate !== null && !rating && resultText === ""

    function openRating() {
        let t = Lyrics.pendingRate || Lyrics.currentSnapshot();
        if (!t) return;
        ratingTarget = t;
        hoverStar = 0;
        rating = true;
        ratingTimer.restart();
    }
    Timer { id: ratingTimer; interval: 8000; onTriggered: root.rating = false }
    Timer { id: resultTimer; interval: 1600; onTriggered: root.resultText = "" }
    Connections {
        target: Lyrics
        function onRated(saved, stars) {
            root.resultText = saved ? ("★ " + stars + "  saved") : ("★ " + stars);
            resultTimer.restart();
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.rating && root.resultText === ""
        cursorShape: (root.hasPending || Lyrics.hasLyrics) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.openRating()
    }

    Text {
        visible: root.hasPending
        anchors.right: parent.right
        anchors.rightMargin: barWindow ? barWindow.s(4) : 4
        anchors.verticalCenter: parent.verticalCenter
        text: "★"
        font.pixelSize: barWindow ? barWindow.s(11) : 11
        color: ThemeBackend.peach
    }

    Row {
        id: starsRow
        visible: root.rating
        anchors.centerIn: parent
        spacing: barWindow ? barWindow.s(2) : 2
        Repeater {
            model: 5
            Text {
                required property int index
                text: "★"
                font.pixelSize: barWindow ? barWindow.s(20) : 20
                color: index < root.hoverStar ? ThemeBackend.peach : Qt.rgba(1, 1, 1, 0.28)
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -2
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: { root.hoverStar = index + 1; ratingTimer.restart(); }
                    onClicked: {
                        Lyrics.rate(index + 1, root.ratingTarget);
                        root.rating = false;
                    }
                }
            }
        }
        onVisibleChanged: if (!visible) root.hoverStar = 0
    }

    Text {
        visible: root.resultText !== ""
        anchors.centerIn: parent
        text: root.resultText
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Bold
        font.pixelSize: barWindow ? barWindow.s(13) : 13
        color: ThemeBackend.peach
    }
}
