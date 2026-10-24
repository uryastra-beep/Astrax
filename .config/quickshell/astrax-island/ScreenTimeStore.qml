import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: tracker
    property bool enabled: true
    property bool ready: false
    property var history: ({})
    property string day: Qt.formatDateTime(new Date(), "yyyy-MM-dd")
    property double lastTick: Date.now()
    property int ticks: 0
    readonly property real seconds: history[day] ? history[day].seconds || 0 : 0
    readonly property var hours: history[day] ? history[day].hours || [] : []
    readonly property bool idle: idleWatch.isIdle
    IdleMonitor { id: idleWatch; enabled: tracker.enabled; timeout: 60; respectInhibitors: false; onIsIdleChanged: tracker.lastTick = Date.now() }
    FileView {
        id: storage
        path: Quickshell.env("HOME") + "/.local/state/astrax-island-screen-time.json"
        preload: true; atomicWrites: true; printErrors: false
        onLoaded: {
            try { const data = JSON.parse(text()); if (data && data.days && typeof data.days === "object") tracker.history = data.days; tracker.ready = true; }
            catch (e) { tracker.ready = false; }
        }
        onLoadFailed: { tracker.ready = true; Qt.callLater(tracker.save); }
    }
    function save() {
        if (ready) storage.setText(JSON.stringify({version: 1, days: history}));
    }
    function tick() {
        const now = new Date();
        const elapsed = (now.getTime()-lastTick)/1000;
        lastTick = now.getTime();
        day = Qt.formatDateTime(now, "yyyy-MM-dd");
        if (!ready || !enabled || idle || elapsed <= 0 || elapsed > 20) return;
        const next = Object.assign({}, history);
        const entry = next[day] ? {seconds: next[day].seconds || 0, hours: (next[day].hours || []).slice()} : {seconds: 0, hours: []};
        entry.seconds += elapsed;
        entry.hours[now.getHours()] = (entry.hours[now.getHours()] || 0) + elapsed;
        next[day] = entry;
        const keys = Object.keys(next).sort();
        while (keys.length > 7) delete next[keys.shift()];
        history = next;
        if (++ticks >= 6) { ticks = 0; save(); }
    }
    onEnabledChanged: { lastTick = Date.now(); if (!enabled) save(); }
    Timer { interval: 10000; repeat: true; running: true; onTriggered: tracker.tick() }
    Component.onDestruction: save()
}
