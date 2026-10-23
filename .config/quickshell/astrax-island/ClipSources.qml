import QtQuick
import Quickshell
import Quickshell.Io
import "FileIcons.js" as FI

// Clipboard activity: copy / cut (wl-paste --watch) and paste (Ctrl+V, announced by
// a non-consuming Hyprland bind that calls `ipc call island paste`). Text, images
// and files each get their own card; secrets flagged by password managers are skipped.
Item {
    id: clip

    property var cfg: ({})
    signal event(var ev)

    readonly property string script: Quickshell.shellPath("clip-event.sh")
    readonly property bool enabled: cfg.showClipboard !== false

    property bool ready: false
    Timer { interval: 2500; running: true; onTriggered: clip.ready = true }

    function paste() {
        if (!enabled || !ready) return;
        pasteProc.running = false;
        pasteProc.running = true;
    }

    // ignore the same content announced twice in a row (apps often rewrite the clipboard)
    property string lastKey: ""
    property double lastAt: 0

    function handle(line) {
        let j;
        try { j = JSON.parse(line); } catch (e) { return; }
        if (!clip.enabled) return;
        const key = j.state + "|" + (j.preview || j.path || j.thumb || "") + "|" + (j.chars || j.count || j.size || 0);
        const now = Date.now();
        if (j.state === "copied" && key === lastKey && now - lastAt < 1500) return;
        lastKey = key; lastAt = now;
        if (!clip.ready && j.state === "copied") return;      // the clipboard that was already there at startup

        const verb = j.state === "pasted" ? "Pasted" : (j.action === "cut" ? "Cut" : "Copied");
        const st = j.state === "pasted" ? "pasted" : (j.action === "cut" ? "cut" : "copied");
        let ev = { layout: "file", kind: "clip", state: st, replaceKey: "clip", duration: 2600 };
        if (j.kind === "text") {
            ev.name = j.preview;
            ev.sub = verb + " · " + (j.lines > 1 ? j.lines + " lines · " : "") + j.chars + " characters";
            ev.glyph = "󰦨";
        } else if (j.kind === "image") {
            ev.name = "Image";
            ev.sub = verb + (j.w > 0 ? " · " + j.w + " × " + j.h : "") + " · " + FI.fmtSize(j.size);
            ev.thumb = "file://" + j.thumb;
            ev.glyph = "󰋩";
            ev.openPath = j.thumb;
        } else if (j.kind === "files") {
            ev.name = j.count > 1 ? j.count + " files" : FI.base(j.path);
            ev.sub = verb + (j.count > 1 ? " · " + FI.base(j.path) + " and " + (j.count - 1) + " more" : "");
            ev.glyph = j.count > 1 ? "󰉖" : FI.glyphFor(j.path, false);
            ev.openPath = j.path;
        } else return;
        clip.event(ev);
    }

    Process {
        running: clip.enabled
        command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--watch", "sh", clip.script, "copied"]
        stdout: SplitParser { onRead: line => clip.handle(line) }
    }
    Process {
        id: pasteProc
        command: ["sh", clip.script, "pasted"]
        stdout: SplitParser { onRead: line => clip.handle(line) }
    }
}
