local mainMod = "SUPER"
local cael = "caelestia shell "
local launchPrefix = "uwsm app -- " -- if you are not using UWSM, make this empty (e.g. "")

---------------------------
---- WINDOW MANAGEMENT ----
---------------------------

-- Window manipulation
hl.bind(mainMod .. " + Escape",      hl.dsp.exec_cmd("hyprctl kill"))
hl.bind(mainMod .. " + Q",           hl.dsp.window.close())
hl.bind(mainMod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + D",           hl.dsp.window.fullscreen({ mode = 1 }))
hl.bind(mainMod .. " + F",           hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + J",           hl.dsp.layout("togglesplit"))

-- Change focus
hl.bind(mainMod .. " + Left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + Right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + Up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + Down",  hl.dsp.focus({ direction = "down" }))
-- ALT+Tab used to be cycle_next() (classic alt-tab) -- removed without
-- reassigning; it now opens the app-switcher (see the bind further down,
-- next to the "Menu" one).
hl.bind(mainMod .. " + Tab",   hl.dsp.exec_cmd(cael .. "drawers toggle dashboard"))

-- Move active window around workspaces & monitors
hl.bind(mainMod .. " + SHIFT + Up",                   hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + Right",                hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + SHIFT + Left",                 hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + Down",                 hl.dsp.window.move({ direction = "d" }))
-- Moving to another monitor used to drop the window's fullscreen: the state
-- (1 = maximized, 2 = fullscreen) is saved before moving and re-applied if
-- Hyprland dropped it.
-- For apps with their own fullscreen (e.g. Netflix in Brave, HTML5 fullscreen)
-- re-applying FS afterwards isn't enough: when moved, Hyprland tells the
-- client it left FS and the video drops it. So only the INTERNAL state is
-- lowered to 0 while keeping the client's (the app never notices),
-- the window is moved, and it is re-applied.
local function move_to_monitor_keep_fs(target)
    return function()
        local win = hl.get_active_window()
        local fs = win and win.fullscreen or 0
        if fs == 0 then
            hl.dispatch(hl.dsp.window.move({ monitor = target }))
            return
        end
        local fsc = win.fullscreen_client or fs
        hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = fsc }))
        hl.dispatch(hl.dsp.window.move({ monitor = target }))
        hl.dispatch(hl.dsp.window.fullscreen_state({ internal = fs, client = fsc }))
    end
end
hl.bind(mainMod .. " + SHIFT + 1",                    move_to_monitor_keep_fs(MONITOR1))
hl.bind(mainMod .. " + SHIFT + 2",                    move_to_monitor_keep_fs(MONITOR2))
hl.bind(mainMod .. " + SHIFT + 3",                    move_to_monitor_keep_fs(MONITOR3))
hl.bind(mainMod .. " + SHIFT + mouse_up",             move_to_monitor_keep_fs("-1"))
hl.bind(mainMod .. " + SHIFT + mouse_down",           move_to_monitor_keep_fs("+1"))
hl.bind(mainMod .. " + CONTROL + SHIFT + Right",      hl.dsp.window.move({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + Left",       hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_up",   hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_down", hl.dsp.window.move({ workspace = "m+1" }))
-- Same two-bank split as focus: SHIFT+CONTROL = 1-10, SHIFT+ALT = 11-20.
for i = 1, math.min(NUM_WPM, 10) do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + CONTROL + " .. key, hl.dsp.window.move({ workspace = "m~" .. i }))
end
for i = 11, NUM_WPM do
    local key = (i - 10) % 10
    hl.bind(mainMod .. " + SHIFT + ALT + " .. key, hl.dsp.window.move({ workspace = "m~" .. i }))
end

-- Move & Resize with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind("CONTROL + mouse:273", hl.dsp.window.resize())

-- Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
hl.bind(mainMod .. " + Minus", function() zoomfunction(-0.3) end, { repeating = true})
hl.bind(mainMod .. " + Plus", function() zoomfunction(0.3) end, { repeating = true })

--# Zoom with keypad
hl.bind(mainMod .. " + code:82", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind(mainMod .. " + code:86", function() zoomfunction(0.3) end, { repeating = true })


------------------
---- LAUNCHER ----
------------------

-- Open an app by window class, or focus its window if it's already running.
local function focus_or_launch(class, launch_cmd)
    local wins = hl.get_windows({ class = class })
    if wins[1] then
        hl.dispatch(hl.dsp.focus({ window = wins[1] }))
    else
        hl.exec_cmd(launch_cmd)
    end
end

hl.bind(mainMod .. " + CONTROL + O", function() focus_or_launch("Chatgpt", launchPrefix .. "chatgpt") end)

hl.bind(mainMod .. " + Return",     hl.dsp.exec_cmd(launchPrefix .. TERMINAL))
hl.bind(mainMod .. " + E",          hl.dsp.exec_cmd(launchPrefix .. FILE_MANAGER))
hl.bind(mainMod .. " + T",          hl.dsp.exec_cmd(launchPrefix .. EDITOR))
hl.bind(mainMod .. " + C",          hl.dsp.exec_cmd(launchPrefix .. CALCULATOR))
hl.bind("XF86Calculator",           hl.dsp.exec_cmd(launchPrefix .. CALCULATOR))
hl.bind(mainMod .. " + B",          hl.dsp.exec_cmd(launchPrefix .. BROWSER))
hl.bind("CONTROL + SHIFT + Escape", hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " -e btop"))
hl.bind(mainMod .. " + Space",      hl.dsp.exec_cmd(cael .. "drawers toggle launcher"))
-- tap SUPER -> custom launcher (astrax-launcher, icon-only left rail + hover)
hl.bind(mainMod .. " + SUPER_L", hl.dsp.exec_cmd("qs ipc -c astrax-launcher call launcher toggle"), { release = true })
-- physical Menu/Application key -> custom app-switcher, ONLY the screen
-- focused right now (shell-agnostic, same as astrax-launcher). Also
-- ALT+Tab (the physical "Copilot" key didn't work -- we tried
-- XF86Copilot, a keysym that doesn't exist in xkeyboard-config 2.48, and
-- then SUPER+SHIFT+XF86Assistant according to wev, no luck either -- that
-- attempt was dropped). ALT+Tab here replaces the classic cycle_next() it
-- had before.
local toggleAppSwitcher = hl.dsp.exec_cmd("sh -c 'mon=$(hyprctl monitors -j | jq -r \".[] | select(.focused==true) | .name\"); qs ipc -c astrax-app-switcher call \"appswitcher-$mon\" toggle'")
hl.bind("Menu", toggleAppSwitcher)
hl.bind("ALT + Tab", toggleAppSwitcher)
-- CTRL + tap SUPER -> caelestia's original launcher
hl.bind("CONTROL + " .. mainMod .. " + SUPER_L", hl.dsp.exec_cmd("caelestia shell drawers toggle launcher"), { release = true })
hl.bind(mainMod .. " + period",     hl.dsp.exec_cmd("caelestia emoji -p"))
hl.bind(mainMod .. " + L",          hl.dsp.exec_cmd(cael .. "lock lock"))
hl.bind(mainMod .. " + ALT + C",    hl.dsp.exec_cmd(cael .. "drawers toggle session"))

---------------------------
---- HARDWARE CONTROLS ----
---------------------------

-- Audio
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),    { locked = true })

-- Media
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(cael .. "mpris playPause"),   { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(cael .. "mpris playPause"),   { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(cael .. "mpris next"),     { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(cael .. "mpris previous"), { locked = true })

-- Brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(cael .. "brightness set +0.1"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(cael .. "brightness set -0.1"), { locked = true, repeating = true })

-------------------
---- UTILITIES ----
-------------------

-- Screen Capture
hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("hyprpicker -a -n"))
hl.bind("Print",               hl.dsp.exec_cmd("caelestia screenshot -r -f"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("caelestia screenshot"))

-- Theming and Wallpaper
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(cael .. "nexus open"))

-- Clipboard
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("caelestia clipboard"))

-- Notifications
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(cael .. "drawers toggle sidebar"))

-------------------------------
---- WORKSPACES & MONITORS ----
-------------------------------

-- Focus on monitors
hl.bind(mainMod .. " + 1", hl.dsp.focus({ monitor = MONITOR1 }))
hl.bind(mainMod .. " + 2", hl.dsp.focus({ monitor = MONITOR2 }))
hl.bind(mainMod .. " + 3", hl.dsp.focus({ monitor = MONITOR3 }))

-- Focus on workspace number
-- Relative to the focused monitor: 1/2/3 switches workspace ONLY on the screen
-- you're on, it never jumps or drags focus to the other monitor.
-- There are only 10 number keys (1-9,0), so with NUM_WPM > 10 it's split
-- into two banks: ALT = monitor workspaces 1-10, CONTROL = 11-20.
for i = 1, math.min(NUM_WPM, 10) do
    local key = i % 10
    hl.bind(mainMod .. " + ALT + " .. key, hl.dsp.focus({ workspace = "m~" .. i }))
end
for i = 11, NUM_WPM do
    local key = (i - 10) % 10
    hl.bind(mainMod .. " + CONTROL + " .. key, hl.dsp.focus({ workspace = "m~" .. i }))
end

-- Move to adjacent workspaces and next empty on a given monitor
hl.bind(mainMod .. " + CONTROL + Right",       hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + Left",        hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + Down",        hl.dsp.focus({ workspace = "emptym" }))

-- Scroll through existing workspaces & monitors
hl.bind(mainMod .. " + mouse_down",           hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + mouse_up",             hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + mouse_up",   hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + mouse_down", hl.dsp.focus({ workspace = "m+1" }))

-- Special workspace (scratchpad)
-- "hl.dsp.window.move({ workspace = ... })" turned out to be the NON-silent
-- equivalent of "movetoworkspace" -- besides moving the window it FOCUSES/
-- SHOWS the special workspace right away (with its blur), so the window
-- never "disappeared" -- it stayed right there, just inside the special
-- overlay now (same bug found and fixed in widgets4).
--
--
-- Also, Hyprland has no built-in real "toggle" for ONE specific window to
-- enter/leave special (movetoworkspace[silent] always moves it in, it never
-- detects "it's already there, take it out") -- so it's done by hand:
-- if the active window is already on a "special:*" workspace, send it
-- back to the active normal workspace of ITS monitor; otherwise send it to
-- special (silently, without revealing the overlay).
local function toggle_special_workspace()
    local win = hl.get_active_window()
    if not win then return end
    local ws_name = (win.workspace and win.workspace.name) or ""
    if ws_name:match("^special:") then
        local mon = win.monitor or hl.get_active_monitor()
        local target = mon and mon.active_workspace and mon.active_workspace.id
        if target then
            hl.dispatch(hl.dsp.window.move({ window = win, workspace = target }))
        end
    else
        hl.dispatch(hl.dsp.exec_raw("movetoworkspacesilent", "special,address:" .. win.address))
    end
end
hl.bind(mainMod .. " + SHIFT + S", toggle_special_workspace)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special())
