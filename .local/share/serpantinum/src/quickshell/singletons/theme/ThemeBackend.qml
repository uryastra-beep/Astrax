pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property string fontFamily: "Adwaita Mono"
    property int borderRadius: 8
    property int clampedBorderRadius: {
        const r = borderRadius;
        return Math.floor(
            r <= 24
                ? r
                : 24 + Math.pow(r - 24, 0.55)
        );
    }

    property real elementOpacity: 1.0
    property bool blurBackground: false
    property string blurStyle: "blur"
    readonly property real liquidGlassOpacity: 0.04
    readonly property bool glassActive: blurBackground && elementOpacity < 0.999
    readonly property bool liquidGlass: blurBackground && blurStyle === "liquid"

    // Tells island-blur.lua (Hyprland) when Serpantinum's liquid glass is on, so the compositor blur
    // it samples is enabled. No-op if the Lua side isn't loaded.
    onLiquidGlassChanged: srpGlassSync.restart()
    Timer {
        id: srpGlassSync
        interval: 80
        onTriggered: {
            if (srpGlassProcess.running) { restart(); return; }
            srpGlassProcess.command = ["hyprctl", "eval",
                "if astraxSrpGlassMode then astraxSrpGlassMode(" + (root.liquidGlass ? "true" : "false") + ") end"];
            srpGlassProcess.running = true;
        }
    }
    Process { id: srpGlassProcess }

    property color base: "#1e1e2e"
    property color mantle: "#181825"
    property color crust: "#11111b"
    property color text: "#cdd6f4"
    property color subtext0: "#a6adc8"
    property color subtext1: "#bac2de"
    property color surface0: "#313244"
    property color surface1: "#45475a"
    property color surface2: "#585b70"
    property color overlay0: "#6c7086"
    property color overlay1: "#7f849c"
    property color overlay2: "#9399b2"
    property color blue: "#89b4fa"
    property color sapphire: "#74c7ec"
    property color peach: "#fab387"
    property color green: "#a6e3a1"
    property color red: "#f38ba8"
    property color mauve: "#cba6f7"
    property color pink: "#f5c2e7"
    property color yellow: "#f9e2af"
    property color maroon: "#eba0ac"
    property color teal: "#94e2d5"

    // Crossfade between themes (song change / entering and leaving a mode).
    property int fadeMs: 700
    Behavior on base { ColorAnimation { duration: root.fadeMs } }
    Behavior on mantle { ColorAnimation { duration: root.fadeMs } }
    Behavior on crust { ColorAnimation { duration: root.fadeMs } }
    Behavior on text { ColorAnimation { duration: root.fadeMs } }
    Behavior on subtext0 { ColorAnimation { duration: root.fadeMs } }
    Behavior on subtext1 { ColorAnimation { duration: root.fadeMs } }
    Behavior on surface0 { ColorAnimation { duration: root.fadeMs } }
    Behavior on surface1 { ColorAnimation { duration: root.fadeMs } }
    Behavior on surface2 { ColorAnimation { duration: root.fadeMs } }
    Behavior on overlay0 { ColorAnimation { duration: root.fadeMs } }
    Behavior on overlay1 { ColorAnimation { duration: root.fadeMs } }
    Behavior on overlay2 { ColorAnimation { duration: root.fadeMs } }
    Behavior on blue { ColorAnimation { duration: root.fadeMs } }
    Behavior on sapphire { ColorAnimation { duration: root.fadeMs } }
    Behavior on peach { ColorAnimation { duration: root.fadeMs } }
    Behavior on green { ColorAnimation { duration: root.fadeMs } }
    Behavior on red { ColorAnimation { duration: root.fadeMs } }
    Behavior on mauve { ColorAnimation { duration: root.fadeMs } }
    Behavior on pink { ColorAnimation { duration: root.fadeMs } }
    Behavior on yellow { ColorAnimation { duration: root.fadeMs } }
    Behavior on maroon { ColorAnimation { duration: root.fadeMs } }
    Behavior on teal { ColorAnimation { duration: root.fadeMs } }

    property string configPath: Quickshell.env("QS_COLORS_JSON") ?? "~/.local/state/serpantinum/qs_colors.json"
    property string matugenConfigPath: (typeof Caching !== "undefined" && Caching.stateDir ? Caching.stateDir : ((Quickshell.env("HOME") ?? "") + "/.local/state/serpantinum")) + "/qs_matugen_colors.json"

    property bool _readInProgress: false
    property var matugenColors: null
    property var _colorQueue: []
    property int colorsPerFrame: 3

    // Reacting to the song color (mauve/pink). This used to
    // turn on by itself with a VIDEO wallpaper set
    // (Wallpaper.anyVideoActive) -- now it's an explicit mode with 2
    // binds (CTRL+SUPER+C = music, ALT+SUPER+C = wallpaper).
    // "off" = the usual behaviour (matugen from the
    // wallpaper, or a static preset per settings.json).
    property string colorMode: "off"
    property color songPrimary: "#cba6f7"
    property color songTertiary: "#f5c2e7"

    FileView {
        id: colorModeFile
        path: `${Quickshell.env("HOME")}/.local/state/serpantinum/widget_color_mode`
        printErrors: false
    }
    function persistColorMode() {
        colorModeFile.setText(root.colorMode);
    }

    function setColorMode(mode) {
        root.colorMode = mode;
        root.persistColorMode();
        if (mode === "music") {
            // With music playing it takes songPrimary/songTertiary (the
            // last ones border_colors.py sent); WITHOUT music
            // playing those properties keep the purple default from
            // above until something plays again -- it doesn't
            // turn on but doesn't turn off either, it just shows
            // purple.
            root.applySongOverrideIfActive();
        } else if (mode === "wallpaper") {
            // Forces the REAL color of the current wallpaper (animated or
            // static), even if a static preset is picked in
            // Serpantinum.
            root.applyMatugenColors();
        } else {
            root.updateColors();
        }
    }

    IpcHandler {
        target: "widgetColorMode"

        function toggleMusic(): string {
            root.setColorMode(root.colorMode === "music" ? "off" : "music");
            return root.colorMode;
        }
        function toggleWallpaper(): string {
            root.setColorMode(root.colorMode === "wallpaper" ? "off" : "wallpaper");
            return root.colorMode;
        }
    }

    function hexToQtColor(hex) {
        // /tmp/widget-colors.json stores the hex WITHOUT "#" (e.g. "cec98c") --
        // Qt.color() requires it, that's why the override never kicked in.
        if (!hex || typeof hex !== "string") return undefined;
        let h = hex.startsWith("#") ? hex : "#" + hex;
        try { return Qt.color(h); } catch (e) { return undefined; }
    }

    // Special TV Girl mode: border_colors.py writes "1"/"0" (atomically) to
    // this file when a TV Girl song starts / stops playing.
    // It takes priority over matugen, presets and music mode: black
    // backgrounds + blue and violet. When it turns off, updateColors() restores the
    // normal theme. applySongOverrideIfActive() runs at the end of EVERY
    // applyColorObject(), so the override isn't overwritten.
    property bool tvGirl: false
    property var tvGirlPalette: ({
        base: "#000000", mantle: "#050309", crust: "#000000",
        surface0: "#0d0916", surface1: "#171128", surface2: "#241b3d",
        overlay0: "#5d4f90", overlay1: "#7b6cb4", overlay2: "#9b8fd4",
        text: "#ede7ff", subtext0: "#b9aee3", subtext1: "#8f85c0",
        blue: "#3d8bff", sapphire: "#1f6bff", teal: "#4db8ff",
        green: "#5aa9ff", mauve: "#ff3fd0", pink: "#3d8bff",
        peach: "#ff7ae0", yellow: "#8fb4ff", maroon: "#b0189a",
        red: "#ff4f9a"
    })

    // Source of truth: Serpantinum's "TV Girl" preset (assets/themes).
    // The palette above is only the fallback if the file doesn't load.
    FileView {
        id: tvGirlTheme
        path: ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                const c = j.colors;
                if (c && root.tvModeName !== "") {
                    root.beginThemeFade();
                    root.tvGirlPalette = c;
                    root.tvSpectrumBands = j.spectrum_bands === true;
                    root.tvSpectrumWipe = j.spectrum_wipe === true;
                    root.tvSpectrum = Array.isArray(j.spectrum) ? j.spectrum.map(x => x.startsWith("#") ? x : "#" + x) : [];
                    root.tvLyricCycle = Array.isArray(j.lyric_cycle) ? j.lyric_cycle.map(x => x.startsWith("#") ? x : "#" + x) : [];
                    root.tvCycle = Array.isArray(j.cycle) ? j.cycle.map(x => x.startsWith("#") ? x : "#" + x) : [];
                    root.tvGirl = true;
                    root.syncLyricsSub();
                    if (root.tvCycle.length > 0 && root.tvLyricIndex >= 0) root.tvPhase = root.tvLyricIndex;
                    root.applyTvGirl();
                    root.applyCycleExternal();
                }
            } catch (e) {}
        }
    }

    // Modes with "cycle" (Streetcat): the main accent goes through the cycle
    // colors in order, one per lyric line change (like in
    // the music video). The color depends on the line index, so it also
    // works if the song is skipped forwards or backwards.
    // Colors rotated ONLY by the active line of the lyrics widget (one color
    // per line, in order). Different from tvCycle (whole-theme rotation).
    // Left-to-right colors for the visualizer (cava) in special
    // modes; t in 0..1. Outside a special mode = flat mauve (as usual).
    property var tvSpectrum: []
    // Crossfade of the cava/lyrics colors: on theme change it
    // interpolates from what was shown (tvSpectrumPrev) to the new one (tvMix 0->1).
    property var tvSpectrumPrev: []
    property var tvLyricCyclePrev: []
    property real tvMix: 1
    NumberAnimation on tvMix { id: tvMixAnim; running: false; from: 0; to: 1; duration: root.fadeMs; easing.type: Easing.InOutQuad }
    function _mixStop(prev, cur, i) {
        const b = Qt.color(cur[i]);
        if (root.tvMix >= 1 || !prev || prev.length === 0) return b;
        const a = Qt.color(prev[Math.min(i, prev.length - 1)]);
        const f = root.tvMix;
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1.0);
    }
    // Current stops (already blended) for whoever draws with canvas.
    function spectrumStops() {
        const out = [];
        for (let i = 0; i < root.tvSpectrum.length; i++) out.push(root._mixStop(root.tvSpectrumPrev, root.tvSpectrum, i));
        return out;
    }
    function beginThemeFade() {
        root.tvSpectrumPrev = root.tvSpectrum.map((c, i) => root._mixStop(root.tvSpectrumPrev, root.tvSpectrum, i).toString());
        root.tvLyricCyclePrev = root.tvLyricCycle.map((c, i) => root._mixStop(root.tvLyricCyclePrev, root.tvLyricCycle, i).toString());
        root.tvMix = 0;
        tvMixAnim.restart();
    }
    property bool tvSpectrumBands: false   // true = SOLID color bands (no blending)
    // "wipe" mode: a single solid color at a time; the next color
    // covers it from left to right, in order, looping. tvWave goes from 0 to
    // N (N = number of colors); integer part = current color, fractional
    // part = position of the sweep front (0 = left, 1 = right).
    property bool tvSpectrumWipe: false
    property real tvWave: 0
    NumberAnimation on tvWave {
        from: 0
        to: Math.max(1, root.tvSpectrum.length)
        duration: Math.max(1, root.tvSpectrum.length) * 2500
        loops: Animation.Infinite
        running: root.tvGirl && root.tvSpectrumWipe && root.tvSpectrum.length > 1
    }
    function spectrumColor(t) {
        const sp = root.tvSpectrum;
        if (!root.tvGirl || !sp || sp.length < 2) return root.mauve;
        if (root.tvSpectrumWipe) {
            const n = sp.length, base = Math.floor(root.tvWave), f = root.tvWave - base;
            return Qt.color(t < f ? sp[(base + 1) % n] : sp[base % n]);
        }
        if (root.tvSpectrumBands)
            return root._mixStop(root.tvSpectrumPrev, sp, Math.min(sp.length - 1, Math.floor(Math.max(0, Math.min(1, t)) * sp.length)));
        const x = Math.max(0, Math.min(1, t)) * (sp.length - 1);
        const i = Math.min(sp.length - 2, Math.floor(x));
        const f = x - i;
        const a = root._mixStop(root.tvSpectrumPrev, sp, i), b = root._mixStop(root.tvSpectrumPrev, sp, i + 1);
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1.0);
    }
    property var tvLyricCycle: []
    // Active lyric line color: in modes with lyric_cycle it rotates one color
    // per line (idx = Lyrics.currentIndex); otherwise the usual fallback.
    function lyricLineColor(idx, fallback) {
        const c = root.tvLyricCycle;
        if (!root.tvGirl || !c || c.length === 0) return fallback;
        return root._mixStop(root.tvLyricCyclePrev, c, Math.max(idx, 0) % c.length);
    }
    property var tvCycle: []
    property int tvPhase: 0
    property bool _lyricsSubscribed: false
    readonly property int tvLyricIndex: (typeof Lyrics !== "undefined") ? Lyrics.currentIndex : -1

    onTvLyricIndexChanged: {
        if (root.tvGirl && root.tvCycle.length > 0 && root.tvLyricIndex >= 0) {
            root.tvPhase = root.tvLyricIndex;
            root.applyTvGirl();
            root.applyCycleExternal();
        }
    }

    // Widgets (widgets2-4) and the window border follow the same cycle: a script
    // rewrites /tmp/widget-colors.json (atomically) and the Hyprland border.
    function applyCycleExternal() {
        const cyc = root.tvCycle;
        if (cyc.length < 4) return;
        const n = cyc.length, ph = Math.max(root.tvPhase, 0);
        const hex = i => cyc[(ph + i) % n].replace("#", "");
        Quickshell.execDetached([(Quickshell.env("HOME") ?? "") + "/scripts/mode-cycle-apply.sh", hex(0), hex(1)]);
    }

    function syncLyricsSub() {
        if (typeof Lyrics === "undefined") return;
        const want = root.tvGirl && root.tvCycle.length > 0;
        if (want && !root._lyricsSubscribed) { Lyrics.subscribe(); root._lyricsSubscribed = true; }
        else if (!want && root._lyricsSubscribed) { Lyrics.unsubscribe(); root._lyricsSubscribed = false; }
    }

    function applyTvGirl() {
        const p = root.tvGirlPalette;
        for (const k in p) root[k] = Qt.color(p[k]);
        const cyc = root.tvCycle;
        if (cyc.length >= 4) {
            const n = cyc.length, ph = Math.max(root.tvPhase, 0);
            const c = i => Qt.color(cyc[(ph + i) % n]);
            root.mauve = c(0); root.pink = c(1); root.blue = c(2); root.green = c(3);
            root.peach = Qt.lighter(c(0), 1.2); root.yellow = Qt.lighter(c(0), 1.4);
            root.sapphire = Qt.lighter(c(2), 1.15); root.teal = Qt.lighter(c(3), 1.2);
            root.red = c(1); root.maroon = Qt.darker(c(1), 2);
        }
    }

    // Name of the active mode ("" = none), read from the tvgirl_mode flag.
    property string tvModeName: ""

    function setTvMode(raw) {
        let n = raw === "1" ? "TV Girl" : (raw === "0" ? "" : raw);
        if (n === root.tvModeName) return;
        root.tvModeName = n;
        if (n === "") {
            tvGirlTheme.path = "";
            root.tvCycle = [];
            root.tvLyricCycle = [];
            root.tvSpectrum = [];
            root.tvSpectrumBands = false;
            root.tvSpectrumWipe = false;
            if (root.tvGirl) { root.tvGirl = false; root.syncLyricsSub(); root.updateColors(); }
        } else {
            tvGirlTheme.path = `${Quickshell.env("HOME")}/.local/state/serpantinum/themes/${n}.json`;
        }
    }

    FileView {
        id: tvGirlFile
        path: `${Quickshell.env("HOME")}/.local/state/serpantinum/tvgirl_mode`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.setTvMode(text().trim())
        onLoadFailed: root.setTvMode("")
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: tvGirlFile.reload()
    }

    function applySongOverrideIfActive() {
        if (root.tvGirl) { root.applyTvGirl(); return; }
        if (root.colorMode !== "music") return;
        root.mauve = root.songPrimary;
        root.pink = root.songTertiary;
    }

    FileView {
        id: songColorsWatcher
        path: "/tmp/widget-colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                const p = root.hexToQtColor(c.primary);
                const t = root.hexToQtColor(c.tertiary);
                if (p) root.songPrimary = p;
                if (t) root.songTertiary = t;
                root.applySongOverrideIfActive();
            } catch (e) {}
        }
    }

    // Check every 2s as a safety net, on top of the reactive FileView
    // above (in case inotify misses a change -- same pattern
    // used in border_colors.py for the wallpaper).
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: songColorsWatcher.reload()
    }

    property var availableFontPaths: ({})
    property var bundledNames: []
    property string activeFontPath: ""

    FontLoader {
        id: iconFontLoader
        source: (typeof Caching !== "undefined" && Caching.serpantinumDir && Caching.serpantinumDir !== "")
            ? ("file://" + Caching.serpantinumDir + "/assets/fonts/SymbolsNerdFontMono-Regular.ttf")
            : ""
    }

    readonly property string iconFont: (iconFontLoader.status === FontLoader.Ready && iconFontLoader.name !== "")
        ? iconFontLoader.name
        : (root.fontFamily !== "" ? root.fontFamily : "sans-serif")
    readonly property bool iconFontReady: iconFontLoader.status === FontLoader.Ready

    onFontFamilyChanged: {
        root.updateActiveFontLoader();
    }

    function isMatugenTheme() {
        if (typeof Matugen !== "undefined" && typeof Matugen.isMatugenTheme === "function") {
            return Matugen.isMatugenTheme();
        }
        let themeConfig = Config.getSetting("theme", { "matugen": true, "activePreset": "Matugen" });
        if (themeConfig.matugen !== undefined) {
            return themeConfig.matugen === true;
        }
        return themeConfig.theme === "matugen"
            || themeConfig.name === "matugen"
            || themeConfig.currentTheme === "matugen"
            || themeConfig.current === "matugen"
            || themeConfig.activePreset === "Matugen"
            || themeConfig.activePreset === undefined;
    }

    function updateActiveFontLoader() {
        if (!root.fontFamily || root.fontFamily === "") return;
        let key = root.fontFamily.toLowerCase();
        let path = root.availableFontPaths ? root.availableFontPaths[key] : "";

        if (path && root.activeFontPath !== path) {
            root.activeFontPath = path;
        }
    }

    FontLoader {
        id: staticFontLoader
        source: (root.activeFontPath && root.activeFontPath !== "") ? ("file://" + root.activeFontPath) : ""
        onStatusChanged: {
            if (status === FontLoader.Ready) {
                let cur = root.fontFamily;
                root.fontFamily = "";
                root.fontFamily = cur;
            }
        }
    }

    Process {
        id: fontFetcher
        property bool forceRescan: false

        command: {
            let sys = Caching.serpantinumDir ? (Caching.serpantinumDir + "/assets/fonts") : "";
            let usr = Caching.stateDir ? (Caching.stateDir + "/fonts") : (Caching.home + "/.local/state/serpantinum/fonts");
            let cacheFile = Caching.stateDir ? (Caching.stateDir + "/fonts_cache.txt") : (Caching.home + "/.local/state/serpantinum/fonts_cache.txt");
            let force = forceRescan ? "true" : "false";

            let cmd = "CACHE=\"" + cacheFile + "\"; ";
            cmd += "if [ \"" + force + "\" = \"true\" ] || [ ! -f \"$CACHE\" ]; then ";
            cmd += "mkdir -p \"$(dirname \"$CACHE\")\"; ";
            cmd += "find ";
            if (sys !== "") cmd += "\"" + sys + "\" ";
            cmd += "\"" + usr + "\" -type f \\( -iname \"*.ttf\" -o -iname \"*.otf\" -o -iname \"*.ttc\" \\) -print0 2>/dev/null | sort -z | ";
            cmd += "xargs -0 -r fc-scan -f '%{family[0]}\\t%{style[0]}\\t%{file}\\n' 2>/dev/null | ";
            cmd += "awk -F'\\t' '{ fam=$1; stl=$2; f=$3; if (fam==\"\") { n=split(f,a,\"/\"); fam=a[n]; sub(/\\.[^.]*$/,\"\",fam) } if (stl!=\"\" && stl!=\"Regular\") print fam \" \" stl \"|\" f; else print fam \"|\" f }' ";
            cmd += "> \"$CACHE.tmp\" || true; mv \"$CACHE.tmp\" \"$CACHE\"; ";
            cmd += "fi; ";
            cmd += "cat \"$CACHE\" || true";

            return ["bash", "-c", cmd];
        }
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                fontFetcher.forceRescan = false;

                let lines = this.text.trim().split('\n');
                let newPaths = {};
                let names = [];
                let seen = new Set();

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line === "") continue;

                    let idx = line.indexOf('|');
                    if (idx !== -1) {
                        let fName = line.substring(0, idx).trim();
                        if (fName.toLowerCase().indexOf("symbols nerd font") !== -1) continue;

                        let fPath = line.substring(idx + 1).trim();
                        let key = fName.toLowerCase();

                        newPaths[key] = fPath;

                        if (!seen.has(key)) {
                            seen.add(key);
                            names.push(fName);
                        }
                    }
                }

                root.availableFontPaths = newPaths;
                root.bundledNames = names;
                root.updateActiveFontLoader();
                if (staticFontLoader.status === FontLoader.Ready) {
                    let cur = root.fontFamily;
                    root.fontFamily = "";
                    root.fontFamily = cur;
                }
            }
        }
    }

    function scanFonts() {
        fontFetcher.running = false;
        fontFetcher.forceRescan = true;
        fontFetcher.running = true;
    }

    function reloadColors() {
        if (root._readInProgress) return;
        root._readInProgress = true;
        root.updateColors();
    }

    IpcHandler {
        target: "theme"

        function reloadColors() {
            root.reloadColors();
        }
    }

    IpcHandler {
        target: "fonts"
        function rescan() {
            root.scanFonts();
        }
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            root.updateColors();
        }
        function onRawSettingsChanged() {
            root.syncElementOpacity();
        }
    }

    Connections {
        target: typeof Matugen !== "undefined" ? Matugen : null
        function onGenerationFinished(success) {
            root._readInProgress = false;
            if (success) {
                themeWatcher.reload();
                matugenColorsWatcher.reload();
            }
        }
    }

    function applyMatugenColors(): bool {
        if (root.matugenColors) {
            root.applyColorObject(root.matugenColors);
            return true;
        }
        return false;
    }

    function faded(c) {
        return Qt.alpha(c, root.elementOpacity);
    }

    function syncElementOpacity() {
        const themeConfig = Config.getSetting("theme", {});
        const pct = themeConfig.elementOpacity !== undefined ? Number(themeConfig.elementOpacity) : 100;
        root.blurBackground = themeConfig.blurBackground !== undefined ? Boolean(themeConfig.blurBackground) : false;
        root.blurStyle = themeConfig.blurStyle === "liquid" ? "liquid" : "blur";
        root.elementOpacity = root.liquidGlass ? root.liquidGlassOpacity : (isNaN(pct) ? 1.0 : Math.max(0.2, Math.min(1.0, pct / 100.0)));
    }

    function updateColors() {
        let themeConfig = Config.getSetting("theme", {});

        if (themeConfig.fontFamily !== undefined) {
            root.fontFamily = themeConfig.fontFamily;
        }
        if (themeConfig.borderRadius !== undefined) {
            root.borderRadius = themeConfig.borderRadius;
        }
        root.syncElementOpacity();

        let customColors = themeConfig.colors || themeConfig.palette || (themeConfig.base !== undefined ? themeConfig : null);

        if (root.isMatugenTheme()) {
            root.applyMatugenColors();
            let wp = themeConfig.wallpaper || Config.getSetting("wallpaper", "");
            if (typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                Matugen.generate(wp, themeConfig.mode, themeConfig.schemeType);
            }
            root._readInProgress = false;
        } else {
            root._readInProgress = false;
            if (customColors) {
                root.applyColorObject(customColors);
                if (typeof Matugen !== "undefined" && typeof Matugen.generateFromStatic === "function") {
                    Matugen.generateFromStatic(customColors, themeConfig.mode);
                }
            } else {
                themeWatcher.reload();
            }
        }
    }

    function applyColorObject(c) {
        if (!c) return;

        let resolveHex = function(val) {
            if (!val) return "";
            if (typeof val === "string") return val;
            if (typeof val === "object") {
                if (val.hex) return val.hex;
                if (val.color) return val.color;
                if (val.default && val.default.hex) return val.default.hex;
            }
            return val.toString();
        };

        let names = ["base", "mantle", "crust", "surface0", "surface1", "surface2",
                     "overlay0", "overlay1", "overlay2", "text", "subtext0", "subtext1",
                     "blue", "sapphire", "peach", "green", "red", "mauve", "pink",
                     "yellow", "maroon", "teal"];

        let queue = [];
        for (let i = 0; i < names.length; i++) {
            let hexColor = resolveHex(c[names[i]]);
            if (!hexColor) continue;
            let nextColor = Qt.color(hexColor);
            if (root[names[i]].toString() !== nextColor.toString()) {
                queue.push({ name: names[i], value: nextColor });
            }
        }

        root._colorQueue = queue;
        if (queue.length > 0) {
            root._flushColorQueue();
            if (root._colorQueue.length > 0) colorStepTimer.restart();
        }
    }

    function _flushColorQueue() {
        let n = Math.min(root.colorsPerFrame, root._colorQueue.length);
        for (let i = 0; i < n; i++) {
            let item = root._colorQueue[i];
            root[item.name] = item.value;
        }
        root._colorQueue = root._colorQueue.slice(n);
        // custom: the song/mode override runs AFTER the color queue is drained
        if (root._colorQueue.length === 0) root.applySongOverrideIfActive();
    }

    Timer {
        id: colorStepTimer
        interval: 16
        repeat: true
        onTriggered: {
            root._flushColorQueue();
            if (root._colorQueue.length === 0) stop();
        }
    }

    FileView {
        id: matugenColorsWatcher
        path: root.matugenConfigPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let c = JSON.parse(txt);
                    let target = c && c.colors ? c.colors : c;
                    if (target) {
                        root.matugenColors = target;
                        if (root.isMatugenTheme()) {
                            root.applyColorObject(target);
                        }
                    }
                } catch(e) {}
            }
        }
    }

    FileView {
        id: themeWatcher
        path: root.configPath.startsWith("~") ? (Quickshell.env("HOME") ?? "") + root.configPath.slice(1) : root.configPath
        watchChanges: false

        onLoaded: {
            root._readInProgress = false;
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let c = JSON.parse(txt);
                    let target = c && c.colors ? c.colors : c;
                    if (target) {
                        if (root.isMatugenTheme()) {
                            root.matugenColors = target;
                        }
                        root.applyColorObject(target);
                    }
                } catch(e) {}
            }
        }
    }

    Component.onCompleted: {
        root._readInProgress = true;
        root.updateColors();
        root.updateActiveFontLoader();
        srpGlassSync.restart();
    }
}
