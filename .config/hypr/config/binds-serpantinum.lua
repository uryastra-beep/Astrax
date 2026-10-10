local mainMod = "SUPER"
local terminal = "kitty"

-- tap SUPER -> custom launcher (same as in the Caelestia session)
hl.bind(mainMod .. " + SUPER_L", hl.dsp.exec_cmd("qs ipc -c astrax-launcher call launcher toggle"), { release = true })

-- physical Menu/Application key -> custom app-switcher, ONLY the screen
-- focused right now (see astrax-app-switcher/shell.qml). The monitor
-- name is resolved at press time (not hardcoded) to call that specific
-- instance's IpcHandler. Also ALT+Tab (the physical "Copilot" key
-- didn't work -- we tried XF86Copilot, a keysym that doesn't exist
-- in xkeyboard-config 2.48, and then SUPER+SHIFT+XF86Assistant
-- according to wev, no luck either -- that attempt was dropped). No previous
-- ALT+Tab bind in this file (checked before adding it).
local toggleAppSwitcher = hl.dsp.exec_cmd("sh -c 'mon=$(hyprctl monitors -j | jq -r \".[] | select(.focused==true) | .name\"); qs ipc -c astrax-app-switcher call \"appswitcher-$mon\" toggle'")
hl.bind("Menu", toggleAppSwitcher)
hl.bind("ALT + Tab", toggleAppSwitcher)

-- SUPER + scroll -> switch workspace
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "m+1" }))

-- SUPER + W -> toggle wallpaper picker
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("serpantinum msg toggle wallpaper"))
-- CTRL+SUPER+W -> network/bluetooth panel (it has both tabs).
-- There is no separate native toggle for bluetooth,
-- only "network" (which includes the bt tab).
hl.bind(mainMod .. " + CONTROL + W", hl.dsp.exec_cmd("serpantinum msg toggle network"))

-- SUPER+SHIFT+W -> on/off toggle of the widget set (clock+lavat) + the
-- native Serpantinum preset on the screen focused right now (see
-- widget-preset-toggle.sh). Serpantinum only -- Caelestia's SUPER+SHIFT+W
-- (nexus, binds.lua) stays intact, this one only overrides it in the
-- Serpantinum session.
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(os.getenv("HOME") .. "/scripts/widget-preset-toggle.sh"))

-- CTRL+SUPER+ALT+G -> hide/show Serpantinum's native desktop widgets
-- (battery, CPU, RAM, clock, user panel, etc), ONLY on the
-- screen focused right now (per screen, it used to
-- toggle both at once). toggleVisible() was added to the IpcHandler
-- of WidgetLoader.qml (there was no built-in global toggle, only
-- per-widget editing).
hl.bind(mainMod .. " + CONTROL + ALT + G", hl.dsp.exec_cmd("sh -c 'mon=$(hyprctl monitors -j | jq -r \".[] | select(.focused==true) | .name\"); serpantinum ipc call \"widgets-$mon\" toggleVisible'"))

-- CTRL+SUPER+S -> mute/unmute the video wallpaper audio
hl.bind(mainMod .. " + CONTROL + S", hl.dsp.exec_cmd("serpantinum ipc call wallpaperAudio toggle"))

-- CTRL+SUPER+SHIFT+S -> the wallpaper audio keeps playing even when
-- app(s) cover the screen (both screens busy included) -- p1
-- (eDP-1) still has fixed priority to play if it has a video
-- wallpaper set. Independent from CTRL+SUPER+A (that one is visual/pause only).
-- Toggle.
hl.bind(mainMod .. " + CONTROL + SHIFT + S", hl.dsp.exec_cmd("serpantinum ipc call wallpaperAudioThroughApps toggle"))

-- CTRL+SUPER+A -> the video wallpaper keeps playing and stays VISIBLE
-- through apps (it isn't paused or covered by the static fallback
-- image). Toggle -- press again to return to the default behaviour
-- (static by default when covered).
hl.bind(mainMod .. " + CONTROL + A", hl.dsp.exec_cmd("serpantinum ipc call wallpaperKeepAnimated toggle"))

-- Note: Serpantinum's SUPER+D, SUPER+Arrows, SUPER+SHIFT+Arrows and SUPER+CTRL+Arrows
-- were NOT added because they clash with the infinite-desktop binds
-- that already live in hyprland.lua (floating_tile_toggle and navigate/move windows).

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))

-- SUPER + hold left click + move -> drag floating window
-- (same mechanism Caelestia already uses, mouse:272 = left button)
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("serpantinum brightness lower"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("serpantinum brightness raise"), { locked = true })

hl.bind("Print", hl.dsp.exec_cmd("serpantinum screenshot"), { locked = true })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("serpantinum screenshot --edit"), { locked = true })
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("serpantinum screenshot --full"), { locked = true })
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("serpantinum screenshot --full --edit"), { locked = true })

-- physical button: tap = the black wave starts rising (3.5s, then power off); another
-- tap before it reaches the top = it drops and cancels. (The button sends press+release
-- together, "holding" can't be measured.) Lock moved to CTRL+Power.
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("qs -c astrax-power-wave ipc call wave toggle"), { locked = true })
hl.bind("CTRL + XF86PowerOff", hl.dsp.exec_cmd("serpantinum lock"), { locked = true })
-- SUPER+Power: reboot straight into CachyOS without the GRUB menu (fast-reboot.sh)
hl.bind("SUPER + XF86PowerOff", hl.dsp.exec_cmd("bash " .. os.getenv("HOME") .. "/scripts/fast-reboot.sh"), { locked = true })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("serpantinum lock"), { repeating = true, locked = true })

hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("serpantinum msg toggle launcher"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("serpantinum volume mic-toggle"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("serpantinum volume mute-toggle"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("serpantinum volume lower"), { repeating = true, locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("serpantinum volume raise"), { repeating = true, locked = true })

hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("nautilus"))
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))

-- SUPER+R: pin/unpin the focused window (window_lock.py). Replaces "serpantinum reload".
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("python3 " .. os.getenv("HOME") .. "/scripts/window_lock.py toggle"))
-- SUPER+C freed for the settings menu (below). Serpantinum's native
-- clipboard toggle that was on CTRL+SUPER+C was removed without
-- reassigning (SUPER+V is still Caelestia's clipboard, the one
-- actually used) -- that key is now the music color mode, see
-- below.
-- Serpantinum settings menu (the same panel as
-- "guide" on SUPER+H -- Welcome/General/Display/Widgets/Theme/Bar/etc).
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("serpantinum msg toggle guide"))

-- CTRL+SUPER+C -> toggle "color from music" mode: the mauve/pink of ALL
-- native Serpantinum widgets (sprw) and of the custom widgets
-- (kitty+cava, via border_colors.py) follow the current album art
-- color. With no music playing it does NOT turn off or fall back to the
-- wallpaper -- it stays purple until something plays again. Serpantinum
-- only (makes no sense under Caelestia, which doesn't use ThemeBackend.qml).
--
hl.bind(mainMod .. " + CONTROL + C", hl.dsp.exec_cmd("serpantinum ipc call widgetColorMode toggleMusic"))

-- ALT+SUPER+C -> toggle "color from wallpaper" mode: forces the REAL color
-- of the current wallpaper (animated or static), ignoring any static
-- preset picked in Serpantinum. Serpantinum only -- Caelestia's ALT+SUPER+C
-- (session drawer, binds.lua) stays intact, this one only overrides it
-- in the Serpantinum session.
hl.bind(mainMod .. " + ALT + C", hl.dsp.exec_cmd("serpantinum ipc call widgetColorMode toggleWallpaper"))
hl.bind(mainMod .. " + CONTROL + Z", hl.dsp.exec_cmd("serpantinum msg toggle music"))
-- SUPER+M: opens/focuses a small floating Spotify on the current
-- screen/workspace; if it's already there, hides it (Spotify has no real
-- tray on Linux, this replaces it -- see spotify-toggle.sh).
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(os.getenv("HOME") .. "/scripts/spotify-toggle.sh"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("brave"))
hl.bind(mainMod .. " + CONTROL + B", hl.dsp.exec_cmd("serpantinum msg toggle system"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("serpantinum msg toggle calendar"))
-- The network panel that was on SUPER+N was removed without reassigning
-- -- that key is now the notifications "do not disturb"
-- toggle (see NotificationManager.qml, IPC target "dnd"). With dnd
-- on, non-critical popups are invisible and silent -- easy to
-- mistake for "notifications don't show up".
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("serpantinum ipc call dnd toggle"))
-- SUPER+V freed for the clipboard (Caelestia convention); Serpantinum's
-- default volume toggle moved to CTRL+SUPER+V.
hl.bind(mainMod .. " + CONTROL + V", hl.dsp.exec_cmd("serpantinum msg toggle volume"))
-- same clipboard as Caelestia (cliphist + fuzzel), not Serpantinum's own
-- panel -- standalone, doesn't depend on which shell is running.
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("caelestia clipboard"))
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("serpantinum msg toggle guide"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("serpantinum msg toggle autohide"))
-- emoji picker: standalone caelestia command (fuzzel --dmenu), doesn't
-- depend on the caelestia shell running.
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("caelestia emoji -p"))

-- Real BUG: "serpantinum msg workspace N" runs
-- "hyprctl dispatch workspace N" -- that isn't even valid syntax in
-- this hyprland-lua (fails with "')' expected"), and its fallback
-- (hl.dsp.focus with an absolute ID) doesn't respect the
-- infinite-desktop-v2 scheme either, which addresses workspaces as "m~N" (relative to the
-- CURRENT monitor, not a global ID). That's why SUPER+number did
-- nothing. Fix: use the same native dispatcher Caelestia already uses
-- (hl.dsp.focus/hl.dsp.window.move with "m~N"), bypassing the
-- Serpantinum CLI for this.
for i = 1, 10 do
  local key = tostring(i % 10)
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = "m~" .. i }))
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = "m~" .. i }))
end
