import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

// Settings for the Astrax Dynamic Island (astrax-island daemon). Everything is
// stored under the "island" key of settings.json; the island watches that file,
// so every change shows up live.
Item {
    id: islandTabRoot

    // Liquid Glass is unavailable while `opti` is on (the shells ignore the setting meanwhile)
    property bool optiOn: false
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/opti"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: islandTabRoot.optiOn = text().trim() === "on"
        onLoadFailed: islandTabRoot.optiOn = false
    }
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    readonly property var defaults: ({
        "overviewWidgets": ["clock", "batteries", "connections", "screenTime", "system", "files"],
        "trackScreenTime": true,
        "enabled": true,
        "replacePopups": true,
        "replaceOsd": true,
        "glass": false,
        "glassOpacity": 55,
        "glassRefraction": 60,
        "bounce": 60,
        "topMargin": 4,
        "posX": 50,
        "posY": 0,
        "followFocus": true,
        "showOnAllScreens": false,
        "hideWhenIdle": false,
        "notifSeconds": 5,
        "showMusic": true,
        "showLyrics": true,
        "showNotifications": true,
        "showVolume": true,
        "showMic": true,
        "showBrightness": true,
        "showLocks": true,
        "showAirplane": true,
        "showCharging": true,
        "showBluetooth": true,
        "showUsb": true,
        "showFiles": true,
        "showClipboard": true,
        "fileDirDownloads": true,
        "fileDirDocuments": true,
        "fileDirDesktop": true,
        "fileDirPictures": false,
        "fileDirVideos": false,
        "fileDirMusic": false
    })

    property var settings: {
        let s = (typeof Config !== "undefined" && Config.rawSettings) ? Config.rawSettings["island"] : undefined;
        return Object.assign({}, islandTabRoot.defaults, (s && typeof s === "object") ? s : {});
    }

    function val(key) { return islandTabRoot.settings[key]; }

    // ---- position picker state ----
    property bool selectorOpen: false
    property bool gridEnabled: false
    property bool showBarBox: true
    property int posX: Number(settings.posX)
    property int posY: Number(settings.posY)
    onSettingsChanged: {
        if (!posDebounce.running) {
            posX = Number(settings.posX);
            posY = Number(settings.posY);
        }
    }

    function savePos() {
        let current = JSON.parse(JSON.stringify(Object.assign({}, islandTabRoot.defaults,
            Config.getSetting("island", {}) || {})));
        current.posX = islandTabRoot.posX;
        current.posY = islandTabRoot.posY;
        Config.setSetting("island", current);
        islandTabRoot.settings = current;
    }
    Timer { id: posDebounce; interval: 100; onTriggered: islandTabRoot.savePos() }

    function applyPos(h, v) {
        islandTabRoot.posX = h;
        islandTabRoot.posY = v;
        posDebounce.stop();
        savePos();
    }

    function update(key, v) {
        let current = JSON.parse(JSON.stringify(Object.assign({}, islandTabRoot.defaults,
            Config.getSetting("island", {}) || {})));
        current[key] = v;
        Config.setSetting("island", current);
        islandTabRoot.settings = current;
    }

    readonly property var widgetCatalog: [
        {key: "clock", title: "Clock & date"}, {key: "batteries", title: "Device batteries"},
        {key: "connections", title: "Wi-Fi & Bluetooth"}, {key: "screenTime", title: "Screen Time"},
        {key: "system", title: "System & storage"}, {key: "files", title: "Files shortcut"}
    ]
    readonly property var overviewOrder: Array.isArray(settings.overviewWidgets) ? settings.overviewWidgets : defaults.overviewWidgets
    readonly property var widgetRows: {
        const ordered = [];
        for (const key of overviewOrder) { const row = widgetCatalog.find(w => w.key === key); if (row && !ordered.includes(row)) ordered.push(row); }
        for (const row of widgetCatalog) if (!ordered.includes(row)) ordered.push(row);
        return ordered;
    }
    function toggleWidget(key, enabled) {
        const order = overviewOrder.filter(k => k !== key);
        if (enabled) order.push(key);
        update("overviewWidgets", order);
    }
    function moveWidget(key, delta) {
        const order = overviewOrder.slice(); const i = order.indexOf(key); const j = i+delta;
        if (i < 0 || j < 0 || j >= order.length) return;
        const temp = order[i]; order[i] = order[j]; order[j] = temp;
        update("overviewWidgets", order);
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: rootObj.s(8)
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: rootObj.s(6)

            // ---- master switches ----
            SettingsBlob {
                Repeater {
                    model: [
                        { key: "enabled", icon: "󰟀", title: "Dynamic Island", desc: "Show the island at the top of the screen" },
                        { key: "replacePopups", icon: "󰂚", title: "Notifications in the island", desc: "Hide Serpantinum's notification popups; they appear in the island instead" },
                        { key: "replaceOsd", icon: "󰕾", title: "OSD in the island", desc: "Hide Serpantinum's volume / brightness / lock-key popups; the island shows them instead" }
                    ]
                    delegate: SettingsRow {
                        required property var modelData
                        rootObj: islandTabRoot.rootObj
                        icon: modelData.icon
                        title: modelData.title
                        description: modelData.desc
                        Toggle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            checked: Boolean(islandTabRoot.val(modelData.key))
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface1
                            handleColor: ThemeBackend.crust
                            handleOffColor: ThemeBackend.text
                            onToggled: function(c) { islandTabRoot.update(modelData.key, c); }
                        }
                    }
                }
            }


            // ---- position ----
            SettingsBlob {
                SettingsRow {
                    rootObj: islandTabRoot.rootObj
                    icon: "󰁍"
                    title: "Horizontal position (X)"
                    description: "0 = left edge, 50 = centered, 100 = right edge"
                    Draggable {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitWidth: islandTabRoot.rootObj.s(220)
                        implicitHeight: islandTabRoot.rootObj.s(18)
                        from: 0
                        to: 100
                        stepSize: 1
                        defaultValue: 50
                        showValueBubble: true
                        valueFormatter: function(v) { return Math.round(v) + " %" }
                        value: islandTabRoot.posX
                        backgroundColor: ThemeBackend.surface0
                        accentColor: ThemeBackend.mauve
                        handleColor: ThemeBackend.text
                        handleBorderColor: ThemeBackend.mantle
                        onMoved: function(val) {
                            islandTabRoot.posX = Math.round(val);
                            posDebounce.restart();
                        }
                        onDragFinished: {
                            posDebounce.stop();
                            islandTabRoot.savePos();
                        }
                    }
                }
                SettingsRow {
                    rootObj: islandTabRoot.rootObj
                    icon: "󰁝"
                    title: "Vertical position (Y)"
                    description: "0 = top, 100 = bottom"
                    Draggable {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitWidth: islandTabRoot.rootObj.s(220)
                        implicitHeight: islandTabRoot.rootObj.s(18)
                        from: 0
                        to: 100
                        stepSize: 1
                        defaultValue: 0
                        showValueBubble: true
                        valueFormatter: function(v) { return Math.round(v) + " %" }
                        value: islandTabRoot.posY
                        backgroundColor: ThemeBackend.surface0
                        accentColor: ThemeBackend.mauve
                        handleColor: ThemeBackend.text
                        handleBorderColor: ThemeBackend.mantle
                        onMoved: function(val) {
                            islandTabRoot.posY = Math.round(val);
                            posDebounce.restart();
                        }
                        onDragFinished: {
                            posDebounce.stop();
                            islandTabRoot.savePos();
                        }
                    }
                }

                SettingsRow {
                    id: posRow
                    rootObj: islandTabRoot.rootObj
                    icon: "󰍹"
                    title: "Place on screen"
                    titleBold: true
                    description: "Drag the island on a preview of your screen"
                    innerSpacing: (islandTabRoot.selectorOpen || posWrapper.implicitHeight > 0) ? rootObj.s(12) : 0
                    bottomSpacing: 0

                    ClickButton {
                        implicitHeight: rootObj.s(32)
                        horizontalPadding: rootObj.s(12)
                        buttonText: islandTabRoot.selectorOpen ? "Close the selector" : "Select on screen..."
                        buttonIcon: islandTabRoot.selectorOpen ? "󰅖" : "󰍹"
                        iconFontSize: rootObj.s(13)
                        textFontSize: rootObj.s(11)
                        accentColor: islandTabRoot.selectorOpen ? ThemeBackend.mauve : ThemeBackend.surface0
                        textColor: islandTabRoot.selectorOpen ? ThemeBackend.crust : ThemeBackend.text
                        cornerRadius: ThemeBackend.borderRadius
                        onClicked: islandTabRoot.selectorOpen = !islandTabRoot.selectorOpen
                    }

                    bottomContent: [
                        Item {
                            id: posWrapper
                            Layout.fillWidth: true
                            property bool isOpen: islandTabRoot.selectorOpen
                            clip: true
                            visible: implicitHeight > 0
                            opacity: isOpen ? 1.0 : 0.0
                            implicitHeight: isOpen ? posBox.implicitHeight : 0
                            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    Rectangle {
                        id: posBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        implicitHeight: posInner.implicitHeight + rootObj.s(24)
                        height: implicitHeight
                        radius: ThemeBackend.borderRadius
                        color: posGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface1, 0.35)

                        GlassFill {
                            id: posGlass
                            anchors.fill: parent
                            radius: parent.radius
                            tintColor: Qt.alpha(ThemeBackend.surface1, 0.35)
                            tintAmount: 0.25
                        }

                        ColumnLayout {
                            id: posInner
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: rootObj.s(12)
                            spacing: rootObj.s(10)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(6)

                                ClickButton {
                                    enabled: false
                                    Layout.preferredWidth: rootObj.s(140)
                                    implicitHeight: rootObj.s(26)
                                    cornerRadius: rootObj.s(6)
                                    horizontalPadding: rootObj.s(6)
                                    textFontSize: rootObj.s(11)
                                    accentColor: ThemeBackend.surface1
                                    textColor: "#ffffff"
                                    buttonText: "X: " + islandTabRoot.posX + "%  Y: " + islandTabRoot.posY + "%"
                                }

                                IconButton {
                                    size: rootObj.s(26)
                                    cornerRadius: rootObj.s(6)
                                    buttonIcon: "󰕰"
                                    iconFontSize: rootObj.s(13)
                                    accentColor: islandTabRoot.gridEnabled ? ThemeBackend.mauve : ThemeBackend.surface1
                                    textColor: islandTabRoot.gridEnabled ? ThemeBackend.crust : ThemeBackend.text
                                    onClicked: islandTabRoot.gridEnabled = !islandTabRoot.gridEnabled
                                }

                                IconButton {
                                    size: rootObj.s(26)
                                    cornerRadius: rootObj.s(6)
                                    buttonIcon: "󰑐"
                                    iconFontSize: rootObj.s(13)
                                    accentColor: ThemeBackend.surface1
                                    textColor: ThemeBackend.text
                                    onClicked: islandTabRoot.applyPos(50, 0)
                                }

                                Item { Layout.fillWidth: true }

                                RowLayout {
                                    spacing: rootObj.s(8)
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                                    Text {
                                        text: I18n.t("guide.common.show_bar", "Show bar")
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(11)
                                        color: ThemeBackend.subtext0
                                    }
                                    Toggle {
                                        checked: islandTabRoot.showBarBox
                                        accentColor: ThemeBackend.mauve
                                        baseColor: ThemeBackend.surface1
                                        handleColor: ThemeBackend.crust
                                        handleOffColor: ThemeBackend.text
                                        onToggled: function(c) { islandTabRoot.showBarBox = c; }
                                    }
                                }
                            }

                            ScreenPositionSelector {
                                id: islandSelector
                                Layout.fillWidth: true
                                horizontalPosition: islandTabRoot.posX
                                verticalPosition: islandTabRoot.posY
                                gridEnabled: islandTabRoot.gridEnabled
                                showBar: islandTabRoot.showBarBox
                                marginV: rootObj.s(12)
                                marginH: rootObj.s(16)
                                dragWidth: rootObj.s(120)
                                dragHeight: rootObj.s(26)

                                onPositionChanged: (hPos, vPos) => {
                                    islandTabRoot.posX = Math.round(hPos);
                                    islandTabRoot.posY = Math.round(vPos);
                                    posDebounce.restart();
                                }
                                onDragFinished: {
                                    posDebounce.stop();
                                    islandTabRoot.savePos();
                                }

                                // the draggable island preview: a black pill with the equalizer bars
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: "#000000"
                                    border.width: 1
                                    border.color: ThemeBackend.surface1

                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: rootObj.s(12)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: rootObj.s(2)
                                        Repeater {
                                            model: [6, 12, 8, 10]
                                            Rectangle {
                                                required property int modelData
                                                width: rootObj.s(3)
                                                height: rootObj.s(modelData)
                                                radius: width / 2
                                                color: ThemeBackend.mauve
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: rootObj.s(6)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.height - rootObj.s(10)
                                        height: width
                                        radius: width / 2
                                        color: ThemeBackend.surface1
                                    }
                                }
                            }
                        }
                    }


                        }
                    ]
                }
            }

            // ---- look ----
            SettingsBlob {
                SettingsRow {
                    rootObj: islandTabRoot.rootObj
                    icon: "󰧞"
                    title: "Liquid Glass"
                    description: islandTabRoot.optiOn ? "Unavailable while opti is on (run: opti off)" : "Translucent blurred material instead of solid black (off = like the real island)"
                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        enabled: !islandTabRoot.optiOn
                        opacity: islandTabRoot.optiOn ? 0.45 : 1
                        checked: Boolean(islandTabRoot.val("glass"))
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(c) { islandTabRoot.update("glass", c); }
                    }
                }
                Repeater {
                    model: [
                        { key: "glassOpacity", icon: "󰃟", title: "Glass opacity", desc: "Lower is clearer, higher is darker", from: 20, to: 95, step: 5, unit: " %", def: 55, glassOnly: true },
                        { key: "glassRefraction", icon: "󰋼", title: "Glass refraction", desc: "How much the rim of the glass bends what is behind it (0 = off)", from: 0, to: 100, step: 5, unit: " %", def: 60, glassOnly: true },
                        { key: "bounce", icon: "󰓅", title: "Spring bounce", desc: "0 = smooth, 100 = very springy", from: 0, to: 100, step: 5, unit: "", def: 60 },
                        { key: "topMargin", icon: "󰁝", title: "Edge margin", desc: "Gap kept between the island and the screen edge", from: 0, to: 40, step: 1, unit: " px", def: 4 },
                        { key: "notifSeconds", icon: "󰔛", title: "Notification time", desc: "How long a notification stays", from: 2, to: 15, step: 1, unit: " s", def: 5 }
                    ]
                    delegate: SettingsRow {
                        id: sliderRow
                        required property var modelData
                        // glass-only options disappear while Liquid Glass is off
                        visible: !modelData.glassOnly || Boolean(islandTabRoot.val("glass"))
                        rootObj: islandTabRoot.rootObj
                        icon: modelData.icon
                        title: modelData.title
                        description: modelData.desc
                        Draggable {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: islandTabRoot.rootObj.s(220)
                            implicitHeight: islandTabRoot.rootObj.s(18)
                            from: sliderRow.modelData.from
                            to: sliderRow.modelData.to
                            stepSize: sliderRow.modelData.step
                            defaultValue: sliderRow.modelData.def
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v) + sliderRow.modelData.unit }
                            value: Number(islandTabRoot.val(sliderRow.modelData.key))
                            backgroundColor: ThemeBackend.surface0
                            accentColor: ThemeBackend.mauve
                            handleColor: ThemeBackend.text
                            handleBorderColor: ThemeBackend.mantle
                            onDragFinished: islandTabRoot.update(sliderRow.modelData.key, Math.round(value))
                        }
                    }
                }
                Repeater {
                    model: [
                        { key: "showOnAllScreens", icon: "󰍹", title: "Show on all screens", desc: "Show the island on every connected screen; off = focused screen only" },
                        { key: "hideWhenIdle", icon: "󰈉", title: "Hide when idle", desc: "Only show the island when something happens" }
                    ]
                    delegate: SettingsRow {
                        required property var modelData
                        rootObj: islandTabRoot.rootObj
                        icon: modelData.icon
                        title: modelData.title
                        description: modelData.desc
                        Toggle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            checked: Boolean(islandTabRoot.val(modelData.key))
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface1
                            handleColor: ThemeBackend.crust
                            handleOffColor: ThemeBackend.text
                            onToggled: function(c) { islandTabRoot.update(modelData.key, c); }
                        }
                    }
                }
            }

            SettingsBlob {
                SettingsRow {
                    rootObj: islandTabRoot.rootObj
                    icon: "󰕮"; title: "Overview widgets"
                    description: "Double right-click panel · choose widgets and arrange them top to bottom"
                }
                Repeater {
                    model: islandTabRoot.widgetRows
                    delegate: SettingsRow {
                        required property var modelData
                        rootObj: islandTabRoot.rootObj
                        icon: "󰕮"; title: modelData.title
                        description: islandTabRoot.overviewOrder.indexOf(modelData.key) >= 0 ? "Position " + (islandTabRoot.overviewOrder.indexOf(modelData.key)+1) : "Not in the panel · enable to add"
                        RowLayout {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: 8
                            Button { text: "↑"; enabled: islandTabRoot.overviewOrder.indexOf(modelData.key) > 0; onClicked: islandTabRoot.moveWidget(modelData.key, -1) }
                            Button { text: "↓"; enabled: islandTabRoot.overviewOrder.indexOf(modelData.key) >= 0 && islandTabRoot.overviewOrder.indexOf(modelData.key) < islandTabRoot.overviewOrder.length-1; onClicked: islandTabRoot.moveWidget(modelData.key, 1) }
                            Toggle {
                                checked: islandTabRoot.overviewOrder.indexOf(modelData.key) >= 0
                                accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface1
                                handleColor: ThemeBackend.crust; handleOffColor: ThemeBackend.text
                                onToggled: function(c) { islandTabRoot.toggleWidget(modelData.key, c); }
                            }
                        }
                    }
                }
                SettingsRow {
                    rootObj: islandTabRoot.rootObj
                    icon: "󰥔"; title: "Track PC Screen Time"
                    description: "Local estimate from now · pauses after 1 minute away · keeps 7 days; hiding the widget does not stop tracking"
                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: islandTabRoot.val("trackScreenTime") !== false
                        accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust; handleOffColor: ThemeBackend.text
                        onToggled: function(c) { islandTabRoot.update("trackScreenTime", c); }
                    }
                }
                SettingsRow {
                    rootObj: islandTabRoot.rootObj
                    icon: "󰑓"; title: "Restore widget layout"
                    description: "Restore the default order and show all six widgets"
                    Button { Layout.alignment: Qt.AlignRight; text: "Reset"; onClicked: islandTabRoot.update("overviewWidgets", islandTabRoot.defaults.overviewWidgets.slice()) }
                }
            }

            // ---- what shows up ----
            SettingsBlob {
                Repeater {
                    model: [
                        { key: "showMusic", icon: "󰎆", title: "Music", desc: "Now playing, with controls when expanded" },
                        { key: "showLyrics", icon: "󰍬", title: "Word-by-word lyrics", desc: "Astrax lyrics for the music on this PC (and a connected phone) in the media panel" },
                        { key: "showNotifications", icon: "󰂚", title: "Notifications", desc: "Messages and alerts from apps" },
                        { key: "showVolume", icon: "󰕾", title: "Volume", desc: "Output volume and mute" },
                        { key: "showMic", icon: "󰍬", title: "Microphone", desc: "Mic volume and mute" },
                        { key: "showBrightness", icon: "󰃠", title: "Brightness", desc: "Screen brightness" },
                        { key: "showLocks", icon: "󰪛", title: "Caps / Num Lock", desc: "Keyboard lock keys" },
                        { key: "showAirplane", icon: "󰀝", title: "Airplane mode", desc: "Wi-Fi and Bluetooth radios off / on" },
                        { key: "showCharging", icon: "󰂄", title: "Charging", desc: "Plug in, unplug, full and low battery" },
                        { key: "showBluetooth", icon: "󰂯", title: "Bluetooth", desc: "Devices connecting and disconnecting" },
                        { key: "showUsb", icon: "󱇰", title: "USB", desc: "Devices plugged in or removed" },
                        { key: "showClipboard", icon: "󰆏", title: "Clipboard", desc: "Copying, cutting and pasting text, images and files (paste is announced by Ctrl+V)" },
                        { key: "showFiles", icon: "󰈔", title: "Files", desc: "Downloads, and files added, modified, renamed or deleted in the folders below" },
                        { key: "fileDirDownloads", icon: "󰉍", title: "Watch Downloads", desc: "Includes live download progress" },
                        { key: "fileDirDocuments", icon: "󰈙", title: "Watch Documents", desc: "~/Documents" },
                        { key: "fileDirDesktop", icon: "󰟀", title: "Watch Desktop", desc: "~/Desktop" },
                        { key: "fileDirPictures", icon: "󰋩", title: "Watch Pictures", desc: "~/Pictures (screenshots are skipped, Serpantinum announces those)" },
                        { key: "fileDirVideos", icon: "󰈫", title: "Watch Videos", desc: "~/Videos" },
                        { key: "fileDirMusic", icon: "󰎆", title: "Watch Music", desc: "~/Music" }
                    ]
                    delegate: SettingsRow {
                        required property var modelData
                        rootObj: islandTabRoot.rootObj
                        icon: modelData.icon
                        title: modelData.title
                        description: modelData.desc
                        Toggle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            checked: Boolean(islandTabRoot.val(modelData.key))
                            accentColor: ThemeBackend.mauve
                            baseColor: ThemeBackend.surface1
                            handleColor: ThemeBackend.crust
                            handleOffColor: ThemeBackend.text
                            onToggled: function(c) { islandTabRoot.update(modelData.key, c); }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: rootObj.s(12) }
        }
    }
}
