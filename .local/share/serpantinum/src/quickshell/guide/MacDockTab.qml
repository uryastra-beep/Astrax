import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../reusables/guide"

Item {
    id: dockTabRoot

    // Liquid Glass is unavailable while `opti` is on (the shells ignore the setting meanwhile)
    property bool optiOn: false
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/opti"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: dockTabRoot.optiOn = text().trim() === "on"
        onLoadFailed: dockTabRoot.optiOn = false
    }
    required property var rootObj
    required property int tabIndex
    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    readonly property var macDockSettings: Config.rawSettings.macDock || ({})
    function updateMacDock(key, value) {
        const next = JSON.parse(JSON.stringify(Config.getSetting("macDock", {}) || {}));
        if (key === "enabled") {
            const original = JSON.parse(JSON.stringify(Config.getSetting("dock", {}) || {}));
            if (value) {
                next.restoreDockEnabled = original.enabled !== false;
                original.enabled = false;
            } else original.enabled = next.restoreDockEnabled !== false;
            Config.setSetting("dock", original);
            // The Dock runs as a user service that Astrax installs but leaves disabled until it is
            // turned on here (and switches it off again with it).
            Quickshell.execDetached(["systemctl", "--user", value ? "enable" : "disable", "--now", "astrax-mac-dock.service"]);
        }
        next[key] = value;
        Config.setSetting("macDock", next);
    }


    Flickable {
        anchors.fill: parent; anchors.margins: rootObj.s(8)
        contentHeight: settingsCol.implicitHeight + 12
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: settingsCol
            width: parent.width
            spacing: rootObj.s(6)
            SettingsBlob {
                SettingsRow {
                    rootObj: dockTabRoot.rootObj
                    settingId: "macdock_enabled"; searchKeywords: "macOS Apple Dock custom auto hide"
                    icon: "󰀻"; title: "macOS Dock · Astrax Custom"
                    description: "Independent Dock with Liquid Glass, Apple icons and smooth magnification"
                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: dockTabRoot.macDockSettings.enabled === true
                        accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust; handleOffColor: ThemeBackend.text
                        onToggled: function(c) { dockTabRoot.updateMacDock("enabled", c); }
                    }
                }
                Repeater {
                    model: [
                        {key:"autoHide",title:"Auto hide",desc:"Reveal from the bottom edge; hide when the pointer leaves",fallback:false},
                        {key:"showInDesktop",title:"Show in Desktop",desc:"Keep visible when this screen's desktop has no open apps",fallback:false,subordinate:true},
                        {key:"magnification",title:"Magnification",desc:"Icons and their neighbours grow beneath the pointer",fallback:true},
                        {key:"glass",title:"Liquid Glass",desc:"Refracted edges and translucent window backdrop",fallback:true},
                        {key:"showRunning",title:"Show running apps",desc:"Running apps appear after the separator",fallback:true},
                        {key:"indicators",title:"Running indicators",desc:"A small dot below each open app",fallback:true},
                        {key:"allScreens",title:"Show on every screen",desc:"Off uses the primary screen",fallback:false},
                        {key:"reserveSpace",title:"Reserve desktop space",desc:"Keep windows above the Dock when auto hide is off",fallback:false}
                    ]
                    delegate: SettingsRow {
                        required property var modelData
                        visible: modelData.subordinate !== true || dockTabRoot.macDockSettings.autoHide === true
                        Layout.leftMargin: modelData.subordinate === true ? dockTabRoot.rootObj.s(20) : 0
                        rootObj: dockTabRoot.rootObj
                        icon: "󰀻"; title: modelData.title
                        description: modelData.key === "glass" && dockTabRoot.optiOn ? "Unavailable while opti is on (run: opti off)" : modelData.desc
                        Toggle {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            enabled: !(modelData.key === "glass" && dockTabRoot.optiOn)
                            opacity: modelData.key === "glass" && dockTabRoot.optiOn ? 0.45 : 1
                            checked: dockTabRoot.macDockSettings[modelData.key] !== undefined ? dockTabRoot.macDockSettings[modelData.key] : modelData.fallback
                            accentColor: ThemeBackend.mauve; baseColor: ThemeBackend.surface1
                            handleColor: ThemeBackend.crust; handleOffColor: ThemeBackend.text
                            onToggled: function(c) { dockTabRoot.updateMacDock(modelData.key, c); }
                        }
                    }
                }
                Repeater {
                    model: [
                        {key:"iconSize",title:"Icon size",from:32,to:64,step:2,value:48,unit:" px"},
                        {key:"zoom",title:"Magnification size",from:115,to:190,step:5,value:155,unit:"%"},
                        {key:"hideDelay",title:"Auto hide delay",from:150,to:1800,step:50,value:650,unit:" ms"}
                    ]
                    delegate: SettingsRow {
                        id: macSliderRow
                        required property var modelData
                        rootObj: dockTabRoot.rootObj
                        icon: "󰒓"; title: modelData.title
                        description: "macOS Dock · Astrax Custom"
                        Draggable {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitWidth: dockTabRoot.rootObj.s(200); implicitHeight: dockTabRoot.rootObj.s(18)
                            from: macSliderRow.modelData.from; to: macSliderRow.modelData.to
                            stepSize: macSliderRow.modelData.step; defaultValue: macSliderRow.modelData.value
                            showValueBubble: true
                            valueFormatter: function(v) { return Math.round(v)+macSliderRow.modelData.unit; }
                            value: dockTabRoot.macDockSettings[macSliderRow.modelData.key] !== undefined ? dockTabRoot.macDockSettings[macSliderRow.modelData.key] : macSliderRow.modelData.value
                            backgroundColor: ThemeBackend.surface0; accentColor: ThemeBackend.mauve
                            handleColor: ThemeBackend.text; handleBorderColor: ThemeBackend.mantle
                            onDragFinished: dockTabRoot.updateMacDock(macSliderRow.modelData.key, Math.round(value))
                        }
                    }
                }
                SettingsRow {
                    rootObj: dockTabRoot.rootObj; icon: "󰐕"; title: "Choose Dock apps"
                    description: "Right-click an icon → Keep in Dock / Remove from Dock. Shift-click opens a new instance."
                }
            }

        }
    }
}
