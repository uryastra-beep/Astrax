import QtQuick

// Rows share the island's single background, mask and rounded outline.
Item {
    id: stack
    required property var rows
    required property var events
    property bool expandedBody: false
    property string textFont: "Rubik"
    property color foreground: "#f5f5f7"
    property color secondary: Qt.rgba(1, 1, 1, 0.58)
    signal pressed(var event, int button)
    signal doublePressed(var event)
    signal actionRequested(var event, string action)
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        move: Transition {
            NumberAnimation { properties: "y"; duration: 280; easing.type: Easing.OutCubic }
        }
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }
        Repeater {
            model: stack.rows
            Item {
                id: row
                required property int token
                required property int index
                readonly property var event: stack.events[token] || null
                width: column.width
                height: Math.max(68, content.implicitHeight + 28)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => stack.pressed(row.event, mouse.button)
                    onDoubleClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) stack.doublePressed(row.event);
                        mouse.accepted = true;
                    }
                }
                AppIcon {
                    x: 14; y: 14; size: 40
                    app: row.event ? (row.event.app || "") : ""
                    entry: row.event ? (row.event.entry || "") : ""
                    icon: row.event ? (row.event.icon || "") : ""
                    image: row.event ? (row.event.image || "") : ""
                }
                Column {
                    id: content
                    x: 66; y: 14
                    width: Math.max(0, row.width - x - 16)
                    spacing: 2
                    Row {
                        spacing: 6
                        Text {
                            text: row.event ? String(row.event.app || "").toUpperCase() : ""
                            color: stack.secondary
                            font.family: stack.textFont; font.pixelSize: 10
                            font.weight: Font.DemiBold; font.letterSpacing: 0.6
                        }
                        Rectangle {
                            visible: !!row.event && row.event.urgent === true
                            width: 5; height: 5; radius: 2.5; color: "#ff453a"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Text {
                        width: parent.width
                        text: row.event ? (row.event.title || "") : ""
                        textFormat: Text.PlainText
                        color: stack.foreground; elide: Text.ElideRight
                        font.family: stack.textFont; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: row.event ? String(row.event.detail || "").replace(/<[^>]*>/g, "") : ""
                        textFormat: Text.PlainText
                        color: Qt.rgba(1, 1, 1, 0.78)
                        wrapMode: Text.Wrap; elide: Text.ElideRight
                        maximumLineCount: stack.expandedBody ? 7 : 2
                        font.family: stack.textFont; font.pixelSize: 13
                    }
                    Row {
                        id: actions
                        spacing: 8
                        topPadding: visible ? 6 : 0
                        readonly property var items: row.event && row.event.actions
                            ? row.event.actions.filter(a => a.id !== "default" && a.text !== "").slice(0, 3) : []
                        visible: items.length > 0
                        Repeater {
                            model: actions.items
                            Rectangle {
                                required property var modelData
                                height: 26; width: label.implicitWidth + 24; radius: 13
                                color: button.pressed ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                                Text {
                                    id: label
                                    anchors.centerIn: parent
                                    text: modelData.text; color: stack.foreground
                                    font.family: stack.textFont; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                MouseArea {
                                    id: button
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: stack.actionRequested(row.event, modelData.id)
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    visible: row.index < stack.rows.count - 1
                    x: 66; width: Math.max(0, parent.width - x - 16)
                    anchors.bottom: parent.bottom
                    height: 1; color: Qt.rgba(1, 1, 1, 0.10)
                }
            }
        }
    }
}
