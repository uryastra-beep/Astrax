.pragma library

// Everything the window shows, as data. Keys are paths in Serpantinum's settings.json.
// Defaults (`def`) mirror what the island / dock use when a key is missing.

const IC = {
    island: "\u{f07c0}", emoji: "\u{f01f5}", dock: "\u{f10a9}", launcher: "\u{f0349}",
    theme: "\u{f03d8}", glass: "\u{f00b5}", motion: "\u{f04c5}", wallpaper: "\u{f02f9}", display: "\u{f0379}"
};

const nav = [
    { kind: "label", text: "Astrax" },
    { kind: "item", id: "island", icon: IC.island, label: "Island" },
    { kind: "item", id: "emoji", icon: IC.emoji, label: "Emoji & Clipboard" },
    { kind: "item", id: "dock", icon: IC.dock, label: "Dock" },
    { kind: "item", id: "launcher", icon: IC.launcher, label: "Launcher" },
    { kind: "label", text: "Desktop" },
    { kind: "item", id: "theme", icon: IC.theme, label: "Theme" },
    { kind: "item", id: "glass", icon: IC.glass, label: "Liquid Glass" },
    { kind: "item", id: "motion", icon: IC.motion, label: "Blur motion" },
    { kind: "item", id: "wallpaper", icon: IC.wallpaper, label: "Wallpaper" },
    { kind: "item", id: "display", icon: IC.display, label: "Display" }
];

function t(key, icon, title, desc, def) { return { type: "toggle", key: key, icon: icon, title: title, desc: desc || "", def: def }; }
function s(key, icon, title, desc, from, to, step, unit, def, showIf) {
    return { type: "slider", key: key, icon: icon, title: title, desc: desc || "", from: from, to: to, step: step, unit: unit || "", def: def, showIf: showIf };
}

function island() {
    const glass = { key: "island.glass", def: false };
    const asIsland = { key: "island.shape", eq: "island", def: "island" };
    const asNotch = { key: "island.shape", eq: "notch", def: "island" };
    return {
        title: "Dynamic Island",
        subtitle: "The pill (or notch) at the top of the screen. Changes apply as you move them.",
        groups: [
            { title: "General", rows: [
                t("island.enabled", "󰟀", "Dynamic Island", "Show the island. Off brings back the original launcher and switcher.", true),
                t("island.replacePopups", "󰂚", "Notifications in the island", "Hide Serpantinum's popups; they show in the island instead.", true),
                t("island.replaceOsd", "󰕾", "Volume and brightness in the island", "Hide the OSD; the island shows it instead.", true)
            ] },
            { title: "Shape and position", rows: [
                { type: "segmented", key: "island.shape", title: "Shape", desc: "A floating pill, or a notch that hangs from the top edge.", def: "island",
                  options: [{ value: "island", label: "Island" }, { value: "notch", label: "Notch" }] },
                s("island.notchWidth", "", "Notch width", "", 120, 320, 4, " px", 200, asNotch),
                s("island.notchHeight", "", "Notch height", "", 20, 48, 1, " px", 34, asNotch),
                s("island.topMargin", "󰁝", "Edge margin", "Gap between the island and the top of the screen.", 0, 40, 1, " px", 4, asIsland),
                s("island.posX", "", "Horizontal position", "0 is the left edge, 100 the right.", 0, 100, 1, " %", 50, asIsland),
                s("island.posY", "", "Vertical position", "Where it floats between the top and the bottom.", 0, 100, 1, " %", 0, asIsland)
            ] },
            { title: "Glass and motion", rows: [
                t("island.glass", "\u{f00b5}", "Liquid glass", "A see-through island with refraction. Off is solid black.", false),
                s("island.glassOpacity", "󰃟", "Glass opacity", "Lower is clearer, higher is darker.", 20, 95, 5, " %", 55, glass),
                s("island.glassRefraction", "󰋼", "Glass refraction", "How much the rim bends what is behind it.", 0, 100, 5, " %", 60, glass),
                s("island.bounce", "󰓅", "Spring bounce", "0 is smooth, 100 is very springy.", 0, 100, 5, "", 60),
                s("island.notifSeconds", "󰔛", "Notification time", "How long a notification stays.", 2, 15, 1, " s", 5)
            ] },
            { title: "Ask panel models", rows: [
                { type: "segmented", key: "island.askClaudeModel", title: "Claude", desc: "Model for quick questions in the island.", def: "haiku",
                  options: [{ value: "haiku", label: "Haiku" }, { value: "sonnet", label: "Sonnet" }, { value: "opus", label: "Opus" }] },
                { type: "segmented", key: "island.askCodexModel", title: "Codex", desc: "Auto uses Codex's own default.", def: "auto",
                  options: [{ value: "auto", label: "Auto" }, { value: "gpt-6.1-sol", label: "6.1 Sol" }, { value: "gpt-6.1-terra", label: "6.1 Terra" }, { value: "gpt-6-astra", label: "6 Astra" }, { value: "gpt-6-luna", label: "6 Luna" }] }
                ,{ type: "segmented", key: "island.askClaudeEffort", title: "Claude effort", desc: "How hard Claude thinks. Auto uses its default.", def: "auto",
                  options: [{ value: "auto", label: "Auto" }, { value: "low", label: "Low" }, { value: "medium", label: "Medium" }, { value: "high", label: "High" }, { value: "xhigh", label: "XHigh" }] },
                { type: "segmented", key: "island.askCodexEffort", title: "Codex effort", desc: "How hard Codex thinks. Auto uses its default.", def: "auto",
                  options: [{ value: "auto", label: "Auto" }, { value: "low", label: "Low" }, { value: "medium", label: "Medium" }, { value: "high", label: "High" }, { value: "xhigh", label: "XHigh" }] }
            ] },
            { title: "PC control", rows: [
                t("island.askControl", "󰆍", "Let Claude and Codex control the PC", "In the Ask panel they can run commands, open apps and edit files on their own, with no confirmation. Off keeps them read-only.", true)
            ] },
            { title: "Screens", rows: [
                t("island.showOnAllScreens", "󰍹", "Every screen", "Off shows it on the focused screen only.", false),
                t("island.hideWhenIdle", "󰈉", "Hide when idle", "Only appears when something happens.", false)
            ] },
            { title: "What it shows", rows: [
                t("island.showMusic", "󰎆", "Music", "Now playing, with controls when expanded.", true),
                t("island.showLyrics", "󰍬", "Lyrics", "Word-by-word lyrics in the media panel.", true),
                t("island.showNotifications", "󰂚", "Notifications", "", true),
                t("island.showVolume", "󰕾", "Volume", "", true),
                t("island.showMic", "󰍬", "Microphone", "", true),
                t("island.showBrightness", "󰃠", "Brightness", "", true),
                t("island.showLocks", "󰪛", "Caps and Num Lock", "", true),
                t("island.showAirplane", "󰀝", "Airplane mode", "", true),
                t("island.showCharging", "󰂄", "Charging", "Plug in, unplug, full and low battery.", true),
                t("island.showBluetooth", "󰂯", "Bluetooth", "Devices connecting and disconnecting.", true),
                t("island.showUsb", "󱇰", "USB", "Devices plugged in or removed.", true),
                t("island.showClipboard", "󰆏", "Clipboard", "Copy, cut and paste cards.", true),
                t("island.showFiles", "󰈔", "Files", "Downloads and changes in the folders below.", true)
            ] },
            { title: "Watched folders", rows: [
                t("island.fileDirDownloads", "󰉍", "Downloads", "Includes live download progress.", true),
                t("island.fileDirDocuments", "󰈙", "Documents", "", true),
                t("island.fileDirDesktop", "󰟀", "Desktop", "", true),
                t("island.fileDirPictures", "󰋩", "Pictures", "Screenshots are skipped.", false),
                t("island.fileDirVideos", "󰈫", "Videos", "", true),
                t("island.fileDirMusic", "󰎆", "Music", "", true)
            ] }
        ]
    };
}

function emoji() {
    return {
        title: "Emoji and Clipboard",
        subtitle: "Both open inside the island. With the island off they open in their own black window.",
        groups: [
            { title: "Emoji picker", rows: [
                { type: "keys", title: "Open the picker", desc: "Type to search, arrows to move, Enter to copy, Tab for the next category.", icon: "\u{f01f5}", keys: ["Super", "."] },
                { type: "action", title: "Frequently Used", desc: "Forget the emoji shown first in the picker.", icon: "\u{f0709}", label: "Clear",
                  command: ["sh", "-c", "rm -f \"$HOME/.local/state/astrax-island-emoji-recent.json\""] }
            ] },
            { title: "Clipboard history", rows: [
                { type: "keys", title: "Open the history", desc: "", icon: "\u{f018f}", keys: ["Super", "V"] },
                t("island.showClipboard", "󰆏", "Clipboard cards", "Show a card in the island when you copy, cut or paste.", true),
                { type: "action", title: "History", desc: "Deletes everything cliphist remembers. It cannot be undone.", icon: "\u{f01b4}", label: "Clear history", confirm: true,
                  command: ["sh", "-c", "cliphist wipe; rm -f \"${XDG_RUNTIME_DIR:-/tmp}\"/astrax-island/cliphist/*"] }
            ] }
        ]
    };
}

function dock() {
    const mag = { key: "macDock.magnification", def: true };
    return {
        title: "Dock",
        subtitle: "The macOS-style dock.",
        groups: [
            { title: "General", rows: [
                t("macDock.enabled", "\u{f10a9}", "Dock", "", true),
                t("macDock.allScreens", "\u{f0379}", "Every screen", "", true),
                t("macDock.reserveSpace", "\u{f084d}", "Reserve space", "Windows stop above the dock instead of going under it.", false),
                t("macDock.showInDesktop", "\u{f07c0}", "Show on the desktop", "Choose which screens keep the dock when they have no windows.", false),
                { type: "segmented", key: "macDock.desktopScreens", icon: "\u{f0379}", title: "On which screen", desc: "", def: "all",
                  options: [{ value: "all", label: "Both" }, { value: "hdmi", label: "HDMI" }, { value: "laptop", label: "Laptop" }],
                  showIf: { key: "macDock.showInDesktop", def: false } }
            ] },
            { title: "Size and zoom", rows: [
                s("macDock.iconSize", "\u{f0a68}", "Icon size", "", 32, 80, 2, " px", 48),
                t("macDock.magnification", "\u{f0349}", "Magnification", "Icons grow as the pointer gets close.", true),
                s("macDock.zoom", "", "Zoom", "", 100, 200, 5, " %", 155, mag)
            ] },
            { title: "Hiding", rows: [
                t("macDock.autoHide", "\u{f06d1}", "Hide automatically", "", true),
                s("macDock.hideDelay", "\u{f051b}", "Hide delay", "", 200, 2000, 50, " ms", 650, { key: "macDock.autoHide", def: true })
            ] },
            { title: "Look", rows: [
                { type: "segmented", key: "macDock.iconTint", icon: "\u{f03d8}", title: "Tinted icons", desc: "iOS-style: dark tile, glyph in one colour.", def: "off",
                  options: [{ value: "off", label: "Off" }, { value: "fixed", label: "Fixed" }, { value: "follow", label: "Astrax" }] },
                { type: "swatches", key: "macDock.iconTintColor", icon: "\u{f03d8}", title: "Tint colour", desc: "", def: "#9566ff",
                  colors: ["#9566ff", "#bc8cff", "#6c8cf0", "#4fb3d9", "#4fd1a1", "#e0a14f", "#ef7a6c", "#e56fb0"],
                  showIf: { key: "macDock.iconTint", eq: "fixed", def: "off" } },
                t("macDock.glass", "\u{f00b5}", "Glass", "", true),
                t("macDock.showRunning", "\u{f003b}", "Running apps", "Show apps that are open but not pinned.", true),
                t("macDock.indicators", "\u{f09df}", "Indicators", "A dot under apps that are open.", true),
                t("macDock.showLabels", "\u{f0316}", "Names", "", false)
            ] }
        ]
    };
}

function launcher() {
    return {
        title: "Launcher",
        subtitle: "Search and open apps.",
        groups: [
            { title: "Open it", rows: [
                { type: "keys", title: "Launcher", desc: "Tap Super on its own.", icon: "\u{f0349}", keys: ["Super"] },
                { type: "keys", title: "Window switcher", desc: "Up to four windows per row.", icon: "\u{f04e9}", keys: ["Alt", "Tab"] }
            ] },
            { title: "Serpantinum launcher", rows: [
                s("launcher.itemCount", "\u{f0279}", "Results shown", "", 3, 10, 1, "", 6),
                s("launcher.width", "\u{f084e}", "Width", "", 400, 900, 20, " px", 600),
                t("launcher.smartRanking", "\u{f04bf}", "Smart ranking", "Apps you open often come first.", true)
            ] }
        ]
    };
}

function theme() {
    return {
        title: "Theme",
        subtitle: "Shared by Serpantinum's windows.",
        groups: [
            { title: "Colors", rows: [
                t("theme.matugen", "\u{f03d8}", "Colors from the wallpaper", "Generate the palette from the current wallpaper.", true)
            ] },
            { title: "Shape", rows: [
                s("theme.borderRadius", "\u{f074a}", "Corner radius", "How round Serpantinum's panels are.", 0, 40, 1, " px", 24)
            ] }
        ]
    };
}

function wallpaper(dir) {
    return {
        title: "Wallpaper",
        subtitle: "Wallpapers live in one folder; Super+W picks them.",
        groups: [
            { title: "Folder", rows: [
                { type: "value", title: "Location", desc: "", icon: "\u{f0256}", text: dir || "" },
                { type: "action", title: "Open it", desc: "", icon: "\u{f0256}", label: "Open folder",
                  command: ["xdg-open", dir || "."] }
            ] },
            { title: "Shortcut", rows: [
                { type: "keys", title: "Wallpaper picker", desc: "", icon: "\u{f02f9}", keys: ["Super", "W"] }
            ] }
        ]
    };
}

function display(screens) {
    const rows = screens.map(sc => ({
        type: "value", title: sc.name, desc: sc.model || "", icon: "\u{f0379}",
        text: sc.width + " × " + sc.height + (sc.scale !== 1 ? " · " + sc.scale + "x" : "")
    }));
    return {
        title: "Display",
        subtitle: "The screens Astrax sees right now. Resolution and refresh stay in Hyprland's config.",
        groups: [{ title: "Screens", rows: rows }]
    };
}

function glass() {
    const isNew = { key: "liquidGlass.mode", eq: "new", def: "new" };
    return {
        title: "Liquid Glass",
        subtitle: "The glass look shared by the Dock, the island and the iPhone clock. Changes recompile the shader and reload them in a second.",
        groups: [
            { title: "Style", rows: [
                { type: "segmented", key: "liquidGlass.mode", title: "Look", desc: "Old is the original glass. New is the iOS 26 look: real chromatic aberration, a lens over the whole surface, frosted backdrop.", def: "new",
                  options: [{ value: "old", label: "Old" }, { value: "new", label: "New" }] }
            ] },
            { title: "Light and refraction", rows: [
                s("liquidGlass.refraction", "\u{f0a68}", "Refraction", "How much the glass bends what is behind it. 100 is the default.", 0, 200, 5, " %", 100, isNew),
                s("liquidGlass.chromatic", "\u{f0a68}", "Chromatic aberration", "The red / blue split along the edges.", 0, 300, 5, " %", 100, isNew),
                s("liquidGlass.lens", "\u{f0a68}", "Lens", "How much the whole surface (not just the edges) magnifies and shifts the backdrop.", 0, 200, 5, " %", 100, isNew),
                s("liquidGlass.specular", "\u{f0a68}", "Edge highlight", "The thin bright line and the glint on the rim.", 0, 300, 5, " %", 100, isNew)
            ] },
            { title: "Backdrop", rows: [
                s("liquidGlass.blur", "\u{f0a68}", "Frost", "Blur of what is behind the glass, in tenths of a pixel. 30 is the default.", 0, 100, 5, "", 30, isNew),
                s("liquidGlass.vivid", "\u{f0a68}", "Vividness", "Colour boost behind the glass. 100 is neutral.", 60, 200, 2, " %", 122, isNew)
            ] }
        ]
    };
}

function motion() {
    const on = { key: "motionBlur.enabled", def: false };
    return {
        title: "Blur motion",
        subtitle: "Real motion blur: whatever moves or changes size is smeared along its movement, like a camera with the shutter open. At rest nothing changes.",
        groups: [
            { title: "General", rows: [
                t("motionBlur.enabled", "\u{f04c5}", "Blur motion", "Off by default. Turn it on to choose what gets it.", false),
                s("motionBlur.strength", "\u{f0a68}", "Strength", "How long the smear is. Low is subtle, high is a long exposure.", 10, 150, 5, " %", 60, on)
            ] },
            { title: "What gets it", rows: [
                t("motionBlur.dock", "\u{f10a9}", "Dock", "Icons while they zoom, bounce, slide aside, and when the Dock slides in.", true),
                t("motionBlur.island", "\u{f07c0}", "Dynamic Island", "The island and its panels when they move or swell. While the island grows or shrinks the effect stays off.", true),
                t("motionBlur.widgets", "\u{f0570}", "Widgets", "Desktop widgets when they move or change size.", true)
            ].map(r => { r.showIf = on; return r; }) }
        ]
    };
}

function build(id, extra) {
    switch (id) {
    case "emoji": return emoji();
    case "dock": return dock();
    case "motion": return motion();
    case "glass": return glass();
    case "launcher": return launcher();
    case "theme": return theme();
    case "wallpaper": return wallpaper(extra.wallpaperDir);
    case "display": return display(extra.screens || []);
    default: return island();
    }
}
