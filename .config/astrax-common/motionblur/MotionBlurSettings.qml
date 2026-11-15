pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reads the "Blur motion" section of Serpantinum's settings.json:
//   motionBlur: { enabled, strength (%), dock, island, widgets, ... }
// Each shell that imports this gets its own reader; the file is the single source of truth.
Singleton {
    id: s
    property var data: ({})
    readonly property bool enabled: data.enabled === true
    readonly property real strength: Math.max(0.1, Math.min(2.5, (data.strength !== undefined ? data.strength : 60) / 60))
    // is the effect on for this part of the desktop? (master switch plus the per-part choice, on by default)
    function on(part) { return enabled && data[part] !== false; }

    FileView {
        path: Quickshell.env("HOME") + "/.config/serpantinum/settings.json"
        watchChanges: true; preload: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { const j = JSON.parse(text()); s.data = j.motionBlur || {}; } catch (e) {} }
    }
}
