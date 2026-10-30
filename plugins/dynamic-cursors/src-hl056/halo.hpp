#pragma once
// HALO PATCH: color of the glow depends on the cursor shape
#include <string>
#include <fstream>
#include <chrono>
#include <cstdlib>

inline std::string g_curShape = "default";

// CURSOR STYLE (chosen from the Serpantinum guide, SUPER+C > General; stored in ~/.config/cursor-style):
//   0 = normal (classic cursor: no glow, no animations, apps may set their own cursor)
//   1 = astrax (default palette)   2 = high contrast (Okabe-Ito based palette)
inline int g_cursorStyle = 1;

// Which animations of the "astrax"/"highcontrast" cursor are on (~/.config/cursor-anims, lines "name=0|1"; missing = on)
struct SAnims {
    bool trail = true, click = true, scroll = true, colorfade = true, roulette = true, speed = true, rotate = true;
};
inline SAnims g_anims;

inline void refreshCursorStyle() {
    using namespace std::chrono;
    static steady_clock::time_point last{};
    auto                            now = steady_clock::now();
    if (duration_cast<milliseconds>(now - last).count() < 300)
        return;
    last = now;
    const char* home = std::getenv("HOME");
    std::ifstream f(std::string(home ? home : "") + "/.config/cursor-style");
    std::string   v;
    f >> v;
    g_cursorStyle = (v == "normal") ? 0 : (v == "highcontrast") ? 2 : 1;  // anything else (e.g. "astrax") = 1

    SAnims        a;
    std::ifstream fa(std::string(home ? home : "") + "/.config/cursor-anims");
    std::string   line;
    while (std::getline(fa, line)) {
        auto eq = line.find('=');
        if (eq == std::string::npos)
            continue;
        std::string k = line.substr(0, eq);
        bool        on = line.substr(eq + 1).find('0') == std::string::npos;
        if (k == "trail") a.trail = on;
        else if (k == "click") a.click = on;
        else if (k == "scroll") a.scroll = on;
        else if (k == "colorfade") a.colorfade = on;
        else if (k == "roulette") a.roulette = on;
        else if (k == "speed") a.speed = on;
        else if (k == "rotate") a.rotate = on;
    }
    g_anims = a;
}

struct SPalette {
    int click, text, drag, cross, resize, copy, error, def, aliasA, aliasB;
    int roulette[6];
};

inline const SPalette& palette() {
    static const SPalette URY = {0x2f6bff, 0xffffff, 0x5cd6ff, 0xff8a1f, 0xff4fb8, 0x2ee86b, 0xff2d3d, 0x7a2cf0, 0x2f6bff, 0xffffff,
                                 {0x2f6bff, 0xffffff, 0x5cd6ff, 0xff8a1f, 0xff4fb8, 0x7a2cf0}};
    // High contrast palette (Okabe-Ito based): sky blue, yellow, orange, reddish purple, bluish green, vermillion
    static const SPalette CB = {0x56b4e9, 0xffffff, 0xf0e442, 0xe69f00, 0xcc79a7, 0x009e73, 0xd55e00, 0x9b8cff, 0x56b4e9, 0xffffff,
                                {0x56b4e9, 0xffffff, 0xf0e442, 0xe69f00, 0xcc79a7, 0x009e73}};
    return g_cursorStyle == 2 ? CB : URY;
}

// packed 0xRRGGBB; bit 0x2000000 = "roulette" (loading): glow split between all colors, spinning
constexpr int HALO_ROULETTE = 0x2000000;
// bit 0x4000000 = "split": half blue (link) / half white with a fade in the middle (alias)
constexpr int HALO_SPLIT = 0x4000000;

inline int haloColorForShape(const std::string& s) {
    auto has = [&](const char* x) { return s.find(x) != std::string::npos; };
    // error / forbidden: red (checked first so "dnd-no-drop" does not fall into "draggable")
    if (s == "no-drop" || s == "not-allowed" || has("crossed_circle") || has("forbidden") || has("not_allowed") || has("no_drop") || has("dnd-none"))
        return palette().error;
    if (s == "alias" || has("dnd-link") || s == "link")
        return HALO_SPLIT | 0x7a2cf0; // alias: half link-blue, half white
    if (s == "copy" || has("dnd-copy"))
        return palette().copy;
    if (g_anims.roulette && (s == "wait" || s == "progress" || has("watch") || has("busy") || s == "clock"))
        return HALO_ROULETTE | 0x7a2cf0; // loading: roulette
    if (has("resize") || has("double_arrow") || has("_corner") || has("_side") || has("sizing") || has("size_"))
        return palette().resize;
    if (has("crosshair") || s == "cross" || has("tcross") || s == "cell" || s == "plus")
        return palette().cross;
    if (s == "text" || has("vertical-text") || has("xterm") || has("ibeam"))
        return palette().text;
    if (has("grab") || s == "move" || has("fleur") || has("all-scroll") || has("dnd"))
        return palette().drag;
    if (s == "pointer" || has("hand"))
        return palette().click;
    return palette().def;
}
