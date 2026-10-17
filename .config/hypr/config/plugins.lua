-- Hyprland plugins
--
-- hypr-dynamic-cursors -- mouse cursor animation.
--   Stock plugin (fallback): https://github.com/virtcode/hypr-dynamic-cursors
--     hyprpm add https://github.com/virtcode/hypr-dynamic-cursors
--     hyprpm enable dynamic-cursors
--   Astrax's reactive cursor: a patched fork (plugins/dynamic-cursors in the
--   repo), built into ~/.local/share/hypr-plugins/astrax-cursor with
--   "cursor-plugin build". See the README, "Reactive cursor".
--
-- NOTE: "hyprctl reload" unloads all plugins, so the .so has to be
-- loaded from the config (hl.plugin.load) and BEFORE the hl.config that
-- configures it -- otherwise the plugin:dynamic-cursors:* keys don't exist yet
-- at parse time and the red "unknown config key" banner shows up.

-- Set to false to always use the stock hyprpm plugin.
local USE_TRAIL = true

-- Safety net. Rules:
--  1. The patched plugin can ONLY be loaded during the first 30 s of the
--     Hyprland process. A reload/autoreload in a running session never loads
--     it live (hot-loading it can take Hyprland down).
--  2. Hyprland evaluates this file twice at startup (start + internal reload):
--     the session is identified by the process start time, not by a flag.
--  3. If the previous session started with the patched plugin and crashed
--     before deleting the "pending" marker (25 s), "disabled" is created and
--     the stock plugin is used from then on.
--  4. It's only loaded if it was built against the installed Hyprland headers
--     (hash saved by "cursor-plugin build"); after a Hyprland update the stock
--     plugin is used until it's rebuilt.
--  To try the patched plugin again after a crash: rm -r ~/.cache/hypr-trail
local HOME = os.getenv("HOME") or ""
local TRAIL_DIR = HOME .. "/.cache/hypr-trail"
local DYNAMIC_CURSORS_SO = "/var/cache/hyprpm/" .. (os.getenv("USER") or "")
    .. "/dynamic-cursors/dynamic-cursors.so"
local PLUGIN_DIR = HOME .. "/.local/share/hypr-plugins/astrax-cursor"
local TRAIL_SO = PLUGIN_DIR .. "/out/dynamic-cursors.so"

if USE_TRAIL then
    local function read(f) local h = io.open(f, "r"); if not h then return nil end; local t = h:read("a"); h:close(); return t end
    local function write(f, t) local h = io.open(f, "w"); if h then h:write(t); h:close() end end

    -- built against these headers?
    local function built_for_this_hyprland()
        local saved = (read(PLUGIN_DIR .. "/built.hash") or ""):match("%x+")
        if not saved or not read(TRAIL_SO) then return false end
        local ph = io.popen("cursor-plugin hash 2>/dev/null || \"$HOME/scripts/cursor-plugin.sh\" hash 2>/dev/null")
        local now = ph and (ph:read("a") or ""):match("%x+")
        if ph then ph:close() end
        return now ~= nil and now == saved
    end

    local rest = (read("/proc/self/stat") or ""):match("%)%s+(.*)$") or ""
    local fields = {}
    for w in rest:gmatch("%S+") do fields[#fields + 1] = w end
    local start = tonumber(fields[20])
    local up = tonumber((read("/proc/uptime") or ""):match("^(%S+)"))
    local age = (start and up) and (up - start / 100) or 1e9
    local sig = tostring(start or "nosig")
    local cur = read(TRAIL_DIR .. "/current") or ""
    local cur_sig, cur_path = cur:match("^(%S+)\n(.*)$")

    if cur_sig == sig and cur_path and cur_path ~= "" then
        -- same session (2nd evaluation or reload): keep what was already decided
        DYNAMIC_CURSORS_SO = cur_path
    elseif age < 30 and built_for_this_hyprland() then
        -- new session, during its startup
        local pending = read(TRAIL_DIR .. "/pending")
        local disabled = read(TRAIL_DIR .. "/disabled")
        os.execute("mkdir -p '" .. TRAIL_DIR .. "'")
        if disabled then
            -- stays on the stock plugin
        elseif pending then
            -- "pending" not deleted = the previous session lasted under 25 s. It only counts as a
            -- crash if Hyprland left a crash report newer than the marker; a logout or a quick
            -- restart (e.g. updating Serpantinum) does NOT disable the patched plugin.
            local ph = io.popen("find \"$HOME/.cache/hyprland\" -name 'hyprlandCrashReport*' -newer '" .. TRAIL_DIR .. "/pending' 2>/dev/null | head -n 1")
            local crashed = ph and (ph:read("a") or "") ~= ""
            if ph then ph:close() end
            if crashed then
                os.execute("rm -f '" .. TRAIL_DIR .. "/pending'; touch '" .. TRAIL_DIR .. "/disabled'")
            else
                write(TRAIL_DIR .. "/pending", sig)
                hl.exec_cmd("sh -c \"sleep 25; rm -f '" .. TRAIL_DIR .. "/pending'\"")
                DYNAMIC_CURSORS_SO = TRAIL_SO
            end
        else
            write(TRAIL_DIR .. "/pending", sig)
            hl.exec_cmd("sh -c \"sleep 25; rm -f '" .. TRAIL_DIR .. "/pending'\"")
            DYNAMIC_CURSORS_SO = TRAIL_SO
        end
        write(TRAIL_DIR .. "/current", sig .. "\n" .. DYNAMIC_CURSORS_SO)
    end
    -- session already running with no previous decision: stock plugin (never hot-loads the patched one)
end

-- If the .so isn't there (plugin removed, or pending a rebuild after a
-- Hyprland update), nothing is loaded: that way the config never breaks.
local so = io.open(DYNAMIC_CURSORS_SO, "r")
if so then
    so:close()
    hl.plugin.load(DYNAMIC_CURSORS_SO)

    hl.config({
        plugin = {
            dynamic_cursors = {
                enabled = true,

                -- Global mode. Normally changed with the "mouse" command
                -- (~/.config/fish/functions/mouse.fish), which rewrites this
                -- line and reloads -- "mouse help".
                --   "rotate"  rotates the cursor towards where it moves
                --             (the patched plugin also stretches it with speed)
                --   "tilt"    tilts the cursor with horizontal speed (subtle)
                --   "stretch" stretches/deforms the cursor with speed
                --   "none"    no movement animation (keeps only shake to find)
                -- NOTE: the plugin does NOT validate this value; a typo is silently
                -- accepted and leaves the cursor without animation (that's why
                -- the "mouse" command validates before writing).
                -- The @mouse-mode marker is what anchors the "mouse" sed:
                -- DON'T remove it, and don't put it in the shape_rules below.
                mode = "rotate", -- @mouse-mode

                -- shake to find: shaking the mouse enlarges the cursor. OFF.
                shake = {
                    enabled = false, -- @mouse-shake
                },

                -- stretch with speed (default limit = 3000 px/s; higher = subtler).
                -- The trail is only drawn by the glow, not by the arrow.
                stretch = {
                    limit = 4500,
                },

                -- Cursor sharpness when enlarged (shake to find).
                -- nearest = 0 -> never nearest-neighbour. With the default (1),
                -- the HARDWARE cursor path (renderHardware) applies
                -- nearest-neighbour on any zoom > 1 and the cursor looks
                -- blocky. The software path doesn't have that problem, which
                -- is why it only showed sometimes.
                -- resolution = 384 -> resolution used to rasterize the theme's
                -- SVG for the enlarged cursor. The default (-1) computes
                -- 24 * shake.base * 1.5 = 144 px, which gets blurry when
                -- enlarged a lot. Bibata is SVG, so it scales cleanly.
                hyprcursor = {
                    nearest = 0,
                    resolution = 384,
                },
            },
        },
    })

    -- Per cursor shape mode. Overrides the global mode only for that shape.
    -- The names come from the wayland cursor-shape protocol (text, pointer,
    -- crosshair, cell, grab, ...), plus the "clientside" wildcard for
    -- cursors drawn by the app itself.
    -- NOTE: the plugin does NOT validate the shape name -- a non-existent name
    -- gives no error, the rule simply never applies.

    -- text cursor (the "I" for editing/selecting text)
    hl.plugin.dynamic_cursors.shape_rule({
        shape = "text",
        mode = "rotate",
    })

    -- hand for links and clickable elements
    hl.plugin.dynamic_cursors.shape_rule({
        shape = "pointer",
        mode = "rotate",
    })
end
