-- Compositor backdrop blur for the Liquid Glass of the Dynamic Island, the macOS Dock and
-- (optionally) Serpantinum's own liquid glass.
--
-- * Liquid Glass is turned off while `opti` is on: the QML side ignores its glass setting and this
--   file leaves blur passes/size to opti. Turning opti off brings the glass back by itself.
-- * With sharp-transparent mode on, every window and layer except the island loses its blur but
--   the blur engine stays on, so the island can still blur what is behind it.
local HOME = os.getenv("HOME") or ""

local function firstLine(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local l = f:read("*l")
    f:close()
    return l
end

local function optiOn() return firstLine(HOME .. "/.local/state/opti") == "on" end

-- The blur values decorations.lua asks for, to go back to them when no glass mode needs a change.
local function defaultBlur()
    local f = io.open(HOME .. "/.config/hypr/config/decorations.lua", "r")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    local block = text:match("blur%s*=%s*(%b{})") or ""
    return tonumber(block:match("size%s*=%s*(%d+)")) or 5, tonumber(block:match("passes%s*=%s*(%d+)")) or 4
end

local windows = hl.window_rule({
    name = "astrax-sharp-windows-no-blur",
    match = { class = ".*" },
    no_blur = true,
})
local layers = hl.layer_rule({
    name = "astrax-sharp-other-layers-no-blur",
    match = { namespace = ".*" },
    blur = false,
    blur_popups = false,
})
local island = hl.layer_rule({
    name = "astrax-island-backdrop-blur",
    match = { namespace = "^astrax-island$" },
    blur = true,
    ignore_alpha = 0.05,
    xray = false, -- blur the actual windows behind the pill, not just the wallpaper
})

-- Serpantinum's glass interiors sample real windows through the compositor blur.
local srp = hl.layer_rule({
    name = "srp-liquid-backdrop-blur",
    match = { namespace = "^(qs-master|qs-popups|qs-lyrics-picker|qs-widget-.*|qs-widget-redactor-.*|qs-dock|qs-applauncher|qs-clipboard|qs-floating-overlay|traymenu|sidemusic|osd|dockappmenu|desktopmenu|welcome-guide|assistant-bg|qs-screenshot-overlay)$" },
    blur = true,
    ignore_alpha = 0.05,
    xray = false,
})

local srpGlassEnabled = false
local sharpMode = false

local function sync()
    if optiOn() then
        -- no Liquid Glass under opti: only keep sharp mode's "no blur at all"
        windows:set_enabled(false)
        layers:set_enabled(false)
        island:set_enabled(false)
        srp:set_enabled(false)
        hl.config({ decoration = { blur = { enabled = not sharpMode } } })
        return
    end
    windows:set_enabled(sharpMode)
    layers:set_enabled(sharpMode)
    island:set_enabled(true)
    srp:set_enabled(srpGlassEnabled)
    if srpGlassEnabled or sharpMode then
        hl.config({ decoration = { blur = { enabled = true, size = srpGlassEnabled and 3 or 1, passes = 2 } } })
    else
        local size, passes = defaultBlur()
        hl.config({ decoration = { blur = { enabled = true, size = size, passes = passes } } })
    end
end

function _G.astraxSrpGlassMode(enabled)
    srpGlassEnabled = enabled == true
    sync()
end

function _G.astraxIslandBlurMode(sharp)
    sharpMode = sharp == true
    sync()
end

-- called by opti-ctl.sh after it switches opti on or off
function _G.astraxIslandBlurRefresh() sync() end

function _G.astraxIslandBlurRestore(previousEnabled)
    windows:set_enabled(false)
    layers:set_enabled(false)
    island:set_enabled(false)
    srp:set_enabled(false)
    local size, passes = defaultBlur()
    hl.config({ decoration = { blur = { enabled = previousEnabled, size = size, passes = passes } } })
    _G.astraxSrpGlassMode = nil
    _G.astraxIslandBlurMode = nil
    _G.astraxIslandBlurRefresh = nil
    _G.astraxIslandBlurRestore = nil
end

-- Read the persisted state when the config is (re)loaded, even if QML stays alive.
local settings = io.open(HOME .. "/.config/serpantinum/settings.json", "r")
local theme = settings and settings:read("*a") or ""
if settings then settings:close() end
srpGlassEnabled = theme:match('"blurBackground"%s*:%s*true') ~= nil
    and theme:match('"blurStyle"%s*:%s*"liquid"') ~= nil
sharpMode = firstLine(HOME .. "/.local/state/sharp-transparent") == "on"
sync()
