import QtQuick
import Quickshell
import Quickshell.Io

// Double right-click panel, NotchPixel style: a row of tab icons at the top and one page at a time below.
// Tabs: Web · Notifications · Clipboard · Widgets · Controls · Call · Overview (the old Overview),
// and a gear that opens the settings. Music and files are not here: they have their own island views.
// Pages are loaded only while shown; the focus timer lives here so it keeps running between opens.
Item {
    id: hub
    property bool opened: false
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    property string tab: "widgets"
    signal tabPicked(string id)
    // pages get the hub through this: inside their Component, `hub: hub` would point at their own property
    readonly property Item selfRef: hub

    // ---- Resumen (Overview) passthrough
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.6
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property var widgetOrder: []
    property real screenSeconds: 0
    property var screenHours: []
    property bool screenIdle: false
    property int fileCount: 0
    signal filesRequested()

    // ---- notifications passthrough
    property var notifItems: []
    property var timeAgo: ts => ""
    signal notifActivated(var item)
    signal notifRemoved(var item)
    signal notifClear()

    // ---- other hooks
    property string srpShell: ""
    signal openClipboardPanel()
    signal dismissed()

    readonly property var tabs: [
        { id: "web", glyph: "", name: "Web" },
        { id: "notif", glyph: "", name: "Notifications" },
        { id: "clip", glyph: "", name: "Clipboard" },
        { id: "widgets", glyph: "", name: "Widgets" },
        { id: "controls", glyph: "", name: "Controls" },
        { id: "call", glyph: "", name: "Call" },
        { id: "overview", glyph: "", name: "Overview" }
    ]
    readonly property int tabIndex: Math.max(0, tabs.findIndex(t => t.id === tab))
    readonly property int unread: notifItems.filter(n => n.kind !== "event" && n.read === false).length

    readonly property int barH: 30
    readonly property real pageH: page.item && page.item.preferredHeight ? page.item.preferredHeight : 170
    readonly property int preferredHeight: 48 + barH + 10 + Math.round(pageH)

    // ================================================================ focus timer (Pomodoro 25 + 5)
    readonly property int focusLen: 25 * 60
    readonly property int breakLen: 5 * 60
    property string focusPhase: "focus"          // "focus" | "break"
    property int focusLeft: focusLen
    property bool focusRunning: false
    readonly property int focusTotal: focusPhase === "focus" ? focusLen : breakLen
    Timer {
        interval: 1000; repeat: true; running: hub.focusRunning
        onTriggered: {
            if (hub.focusLeft > 1) { hub.focusLeft--; return; }
            const wasFocus = hub.focusPhase === "focus";
            hub.focusPhase = wasFocus ? "break" : "focus";
            hub.focusLeft = hub.focusTotal;
            focusBell.command = ["notify-send", "-a", "Focus", "-i", "alarm-symbolic",
                wasFocus ? "Break time" : "Back to focus",
                wasFocus ? "Five minutes to clear your head." : "Another 25 minutes."];
            focusBell.running = true;
        }
    }
    Process { id: focusBell }
    function focusToggle() { focusRunning = !focusRunning; }
    function focusReset() { focusRunning = false; focusPhase = "focus"; focusLeft = focusLen; }

    // ================================================================ tab bar
    Row {
        id: bar
        anchors.horizontalCenter: parent.horizontalCenter
        height: hub.barH; spacing: 4
        Repeater {
            model: hub.tabs
            Item {
                id: tabItem
                required property var modelData
                required property int index
                readonly property bool active: hub.tab === modelData.id
                width: 34; height: hub.barH
                Text {
                    anchors.centerIn: parent; anchors.verticalCenterOffset: -2
                    text: tabItem.modelData.glyph
                    color: tabItem.active ? "#f5f5f7" : tabArea.containsMouse ? "#b8b8bd" : "#6e6e73"
                    Behavior on color { ColorAnimation { duration: 160 } }
                    font.family: hub.iconFont; font.pixelSize: 15
                    scale: tabArea.pressed ? 0.88 : 1
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
                Rectangle {   // unread badge on the bell
                    visible: tabItem.modelData.id === "notif" && hub.unread > 0
                    x: parent.width / 2 + 4; y: 3
                    width: 7; height: 7; radius: 3.5; color: "#ff453a"
                    border.width: 1.5; border.color: "#000000"
                }
                MouseArea {
                    id: tabArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { hub.tab = tabItem.modelData.id; hub.tabPicked(tabItem.modelData.id); }
                }
            }
        }
        Rectangle { width: 1; height: 14; color: "#2a2a2e"; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -2 }
        Item {
            width: 34; height: hub.barH
            Text {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -2
                text: ""; color: gearArea.containsMouse ? "#b8b8bd" : "#6e6e73"
                Behavior on color { ColorAnimation { duration: 160 } }
                font.family: hub.iconFont; font.pixelSize: 15
            }
            MouseArea {
                id: gearArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["sh", "-c", "qs list --all 2>/dev/null | grep -q 'astrax-settings/shell.qml' || { qs -c astrax-settings -d >/tmp/astrax-settings.log 2>&1; sleep 1; }; qs -c astrax-settings ipc call settings toggle"]);
                    hub.dismissed();
                }
            }
        }
    }
    // active-tab dot, slides between tabs
    Rectangle {
        width: 4; height: 4; radius: 2; color: "#f5f5f7"
        y: hub.barH - 5
        x: bar.x + hub.tabIndex * 38 + 15
        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }

    // ================================================================ page
    Loader {
        id: page
        anchors.top: bar.bottom; anchors.topMargin: 10
        anchors.left: parent.left; anchors.right: parent.right
        height: hub.pageH
        active: hub.visible
        property int lastIndex: hub.tabIndex
        property int dir: 1
        sourceComponent: {
            switch (hub.tab) {
            case "web": return webPage;
            case "notif": return notifPage;
            case "clip": return clipPage;
            case "controls": return controlsPage;
            case "call": return callPage;
            case "overview": return overviewPage;
            default: return widgetsPage;
            }
        }
        onSourceComponentChanged: {
            dir = hub.tabIndex >= lastIndex ? 1 : -1;
            lastIndex = hub.tabIndex;
        }
        onLoaded: { item.opacity = 0; item.x = 14 * dir; enter.restart(); }
        ParallelAnimation {
            id: enter
            NumberAnimation { target: page.item; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { target: page.item; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        }
    }

    Component { id: widgetsPage; HubWidgets { hub: selfRef; width: page.width } }
    Component { id: controlsPage; HubControls { hub: selfRef; width: page.width } }
    Component { id: clipPage; HubClipboard { hub: selfRef; width: page.width } }
    Component { id: notifPage; HubNotifications { hub: selfRef; width: page.width } }
    Component { id: callPage; HubCall { hub: selfRef; width: page.width } }
    Component { id: webPage; HubWeb { hub: selfRef; width: page.width } }
    Component {
        id: overviewPage
        Overview {
            readonly property int preferredHeight: 300
            width: page.width; height: 300
            glassTexture: hub.glassTexture
            glassEnabled: hub.glassEnabled
            glassStrength: hub.glassStrength
            glassOrigin: Qt.point(hub.glassOrigin.x, hub.glassOrigin.y + page.y)
            glassScreen: hub.glassScreen
            widgetOrder: hub.widgetOrder
            screenSeconds: hub.screenSeconds
            screenHours: hub.screenHours
            screenIdle: hub.screenIdle
            textFont: hub.textFont; iconFont: hub.iconFont
            fileCount: hub.fileCount
            onFilesRequested: hub.filesRequested()
        }
    }
}
