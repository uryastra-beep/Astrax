pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Serpantinum's settings.json is the single source of truth (the island, dock... watch it).
// Reads are reactive; writes update the UI at once and are merged into the file by cfgset.py, one at a time.
Singleton {
    id: cfg
    property var data: ({})
    property int rev: 0
    readonly property string file: Quickshell.env("HOME") + "/.config/serpantinum/settings.json"
    readonly property string setter: Quickshell.shellPath("cfgset.py")
    property var queue: []

    FileView {
        path: cfg.file
        watchChanges: true; preload: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { cfg.data = JSON.parse(text()); cfg.rev++; } catch (e) {} }
    }

    function get(path, def) {
        void rev;
        let o = data;
        for (const k of path.split(".")) {
            if (o === undefined || o === null) return def;
            o = o[k];
        }
        return o === undefined ? def : o;
    }

    function set(path, value) {
        const ks = path.split(".");
        let o = data;
        for (let i = 0; i < ks.length - 1; i++) {
            if (typeof o[ks[i]] !== "object" || o[ks[i]] === null) o[ks[i]] = {};
            o = o[ks[i]];
        }
        o[ks[ks.length - 1]] = value;
        rev++;
        // a newer value for the same key replaces the one still waiting
        queue = queue.filter(q => q[0] !== path).concat([[path, JSON.stringify(value)]]);
        flush();
    }

    function flush() {
        if (writer.running || !queue.length) return;
        const next = queue[0];
        queue = queue.slice(1);
        writer.command = ["python3", cfg.setter, next[0], next[1]];
        writer.running = true;
    }
    Process { id: writer; onRunningChanged: if (!running) cfg.flush() }
}
