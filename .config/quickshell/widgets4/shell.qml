pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// widgets4: the "visual/behind apps" part of the mini desktop. The
// Now Playing + mini Cava panel was removed: Serpantinum already ships
// its own "vis"/media module in the bar, it was redundant. This file is
// kept as an empty wlr-layer-shell surface (click-through) only in case
// something else gets added here later; the mini terminal/btop/unimatrix/lavat are
// separate normal kitty windows (interactive, they can't be click-through) --
// handled by widget4-ctl.sh + widget4_visibility.py, not this file.
//
// Unlike widgets2/3 (tied to a MONITOR, always visible on
// any workspace of that monitor), widgets4 is tied to a specific
// WORKSPACE: widget4_visibility.py calls "qs ipc call widgets4 setVisible
// true|false" to show/hide it depending on whether that workspace is the active
// one right now -- that's why the IpcHandler below exists.
ShellRoot {
    id: root

    // Synchronous via env var (WIDGETS4_MONITOR, set by widget4-ctl.sh before
    // launching "qs -c widgets4") -- NOT via file/FileView. See the same
    // note in widgets2/widgets3/shell.qml: zwlr_layer_shell_v1 fixes the
    // output when the surface is created; if "screen:" changes only after
    // it's mapped, Quickshell doesn't move it and it stays invisible forever.
    property string targetMonitor: Quickshell.env("WIDGETS4_MONITOR") || ""

    property bool shown: true // controlled by widget4_visibility.py via IPC

    // widget4-ctl.sh/widget4_visibility.py control visibility based on the
    // target workspace (active/not active right now).
    IpcHandler {
        target: "widgets4"
        function setVisible(visible: string): void { root.shown = (visible === "true"); }
        function isVisible(): bool { return root.shown; }
    }

    PanelWindow {
        id: win

        screen: {
            if (!root.targetMonitor) return null;
            const found = Quickshell.screens.find(s => s.name === root.targetMonitor);
            return found || null;
        }

        WlrLayershell.namespace: "widgets4"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        color: "transparent"
        exclusiveZone: 0
        mask: Region {} // fully click-through
        visible: root.shown

        anchors { left: true; right: true; top: true; bottom: true }
    }
}
