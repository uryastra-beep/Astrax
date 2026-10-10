-- Hyprland plugins (managed with hyprpm)
--
-- hypr-dynamic-cursors -- physics-based mouse cursor animation.
--   https://github.com/virtcode/hypr-dynamic-cursors
--   Installed with:
--     hyprpm add https://github.com/virtcode/hypr-dynamic-cursors
--     hyprpm enable dynamic-cursors
--
-- NOTE: "hyprctl reload" unloads all plugins, so the .so has to be
-- loaded from the config (hl.plugin.load) and BEFORE the hl.config that
-- configures it -- otherwise the plugin:dynamic-cursors:* keys don't exist yet
-- at parse time and the red "unknown config key" banner shows up.

local DYNAMIC_CURSORS_SO = "/var/cache/hyprpm/" .. (os.getenv("USER") or "")
    .. "/dynamic-cursors/dynamic-cursors.so"

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
                --   "tilt"    tilts the cursor with horizontal speed (subtle)
                --   "stretch" stretches/deforms the cursor with speed
                --   "none"    no movement animation (keeps only shake to find)
                -- NOTE: the plugin does NOT validate this value; a typo is silently
                -- accepted and leaves the cursor without animation (that's why
                -- the "mouse" command validates before writing).
                -- The @mouse-mode marker is what anchors the "mouse" sed:
                -- DON'T remove it, and don't put it in the shape_rules below.
                mode = "rotate", -- @mouse-mode

                -- shake to find: shaking the mouse enlarges the cursor.
                -- OFF. The @mouse-shake marker is what
                -- "mouse trail on" reads so it doesn't re-enable it when hot-loading.
                shake = {
                    enabled = false, -- @mouse-shake
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
                -- enlarged a lot. Bibata-Modern-Ice is SVG, so it scales cleanly.
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
        mode = "stretch",
    })

    -- hand for links and clickable elements
    hl.plugin.dynamic_cursors.shape_rule({
        shape = "pointer",
        mode = "tilt",
    })
end
