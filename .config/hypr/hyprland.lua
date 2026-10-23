-- CachyOS Hyprland Configuration

require("config.animations")
require("config.autostart")
require("config.colors")
require("config.decorations")
require("config.variables")
require("config.environment")
require("config.inputs")
-- Active shell: the SDDM session sets HYPR_SHELL, and `vm` can switch shells live,
-- recording the choice per Hyprland instance in $XDG_RUNTIME_DIR/astrax-shell
-- (same file scripts/active-shell.sh reads); `vm` reloads the config afterwards.
local function active_shell()
    local shell = (os.getenv("HYPR_SHELL") == "serpantinum") and "serpantinum" or "caelestia"
    local sig, dir = os.getenv("HYPRLAND_INSTANCE_SIGNATURE"), os.getenv("XDG_RUNTIME_DIR")
    if sig and dir and io and io.open then
        local ok, line = pcall(function()
            local f = io.open(dir .. "/astrax-shell", "r")
            if not f then return nil end
            local l = f:read("*l")
            f:close()
            return l
        end)
        if ok and line then
            local fsig, fshell = line:match("^(%S+)%s+(%S+)$")
            if fsig == sig and (fshell == "serpantinum" or fshell == "caelestia") then shell = fshell end
        end
    end
    return shell
end

if active_shell() == "serpantinum" then
    require("config.binds-serpantinum")
else
    require("config.binds")
end
require("config.binds-island")
require("config.misc")
require("config.monitors")
require("config.windowrules")
require("config.workspaces")
require("config.plugins")

-- CTRL+SUPER+G -> sharp corners + transparency without blur (works in
-- any session, Caelestia or Serpantinum, not part of caelestia's
-- gameMode). See ~/scripts/sharp-transparent-ctl.sh
hl.bind("CONTROL + SUPER + G", hl.dsp.exec_cmd(os.getenv("HOME") .. "/scripts/sharp-transparent-ctl.sh toggle"))

-- CTRL+SUPER+N -> sleep mode: screens go black (DPMS off), freezes apps
-- if there are more than 2 windows (without closing them), audio keeps playing. Wakes up with the
-- same combo or any key. See ~/scripts/sleep-ctl.sh
hl.bind("CONTROL + SUPER + N", hl.dsp.exec_cmd(os.getenv("HOME") .. "/scripts/sleep-ctl.sh toggle"))

-- >>> hyprland-infinite-desktop-v2 (auto-installed) START
-- mainMod detected/used: "SUPER"
    hl.on("hyprland.start", function()
        hl.exec_cmd("python3 ~/scripts/infinite_desktop_core.py 1.6 > /tmp/infinite-desktop.log 2>&1")
    end)

-- Infinite desktop keybinds
hl.bind("SUPER" .. " + Z", hl.dsp.focus({ workspace = "-1" }))
hl.bind("SUPER" .. " + X", hl.dsp.focus({ workspace = "+1" }))
hl.bind("SUPER" .. " + SHIFT + Z", hl.dsp.window.move({ workspace = "-1" }))
hl.bind("SUPER" .. " + SHIFT + X", hl.dsp.window.move({ workspace = "+1" }))
hl.bind("SUPER" .. " + D", hl.dsp.exec_cmd("python3 ~/scripts/floating_tile_toggle.py"))
hl.bind("SUPER" .. " + left", hl.dsp.exec_cmd("python3 ~/scripts/navigate_windows.py left"))
hl.bind("SUPER" .. " + ALT + left", hl.dsp.exec_cmd("python3 ~/scripts/move_window_tiled.py left"))
hl.bind("SUPER" .. " + SHIFT + left", hl.dsp.exec_cmd("python3 ~/scripts/move_window.py left"), { repeating = true })
hl.bind("SUPER" .. " + CTRL + left", hl.dsp.exec_cmd("python3 ~/scripts/resize_window.py left"), { repeating = true })
hl.bind("SUPER" .. " + right", hl.dsp.exec_cmd("python3 ~/scripts/navigate_windows.py right"))
hl.bind("SUPER" .. " + ALT + right", hl.dsp.exec_cmd("python3 ~/scripts/move_window_tiled.py right"))
hl.bind("SUPER" .. " + SHIFT + right", hl.dsp.exec_cmd("python3 ~/scripts/move_window.py right"), { repeating = true })
hl.bind("SUPER" .. " + CTRL + right", hl.dsp.exec_cmd("python3 ~/scripts/resize_window.py right"), { repeating = true })
hl.bind("SUPER" .. " + up", hl.dsp.exec_cmd("python3 ~/scripts/navigate_windows.py up"))
hl.bind("SUPER" .. " + ALT + up", hl.dsp.exec_cmd("python3 ~/scripts/move_window_tiled.py up"))
hl.bind("SUPER" .. " + SHIFT + up", hl.dsp.exec_cmd("python3 ~/scripts/move_window.py up"), { repeating = true })
hl.bind("SUPER" .. " + CTRL + up", hl.dsp.exec_cmd("python3 ~/scripts/resize_window.py up"), { repeating = true })
hl.bind("SUPER" .. " + down", hl.dsp.exec_cmd("python3 ~/scripts/navigate_windows.py down"))
hl.bind("SUPER" .. " + ALT + down", hl.dsp.exec_cmd("python3 ~/scripts/move_window_tiled.py down"))
hl.bind("SUPER" .. " + SHIFT + down", hl.dsp.exec_cmd("python3 ~/scripts/move_window.py down"), { repeating = true })
hl.bind("SUPER" .. " + CTRL + down", hl.dsp.exec_cmd("python3 ~/scripts/resize_window.py down"), { repeating = true })
-- <<< hyprland-infinite-desktop-v2 (auto-installed) END

