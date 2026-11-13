import QtQuick
import Quickshell
import Quickshell.Io

// Emoji picker, iPhone style: "Frequently Used" first, then one section per category, a category bar
// at the bottom and Apple Color Emoji glyphs. Used inside the island (Super+.) and, with the island
// off, inside its own black rounded window (see shell.qml). Picking copies the emoji to the clipboard.
Item {
    id: panel
    property bool opened: false
    opacity: 0
    scale: 0.98
    transformOrigin: Item.Top
    ParallelAnimation {
        id: appear
        NumberAnimation { target: panel; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: panel; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    property var glassTexture: null
    property bool glassEnabled: false
    property real glassStrength: 0.5
    property point glassOrigin: Qt.point(0, 0)
    property vector2d glassScreen: Qt.vector2d(1, 1)
    property string textFont: "Rubik"
    property string iconFont: "Iosevka Nerd Font"
    signal dismissed()

    readonly property int cols: 9
    readonly property int cell: 54
    readonly property int headerH: 30
    readonly property int gridH: 270
    readonly property int maxRecent: 27
    readonly property int preferredHeight: 48 + 54 + gridH + 8 + 30 + 6 + 42

    readonly property var categories: [
        { title: "Smileys & People", glyph: "😀" },
        { title: "Animals & Nature", glyph: "🐻" },
        { title: "Food & Drink", glyph: "🍎" },
        { title: "Activity", glyph: "⚽" },
        { title: "Travel & Places", glyph: "🚗" },
        { title: "Objects", glyph: "💡" },
        { title: "Symbols", glyph: "🔣" },
        { title: "Flags", glyph: "🏁" },
        { title: "Symbols & Text", glyph: "→", text: true }
    ]
    // arrows, math, punctuation...: drawn with the text font instead of the emoji one
    property var textSet: ({})


    readonly property string emojiFont: "Noto Color Emoji"

    // ------------------------------------------------------------------ data
    property var all: []          // [emoji, name, category, keywords]
    property var recent: []       // most recent first
    property var rows: []         // list model: { kind: "h"|"e", title, items, start }
    property var flat: []         // every selectable emoji: { e, n, row, col }
    property var rowY: []
    property var sections: []     // { title, glyph, row, cat } (what the category bar scrolls to)
    property int selectedIndex: 0
    property int activeSection: 0
    readonly property string query: search.text.trim().toLowerCase()

    FileView {
        path: Quickshell.shellPath("emoji-data.json")
        preload: true; printErrors: false
        onLoaded: { try { panel.all = JSON.parse(text()); } catch (e) { panel.all = []; } }
    }
    FileView {
        id: recentStore
        path: Quickshell.env("HOME") + "/.local/state/astrax-island-emoji-recent.json"
        preload: true; atomicWrites: true; printErrors: false
        onLoaded: {
            try { const r = JSON.parse(text()); if (Array.isArray(r)) panel.recent = r.slice(0, panel.maxRecent); } catch (e) {}
        }
    }
    onAllChanged: { const t = {}; for (const it of all) if (it[2] === 8) t[it[0]] = true; textSet = t; rebuild(); }
    onRecentChanged: if (!opened) rebuild()
    onQueryChanged: { rebuild(); list.contentY = 0; }

    function matches() {
        const tokens = query.split(/\s+/).filter(t => t.length);
        const hits = [];
        for (const item of all) {
            const name = item[1].toLowerCase();
            const hay = name + " " + item[3].toLowerCase();
            let ok = true, score = 3;
            for (const t of tokens) {
                if (!hay.includes(t)) { ok = false; break; }
            }
            if (!ok) continue;
            if (name === query) score = 0;
            else if (name.startsWith(query)) score = 1;
            else if (name.includes(" " + tokens[0])) score = 2;
            hits.push({ item: item, score: score });
        }
        hits.sort((a, b) => a.score - b.score);
        return hits.slice(0, 180).map(h => h.item);
    }

    function rebuild() {
        const out = [], flatList = [], offs = [], secs = [];
        let y = 0;
        function header(title) { out.push({ kind: "h", title: title, items: [], start: 0 }); offs.push(y); y += headerH; }
        function grid(list) {
            for (let i = 0; i < list.length; i += cols) {
                const slice = list.slice(i, i + cols);
                const row = out.length, start = flatList.length;
                slice.forEach((it, c) => flatList.push({ e: it[0], n: it[1], row: row, col: c }));
                out.push({ kind: "e", title: "", items: slice.map(it => it[0]), start: start });
                offs.push(y); y += cell;
            }
        }
        if (query) {
            const found = matches();
            if (found.length) { header(found.length >= 180 ? "Top results" : "Results"); grid(found); }
        } else {
            const byEmoji = {};
            for (const it of all) byEmoji[it[0]] = it;
            const used = recent.map(e => byEmoji[e]).filter(x => x);
            if (used.length) {
                secs.push({ title: "Frequently Used", glyph: "🕘", row: out.length });
                header("Frequently Used"); grid(used);
            }
            for (let c = 0; c < categories.length; c++) {
                const inCat = all.filter(it => it[2] === c);
                if (!inCat.length) continue;
                secs.push({ title: categories[c].title, glyph: categories[c].glyph, text: categories[c].text === true, row: out.length });
                header(categories[c].title); grid(inCat);
            }
        }
        rows = out; flat = flatList; rowY = offs; sections = secs;
        selectedIndex = Math.max(0, Math.min(selectedIndex, flat.length - 1));
        activeSection = 0;
    }

    // ------------------------------------------------------------------ scroll / selection
    function rowTop(r) {
        // keep the section title in view when the first row of a section is selected
        return r > 0 && rows[r - 1] && rows[r - 1].kind === "h" ? rowY[r - 1] : rowY[r];
    }
    function scrollTo(target) {
        target = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), target));
        const current = rowScroll.running ? rowScroll.to : list.contentY;
        if (Math.abs(target - current) < 0.5) return;
        rowScroll.stop();
        rowScroll.from = list.contentY;
        rowScroll.to = target;
        rowScroll.start();
    }
    // The selector lives inside the scrolling content, so while the list scrolls it must not animate on its own
    // (the two motions would fight and leave it off its cell). snapSel pins it for the length of the scroll.
    property bool snapSel: false
    Timer { id: snapTimer; interval: 300; onTriggered: panel.snapSel = false }
    function startScroll(target) {
        snapSel = true; snapTimer.restart();
        scrollTo(target);
    }
    function select(index) {
        if (!flat.length) return;
        const idx = Math.max(0, Math.min(flat.length - 1, index));
        const it = flat[idx];
        const top = rowTop(it.row), bottom = rowY[it.row] + cell;
        const current = rowScroll.running ? rowScroll.to : list.contentY;
        if (top < current) startScroll(top);
        else if (bottom > current + list.height) startScroll(bottom - list.height);
        selectedIndex = idx;
    }
    function vertical(direction) {
        const it = flat[selectedIndex];
        if (!it) return;
        let r = it.row + direction;
        while (r >= 0 && r < rows.length && rows[r].kind !== "e") r += direction;
        if (r < 0 || r >= rows.length) return;
        const target = rows[r];
        select(target.start + Math.min(it.col, target.items.length - 1));
    }
    function jump(sectionIndex) {
        const sec = sections[sectionIndex];
        if (!sec || query) return;
        const first = rows[sec.row + 1];
        startScroll(rowY[sec.row]);
        if (first) selectedIndex = first.start;
    }

    // ------------------------------------------------------------------ pick
    // Detached on purpose: wl-copy forks to keep serving the selection, and tying it to a Process object
    // (and to its "running" flag) made later picks get ignored while the old one was still alive.
    function pick(entry) {
        if (!entry) return;
        Quickshell.execDetached(["wl-copy", "--", entry.e]);
        const next = [entry.e].concat(recent.filter(e => e !== entry.e)).slice(0, maxRecent);
        recent = next;
        recentStore.setText(JSON.stringify(next));
        dismissed();
    }

    onOpenedChanged: if (opened) {
        search.text = ""; selectedIndex = 0; rebuild(); list.contentY = 0; focusDelay.restart();
    }
    Component.onCompleted: { appear.start(); rebuild(); if (opened) focusDelay.restart(); }
    Timer { id: focusDelay; interval: 80; onTriggered: if (panel.opened) navigation.forceActiveFocus() }

    Item {
        id: navigation
        focus: true
        Keys.onPressed: event => panel.key(event)
    }
    function key(event) {
        if (event.key === Qt.Key_Escape) dismissed();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) pick(flat[selectedIndex]);
        else if (event.key === Qt.Key_Left) select(selectedIndex - 1);
        else if (event.key === Qt.Key_Right) select(selectedIndex + 1);
        else if (event.key === Qt.Key_Up) vertical(-1);
        else if (event.key === Qt.Key_Down) vertical(1);
        else if (event.key === Qt.Key_Tab) jump(Math.max(0, Math.min(sections.length - 1, activeSection + (event.modifiers & Qt.ShiftModifier ? -1 : 1))));
        else if (!search.activeFocus && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && event.text.length && event.text >= " ") {
            search.text += event.text;
            search.forceActiveFocus();
            search.cursorPosition = search.text.length;
        }
        else return;
        event.accepted = true;
    }

    // ------------------------------------------------------------------ chrome
    // ---------------------------------------------------------------- Argon chrome
    readonly property color accent: "#ffcf4d"
    function tint(al) { return Qt.rgba(accent.r, accent.g, accent.b, al); }
    ArgonGlow { accent: panel.accent; reach: 150 }
    ArgonHeader {
        id: panelHeader
        glyph: "\uf118"; title: "Emoji"; accent: panel.accent
        textFont: panel.textFont; iconFont: panel.iconFont
        onCloseClicked: panel.dismissed()
    }
    ArgonBar {
        id: searchBox
        anchors.bottom: parent.bottom
        width: parent.width; accent: panel.accent
        iconFont: panel.iconFont; textFont: panel.textFont
        focused: search.activeFocus
        TextInput {
            id: search
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter; clip: true
            color: "#f5f5f7"; selectionColor: panel.accent
            cursorDelegate: Rectangle { width: 2; radius: 1; color: panel.accent }
            font.family: panel.textFont; font.pixelSize: 13
            anchors.rightMargin: selName.visible ? selName.width + 8 : 0
            onTextChanged: panel.selectedIndex = 0
            Keys.onPressed: event => panel.key(event)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Search emoji…"; color: "#7c7c82"; visible: !search.text; font: search.font }
        }
    }
    Text {   // name of the selected emoji, at the end of the bar
        id: selName
        parent: searchBox
        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 150); elide: Text.ElideRight
        visible: text !== ""
        text: panel.flat[panel.selectedIndex] ? panel.flat[panel.selectedIndex].n : ""
        color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 11
    }

    ListView {
        id: list
        y: panelHeader.height + 6; width: parent.width; height: panel.gridH
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: panel.rows
        onDraggingChanged: if (dragging) rowScroll.stop()
        onContentYChanged: {
            let a = 0;
            for (let i = 0; i < panel.sections.length; i++)
                if (panel.rowY[panel.sections[i].row] <= contentY + 18) a = i;
            if (a !== panel.activeSection) panel.activeSection = a;
        }
        NumberAnimation {
            id: rowScroll
            target: list; property: "contentY"
            duration: 240; easing.type: Easing.OutCubic
        }
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property real gridX: (list.width - panel.cols * panel.cell) / 2
            width: list.width
            height: modelData.kind === "h" ? panel.headerH : panel.cell
            Text {
                visible: row.modelData.kind === "h"
                x: row.gridX + 4; anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                text: row.modelData.title.toUpperCase()
                color: panel.tint(0.75); font.family: panel.textFont; font.pixelSize: 10; font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }
            Repeater {
                model: row.modelData.kind === "e" ? row.modelData.items : []
                delegate: Text {
                    required property string modelData
                    required property int index
                    x: row.gridX + index * panel.cell; width: panel.cell; height: panel.cell
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: modelData
                    readonly property bool plain: panel.textSet[modelData] === true
                    font.family: plain ? panel.textFont : panel.emojiFont; font.pixelSize: plain ? 24 : 31
                    color: "#f5f5f7"
                    fontSizeMode: plain ? Text.Fit : Text.FixedSize; minimumPixelSize: 11
                    leftPadding: 3; rightPadding: 3
                    scale: rowMouse.pressed && rowMouse.hoverCol === index ? 0.86 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent; hoverEnabled: true
                visible: row.modelData.kind === "e"
                // the list is a Flickable: without this it steals the press the moment the mouse moves a pixel
                // and the click never fires (you had to click again and again)
                preventStealing: true
                // always use the coordinates of the event itself: mouseX goes stale when the list scrolls under a still pointer
                property int hoverCol: -1
                function colAt(x) {
                    const c = Math.floor((x - row.gridX) / panel.cell);
                    return c >= 0 && c < row.modelData.items.length ? row.modelData.start + c : -1;
                }
                onPressed: m => { hoverCol = colAt(m.x) >= 0 ? colAt(m.x) - row.modelData.start : -1; }
                onPositionChanged: m => { const h = colAt(m.x); if (!rowScroll.running && h >= 0) panel.selectedIndex = h; }
                onClicked: m => { const h = colAt(m.x); if (h >= 0) panel.pick(panel.flat[h]); }
            }
        }
        Rectangle {
            id: selectionGlass
            parent: list.contentItem; z: 5
            readonly property var sel: panel.flat[panel.selectedIndex]
            visible: sel !== undefined
            x: sel ? (list.width - panel.cols * panel.cell) / 2 + sel.col * panel.cell + 2 : 0
            y: sel ? panel.rowY[sel.row] + 2 : 0
            width: panel.cell - 4; height: panel.cell - 4
            radius: 15; color: "transparent"; border.width: 1; border.color: panel.tint(0.42)
            Behavior on x { enabled: !rowScroll.running && !panel.snapSel; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !rowScroll.running && !panel.snapSel; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                GradientStop { position: 0; color: panel.tint(0.16) }
                GradientStop { position: 0.5; color: panel.tint(0.06) }
                GradientStop { position: 1; color: panel.tint(0.14) }
            }
            ShaderEffect {
                anchors.fill: parent
                visible: panel.glassEnabled && panel.glassTexture !== null && width > 1 && height > 1
                property var src: panel.glassTexture
                property real radius: selectionGlass.radius
                property real strength: panel.glassStrength
                property real band: 9
                property vector2d stretch: Qt.vector2d(1, 1)
                property vector2d size: Qt.vector2d(width, height)
                property vector2d origin: Qt.vector2d(panel.glassOrigin.x + list.x + selectionGlass.x,
                    panel.glassOrigin.y + list.y + selectionGlass.y - list.contentY)
                property vector2d screen: panel.glassScreen
                fragmentShader: Qt.resolvedUrl("glass-soft-blur.frag.qsb")
            }
        }
        Text {
            anchors.centerIn: parent; visible: !panel.flat.length
            text: panel.all.length ? "No emoji match" : ""
            color: "#8e8e93"; font.family: panel.textFont; font.pixelSize: 12
        }
    }

    // category bar
    Row {
        id: bar
        anchors.bottom: searchBox.top; anchors.bottomMargin: 6
        width: parent.width; height: 30
        opacity: panel.query ? 0.25 : 1
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Repeater {
            model: panel.sections
            delegate: Item {
                required property var modelData
                required property int index
                width: bar.width / Math.max(1, panel.sections.length); height: bar.height
                readonly property bool active: index === panel.activeSection && !panel.query
                Rectangle {
                    anchors.centerIn: parent; width: 32; height: 26; radius: 13
                    color: active ? panel.tint(0.22) : tabArea.containsMouse ? "#18ffffff" : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: modelData.glyph
                    font.family: modelData.text ? panel.textFont : panel.emojiFont; font.pixelSize: modelData.text ? 17 : 15
                    color: "#f5f5f7"
                    opacity: active ? 1 : 0.55
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; enabled: !panel.query; onClicked: panel.jump(index) }
            }
        }
    }
}
