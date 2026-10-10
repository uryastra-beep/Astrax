import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Lyrics: synced lyrics of the current song, via "sptlrx pipe" (the
// same mechanism the lyrics widget in widgets2 already used).
// sptlrx talks MPRIS directly, it doesn't depend on which shell is
// running. Unlike widgets2 (a separate wlr-layer-shell surface),
// this is a native widget of Serpantinum's widget system: it's added
// via the editor, it's draggable/resizable and follows the theme.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property real minWidth: 200
    property real minHeight: 80
    property real maxWidth: 1400
    property real maxHeight: 500

    property string currentLyric: ""

    // sptlrx doesn't say in advance whether the current song HAS synced
    // lyrics or is purely instrumental -- all we know is
    // whether it ever emitted a non-empty line for THIS song. As long as
    // none has come through (instrumental, or sptlrx hasn't found
    // it yet), not even the music icon is shown -- once the
    // first line appears, the gaps between lines (songs with few
    // lyrics) show the icon instead of staying empty.
    property bool trackHasLyrics: false
    readonly property string trackKey: MprisController.trackArtist + "|" + MprisController.trackTitle
    onTrackKeyChanged: { root.trackHasLyrics = false; root.currentLyric = ""; }
    onCurrentLyricChanged: { if (root.currentLyric.length > 0) root.trackHasLyrics = true; }

    Process {
        id: sptlrxProc
        command: ["sptlrx", "pipe"]
        running: root.visible
        stdout: SplitParser {
            onRead: data => { root.currentLyric = data; }
        }
        onExited: sptlrxRestart.restart()
    }
    Timer { id: sptlrxRestart; interval: 500; onTriggered: sptlrxProc.running = root.visible }

    onVisibleChanged: {
        if (visible) sptlrxProc.running = true;
    }

    Text {
        anchors.centerIn: parent
        anchors.margins: Math.min(parent.width, parent.height) * 0.1
        width: parent.width - Math.min(parent.width, parent.height) * 0.2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        visible: root.currentLyric.length > 0
        text: root.currentLyric
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Black
        color: ThemeBackend.text
        // black outline: without it the text gets lost
        // on both very light and very dark wallpapers -- Text.Outline
        // is native QML support, no need for a second Text behind it.
        style: Text.Outline
        styleColor: "black"
        fontSizeMode: Text.Fit
        minimumPixelSize: 10
        font.pixelSize: Math.min(parent.width, parent.height) * 0.16
    }

    // Music icon: filler for the gaps INSIDE a song that
    // does have lyrics (few lines, with instrumental stretches between
    // them). If the song is 100% instrumental (no line ever
    // appeared) nothing is shown, not even this.
    Text {
        anchors.centerIn: parent
        visible: root.currentLyric.length === 0 && root.trackHasLyrics && MprisController.isPlaying
        text: "♫"
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Black
        color: ThemeBackend.text
        style: Text.Outline
        styleColor: "black"
        font.pixelSize: Math.min(parent.width, parent.height) * 0.22
    }
}
