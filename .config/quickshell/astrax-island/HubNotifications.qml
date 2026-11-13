import QtQuick
import Quickshell

// Hub tab "Notificaciones": the island's history as rounded rows (icon with an unread dot, title, body,
// time) and a footer "N notices · N new   Clear all". Click opens, right click or × removes.
Item {
    id: page
    required property var hub
    readonly property int rowH: 60
    readonly property int maxRows: 3
    readonly property var items: hub.notifItems
    readonly property int newCount: items.filter(n => n.kind !== "event" && n.read === false).length
    readonly property int preferredHeight: (items.length ? Math.min(maxRows, items.length) * (rowH + 6) - 6 : 96) + 34
    height: preferredHeight

    readonly property color fg: "#f5f5f7"
    readonly property color dim: "#8e8e93"

    ListView {
        id: list
        width: parent.width
        height: parent.height - 34
        clip: true; spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: page.items
        remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 140 } }
        displaced: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool isEv: modelData.kind === "event"
            width: list.width; height: page.rowH; radius: 16
            color: rowArea.containsMouse ? "#141417" : "#0e0e10"
            border.width: 1; border.color: "#14ffffff"
            Behavior on color { ColorAnimation { duration: 140 } }
            scale: rowArea.pressed ? 0.985 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Item {
                id: tile
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36
                AppIcon {
                    anchors.fill: parent; visible: !row.isEv; size: 36
                    app: row.modelData.app || ""; entry: row.modelData.entry || ""
                    icon: row.modelData.icon || ""; image: row.modelData.image || ""
                }
                Rectangle {
                    anchors.fill: parent; visible: row.isEv; radius: 10
                    color: Qt.rgba(Qt.color(row.modelData.accent || "#ffffff").r, Qt.color(row.modelData.accent || "#ffffff").g,
                                   Qt.color(row.modelData.accent || "#ffffff").b, 0.22)
                    Text {
                        anchors.centerIn: parent; visible: !row.modelData.thumb
                        text: row.modelData.glyph || ""; color: row.modelData.accent || "#ffffff"
                        font.family: page.hub.iconFont; font.pixelSize: 17
                    }
                    RoundedImage { anchors.fill: parent; radius: 10; visible: !!row.modelData.thumb; source: row.modelData.thumb || "" }
                }
                Rectangle {   // unread dot
                    visible: !row.isEv && row.modelData.read === false
                    x: parent.width - 7; y: -3
                    width: 10; height: 10; radius: 5; color: "#f5f5f7"
                    border.width: 2; border.color: "#0e0e10"
                }
            }
            Column {
                anchors.left: tile.right; anchors.leftMargin: 12
                anchors.right: stamp.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.summary || row.modelData.app || ""
                    color: page.fg; font.family: page.hub.textFont; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: (row.modelData.body || row.modelData.app || "").replace(/<[^>]*>/g, "").replace(/\n/g, " ")
                    color: page.dim; font.family: page.hub.textFont; font.pixelSize: 12
                }
            }
            Item {
                id: stamp
                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 24
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: page.hub.timeAgo(row.modelData.ts)
                    color: page.dim; font.family: "Adwaita Mono"; font.pixelSize: 11
                    opacity: rowArea.containsMouse ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 12
                    opacity: rowArea.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    color: delArea.containsMouse ? "#3a3a3e" : "#232326"
                    Text { anchors.centerIn: parent; text: "×"; color: page.fg; font.pixelSize: 16 }
                    MouseArea { id: delArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.hub.notifRemoved(row.modelData) }
                }
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent; hoverEnabled: true; z: -1
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: m => { if (m.button === Qt.RightButton) page.hub.notifRemoved(row.modelData); else page.hub.notifActivated(row.modelData); }
            }
        }
        Column {
            anchors.centerIn: parent; spacing: 6
            visible: !page.items.length
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: ""; color: "#3a3a3e"; font.family: page.hub.iconFont; font.pixelSize: 26 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "All caught up"; color: page.dim; font.family: page.hub.textFont; font.pixelSize: 13 }
        }
    }
    Row {
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
        height: 24; spacing: 18
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: page.items.length + (page.items.length === 1 ? " notice" : " notices") + " · " + page.newCount + (page.newCount === 1 ? " new" : " new")
            color: page.dim; font.family: page.hub.textFont; font.pixelSize: 12
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: page.items.length > 0
            text: "Clear all"; color: clrArea.containsMouse ? "#ffffff" : page.fg
            font.family: page.hub.textFont; font.pixelSize: 12; font.weight: Font.DemiBold
            MouseArea { id: clrArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.hub.notifClear() }
        }
    }
}
