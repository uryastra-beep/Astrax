import QtQuick
import Quickshell
import Quickshell.Io

// File activity for the island: downloads (live progress -> done / canceled) and
// files added, modified, renamed or deleted inside the folders chosen in
// Super+C > Dynamic Island. Uses inotifywait; bursts (an unzip, a git checkout)
// collapse into a single "12 items added" card.
//
// Emits event(ev) with layout "file":
//   state   progress | done | canceled | added | modified | deleted | renamed | batch
//   name    file name (or "N items")      sub  second line
//   glyph   Nerd Font glyph of the file type
//   path    what a click should open      replaceKey  later events with the same key replace this card in place
Item {
    id: fs

    property var cfg: ({})
    signal event(var ev)

    readonly property string home: Quickshell.env("HOME")
    readonly property var dirDefaults: ({ Downloads: true, Documents: true, Desktop: true, Pictures: false, Videos: false, Music: false })
    // English and Spanish folder names (the ones that do not exist are skipped by the watcher script)
    readonly property var dirNames: ({
        Downloads: ["Downloads", "Descargas"], Documents: ["Documents", "Documentos"], Desktop: ["Desktop", "Escritorio"],
        Pictures: ["Pictures", "Imágenes"], Videos: ["Videos", "Vídeos"], Music: ["Music", "Música"] })
    readonly property var dirs: {
        const out = [];
        for (const k in dirDefaults) {
            const on = cfg["fileDir" + k] !== undefined ? cfg["fileDir" + k] : dirDefaults[k];
            if (on) for (const n of dirNames[k]) out.push(home + "/" + n);
        }
        return out;
    }
    readonly property bool enabled: cfg.showFiles !== false && dirs.length > 0
    readonly property string dirsKey: dirs.join(":")

    property bool ready: false
    Timer { interval: 3000; running: true; onTriggered: fs.ready = true }

    // restart the watcher when the folder list changes
    property bool watching: false
    onDirsKeyChanged: { watching = false; restartWatch.restart(); }
    onEnabledChanged: { watching = false; restartWatch.restart(); }
    Timer { id: restartWatch; interval: 400; onTriggered: fs.watching = fs.enabled }
    Component.onCompleted: restartWatch.start()

    // ------------------------------------------------------------ helpers
    readonly property var dlExt: ["crdownload", "part", "download", "opdownload", "partial", "filepart"]
    function base(p) { return p.substring(p.lastIndexOf("/") + 1); }
    function dir(p) { return p.substring(0, p.lastIndexOf("/")); }
    function ext(p) { const b = base(p); const i = b.lastIndexOf("."); return i > 0 ? b.substring(i + 1).toLowerCase() : ""; }
    function isTemp(p) { return dlExt.indexOf(ext(p)) >= 0; }
    function stripTemp(p) { return p.substring(0, p.lastIndexOf(".")); }
    function folderName(p) { return base(dir(p)) || "Home"; }

    function glyphFor(p, isDir) {
        if (isDir) return "󰉋";
        const e = ext(p);
        if (["png","jpg","jpeg","gif","webp","svg","bmp","heic","avif"].indexOf(e) >= 0) return "󰋩";
        if (["mp4","mkv","mov","webm","avi","m4v"].indexOf(e) >= 0) return "󰈫";
        if (["mp3","flac","wav","ogg","m4a","opus","aac"].indexOf(e) >= 0) return "󰎆";
        if (e === "pdf") return "󰈦";
        if (["zip","rar","7z","tar","gz","xz","bz2","zst","iso"].indexOf(e) >= 0) return "󰗄";
        if (["doc","docx","odt","txt","md","rtf","pptx","xlsx","csv","ods"].indexOf(e) >= 0) return "󰈙";
        if (["py","js","ts","qml","rs","c","cpp","h","sh","lua","json","html","css","java","go"].indexOf(e) >= 0) return "󰅩";
        if (["exe","msi","appimage","deb","rpm","pkg"].indexOf(e) >= 0) return "󰏖";
        return "󰈔";
    }
    function fmtSize(b) {
        if (b < 1024) return b + " B";
        if (b < 1048576) return (b / 1024).toFixed(0) + " KB";
        if (b < 1073741824) return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + " MB";
        return (b / 1073741824).toFixed(2) + " GB";
    }
    function emit(state, path, extra) {
        const ev = Object.assign({
            layout: "file", kind: "file", state: state, name: base(path), path: path, glyph: glyphFor(path, false),
            duration: 3200, replaceKey: "file"
        }, extra || {});
        fs.event(ev);
    }

    // ---------------------------------------------------------- downloads
    property var tracked: ({})          // temp path -> { final, size, t }
    function dlLabel(t) { return t.final ? base(t.final) : "Download"; }

    function dlStart(p) {
        const t = { final: stripTemp(p), size: 0, last: 0, t0: Date.now() };
        // Chrome starts as "Unconfirmed 123.crdownload": keep the generic name until it is renamed
        if (/^Unconfirmed \d+$/.test(base(t.final))) t.final = "";
        tracked[p] = t;
        pollTimer.running = true;
        fs.emit("progress", p, { name: dlLabel(t), sub: "Starting…", replaceKey: "dl:" + p, duration: 4000, glyph: glyphFor(t.final || p, false), openDir: true });
    }
    function dlDone(finalPath, key) {
        if (key && tracked[key]) delete tracked[key];
        else key = null;
        if (Object.keys(tracked).length === 0) pollTimer.running = false;
        sizeOf.finalPath = finalPath;
        sizeOf.replaceKey = key ? "dl:" + key : "file";
        sizeOf.running = false;
        sizeOf.running = true;
    }
    function dlCancel(p) {
        const t = tracked[p];
        delete tracked[p];
        if (Object.keys(tracked).length === 0) pollTimer.running = false;
        if (!t) return;
        cancelTimer.pendingKey = p; cancelTimer.pendingName = dlLabel(t); cancelTimer.restart();
    }
    Timer {
        id: cancelTimer
        property string pendingKey: ""
        property string pendingName: ""
        interval: 900
        onTriggered: fs.emit("canceled", pendingKey, { name: pendingName, sub: "Download canceled", replaceKey: "dl:" + pendingKey, glyph: fs.glyphFor(pendingName, false) })
    }
    Process {
        id: sizeOf
        property string finalPath: ""
        property string replaceKey: "file"
        command: ["stat", "-c", "%s", sizeOf.finalPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const b = parseInt(this.text.trim());
                fs.emit("done", sizeOf.finalPath, { sub: "Downloaded" + (isNaN(b) ? "" : " · " + fs.fmtSize(b)), replaceKey: sizeOf.replaceKey, duration: 3400 });
            }
        }
    }

    // sizes of in-flight downloads, once a second -> live progress card
    Timer {
        id: pollTimer
        interval: 1000; repeat: true
        onTriggered: {
            statAll.command = ["sh", "-c", "for f in \"$@\"; do s=$(stat -c %s \"$f\" 2>/dev/null) && printf '%s|%s\\n' \"$s\" \"$f\"; done", "_"].concat(Object.keys(fs.tracked));
            statAll.running = false;
            statAll.running = true;
        }
    }
    Process {
        id: statAll
        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf("|");
                if (i < 0) return;
                const size = parseInt(line.substring(0, i)), p = line.substring(i + 1);
                const t = fs.tracked[p];
                if (!t) return;
                const rate = t.size > 0 ? Math.max(0, size - t.size) : 0;
                t.size = size;
                fs.emit("progress", p, { name: fs.dlLabel(t), replaceKey: "dl:" + p, duration: 4000,
                    glyph: fs.glyphFor(t.final || p, false), openDir: true,
                    sub: fs.fmtSize(size) + (rate > 0 ? " · " + fs.fmtSize(rate) + "/s" : "") });
            }
        }
    }

    // ------------------------------------------------- everything else
    property var created: ({})          // path -> ts of CREATE (so CLOSE_WRITE means "added")
    property var queue: []
    property double firstQueued: 0

    function enqueue(kind, path, isDir, extra) {
        if (!fs.ready) return;
        if (queue.length === 0) firstQueued = Date.now();
        queue.push(Object.assign({ kind: kind, path: path, isDir: isDir, t: Date.now() }, extra || {}));
        // flush when quiet for 450 ms, or at the latest 1.5 s after the first one
        flushTimer.interval = Math.max(60, Math.min(450, 1500 - (Date.now() - firstQueued)));
        flushTimer.restart();
    }
    Timer { id: flushTimer; onTriggered: fs.flush() }

    readonly property var labels: ({ added: "Added to", modified: "Modified in", deleted: "Removed from", renamed: "Renamed in" })
    function flush() {
        const q = queue; queue = [];
        if (q.length === 0) return;
        if (q.length === 1) {
            const e = q[0];
            if (e.kind === "renamed")
                fs.emit("renamed", e.path, { name: base(e.path), sub: "Renamed from " + e.from, glyph: glyphFor(e.path, e.isDir), openPath: e.path });
            else
                fs.emit(e.kind, e.path, { sub: labels[e.kind] + " " + folderName(e.path), glyph: glyphFor(e.path, e.isDir),
                                          openPath: e.kind === "deleted" ? dir(e.path) : e.path });
            return;
        }
        const counts = {};
        for (const e of q) counts[e.kind] = (counts[e.kind] || 0) + 1;
        let top = "added";
        for (const k in counts) if (counts[k] > (counts[top] || 0)) top = k;
        const folders = {};
        for (const e of q) folders[folderName(e.path)] = true;
        const fl = Object.keys(folders);
        fs.emit("batch", q[q.length - 1].path, { name: q.length + " items", count: q.length, batchKind: top, glyph: "󰉖",
            sub: labels[top] + " " + (fl.length === 1 ? fl[0] : fl.length + " folders"), openPath: dir(q[q.length - 1].path) });
    }

    // a MOVED_FROM with no matching MOVED_TO is a delete / move out (Trash)
    property var movedFrom: null
    Timer {
        id: movedFromTimer
        interval: 300
        onTriggered: {
            const m = fs.movedFrom; fs.movedFrom = null;
            if (!m) return;
            if (fs.isTemp(m.path)) fs.dlCancel(m.path);
            else fs.enqueue("deleted", m.path, m.isDir);
        }
    }

    function handle(flags, path) {
        // BrAIn persists its state frequently; these writes are not user file activity.
        if (/^brain\.sqlite3(?:-(?:wal|shm|journal))?$/i.test(base(path))) return;
        const isDir = flags.indexOf("ISDIR") >= 0;
        if (flags.indexOf("CREATE") >= 0) {
            if (!isDir && isTemp(path)) { dlStart(path); return; }
            created[path] = Date.now();
            if (isDir) enqueue("added", path, true);
        } else if (flags.indexOf("CLOSE_WRITE") >= 0) {
            if (isTemp(path)) return;
            const wasCreated = created[path] !== undefined;
            delete created[path];
            enqueue(wasCreated ? "added" : "modified", path, false);
        } else if (flags.indexOf("MOVED_FROM") >= 0) {
            if (movedFrom) { movedFromTimer.stop(); movedFromTimer.triggered(); }
            if (isTemp(path) && tracked[path]) {
                // a download's temp was renamed: a MOVED_TO right after says to what
                movedFrom = { path: path, isDir: false, temp: true };
            } else movedFrom = { path: path, isDir: isDir };
            movedFromTimer.restart();
        } else if (flags.indexOf("MOVED_TO") >= 0) {
            if (movedFrom && movedFrom.temp) {
                const m = movedFrom; movedFrom = null; movedFromTimer.stop();
                if (isTemp(path)) {
                    // Chrome: "Unconfirmed 123.crdownload" -> "name.pdf.crdownload": same download, now with its real name
                    const t = tracked[m.path]; delete tracked[m.path];
                    t.final = stripTemp(path); tracked[path] = t;
                } else dlDone(path, m.path);
                return;
            }
            if (movedFrom && !movedFrom.temp) {
                const m = movedFrom; movedFrom = null; movedFromTimer.stop();
                enqueue("renamed", path, isDir, { from: base(m.path) });
            } else enqueue("added", path, isDir);
        } else if (flags.indexOf("DELETE") >= 0) {
            if (isTemp(path)) { dlCancel(path); return; }
            const born = created[path];
            delete created[path];
            // created and removed within 2 s (lock files, SQLite journals, editor scratch): not worth a card
            const transient = (born !== undefined && Date.now() - born < 2000);
            if (transient || queue.some(e => e.path === path && e.kind === "added" && Date.now() - e.t < 2000)) {
                queue = queue.filter(e => e.path !== path);
                return;
            }
            enqueue("deleted", path, isDir);
        }
    }

    Process {
        running: fs.watching
        command: ["sh", "-c",
            "orig=$#; for d in \"$@\"; do [ -d \"$d\" ] && set -- \"$@\" \"$d\"; done; shift $orig; [ $# -eq 0 ] && exit 0; " +
            "exec setpriv --pdeathsig TERM inotifywait -m -r -q --exclude '(/\\.[^/]+(/|$)|/(node_modules|__pycache__|Screenshots|Recordings|Screencasts)(/|$)|~$|-(wal|shm|journal)$|\\.(swp|swx|tmp|temp|lock|lck)$)' " +
            "--format '%e|%w%f' -e create -e close_write -e delete -e moved_to -e moved_from \"$@\"",
            "_"].concat(fs.dirs)
        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf("|");
                if (i > 0) fs.handle(line.substring(0, i), line.substring(i + 1));
            }
        }
    }
}
