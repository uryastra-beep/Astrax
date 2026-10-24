-- Window rules wiki https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- Generic floating position
hl.window_rule({ match = { float = true }, center = true, persistent_size = true })

-- Picture-in-Picture
hl.window_rule({
    match             = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" },
    float             = true,
    keep_aspect_ratio = true,
    size              = { "max(monitor_w, monitor_h)*0.25", "min(monitor_w, monitor_h)*0.25" },
    pin               = true,
})

-- Gaming
local gamingApps = "^(steam_app.*|gamescope)$"
local gamingWorkspace = "name:gaming"

hl.window_rule({ match = { content = "game" }, workspace = gamingWorkspace })
hl.window_rule({ match = { xdg_tag = "^(.*game.*)$" }, workspace = gamingWorkspace, fullscreen_state = 2, content = "game", sync_fullscreen = true })
hl.window_rule({ match = { class = gamingApps }, workspace = gamingWorkspace })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Friends List)$" }, float = true })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Launching\\.{3})$" }, float = true, center = true, workspace = gamingWorkspace })
hl.window_rule({
    match = {
        class         = gamingApps,
        title         = "^(.+)$",
        initial_title = "negative:^(.*\\\\home\\\\.*)$",
    },
    content          = "game",
    decorate         = false,
    fullscreen_state = 2,
    size             = { "monitor_w", "monitor_h" },
    sync_fullscreen  = true,
})
hl.window_rule({
    match = {
        class         = "^(steam_app.*)$",
        initial_title = "^$",
    },
    center           = true,
    float            = true,
    fullscreen       = false,
    fullscreen_state = 0,
    workspace        = gamingWorkspace,
})

-- Apps
hl.window_rule({ match = { class = "^(.*\\.exe)$", float = true }, monitor = PRIMARY_MONITOR, center = true, fullscreen_state = 0 })
hl.window_rule({ match = { class = "^(.*[Ll]auncher.*)$" }, float = true, monitor = PRIMARY_MONITOR })
hl.window_rule({ match = { class = "^(vesktop|discord)$" }, monitor = PRIMARY_MONITOR })
hl.window_rule({ match = { class = "^(.*[Cc]alc.*)$" }, float = true, size = { "max(monitor_w, monitor_h)*0.17", "min(monitor_w, monitor_h)*0.43" } })
hl.window_rule({ match = { class = "^(show-hz)$" }, float = true, center = true, size = { 260, 220 } })
hl.window_rule({ match = { class = "^(org\\.kde\\.keditfiletype)$" }, float = true })
hl.window_rule({ match = { class = "^(org\\.kde\\.ark)$" }, size = { "max(monitor_w, monitor_h)*0.40", "min(monitor_w, monitor_h)*0.40" } })
hl.window_rule({ match = { class = "^(.*satty.*)$", title = "^(Satty)$" }, min_size = { "max(monitor_w, monitor_h)*0.35", "min(monitor_w, monitor_h)*0.35" }, float = true })
hl.window_rule({ match = { class = "^(dev\\.)?(noctalia\\.Noctalia(\\.Settings)?)$" }, float = true, size = { "monitor_w*0.70", "monitor_h*0.70" } })
hl.window_rule({
    match = {
        class = "^(org\\.kde\\.dolphin)$",
        title = "negative:^(Moving.*|Create New.*|Extract.*|Compress.*|Copying.*|Progress.*|Configure.*|Properties.*|Choose\\sApplication.*)$",
    },
    float = true,
    size = { "max(monitor_w, monitor_h)*0.50", "min(monitor_w, monitor_h)*0.55" },
    move = {
        "max(20, min(cursor_x - (window_w*0.50), monitor_w - window_w + 20))", -- X axis clamping
        "max(20, min(cursor_y - 50, monitor_h - window_h + 20))" -- Y axis clamping
    },
})

-- Opacity Overrides
local terminals = "^(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)$"

hl.window_rule({ match = { class = "^(firefox|zen)$" }, opacity = "1.0 override" })
hl.window_rule({ match = { class = terminals }, opacity = "1.0 override" }) -- Override opacity in favor of terminal settings for opacity. If your terminal doesn't support transparency, you can remove this rule.
hl.window_rule({ match = { class = "^(mpv|org.kde.haruna|.*plex.*|org\\.kde\\.gwenview|.*vlc.*)$" }, opacity = "1.0 override" })

-- Float Utility Windows
local floatApps = {
    { class = "^(kvantummanager|qt[56]ct|nwg-look)$" },
    { class = "^(org.pulseaudio.pavucontrol|blueman-manager|nm-applet|nm-connection-editor)$" },
    { title = "^(Winetricks.*|Protontricks.*)$" },
}
for _, m in ipairs(floatApps) do hl.window_rule({ match = m, float = true }) end

-- Float Common Modals
local modalMatches = {
    { title = "^(Open|Authentication Required|Add Folder to Workspace|Choose Files|Save As|Confirm to replace files|File Operation Progress)$" },
    { initial_title = "^(Open File)$" },
    { class = "^([Xx]dg-desktop-portal-gtk)$" },
    { title = "^(File Upload|Choose wallpaper|Library)(.*)$" },
    { class = "^(.*dialog.*)$" },
    { title = "^(.*dialog.*)$" },
    { class = "^(hyprland-share-picker)$"},
}
for _, m in ipairs(modalMatches) do hl.window_rule({ match = m, float = true }) end

-- Ignore maximize requests from all apps. You'll probably like this.
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-------------------------
---- DESKTOP WIDGETS ----
-------------------------
-- x, y, w, h are expressions (strings) relative to monitor_w/monitor_h, so
-- the layout adapts by itself regardless of the monitor's logical resolution
-- (the laptop has scale 1.25, i.e. a different logical resolution from the HDMI one).
local function widget(class, x, y, w, h, make_ghost)
    hl.window_rule({
        match    = { class = "^(" .. class .. ")$" },
        float    = true,
        decorate = false,
        move     = { x, y },
        size     = { w, h },
        suppress_event = "maximize",
    })
    if make_ghost == false then return end
    -- "ghost": same app, small offset, full opacity for a strong glow.
    -- no_blur only here (the main one keeps its blur).
    hl.window_rule({
        match    = { class = "^(" .. class .. "-ghost)$" },
        float    = true,
        decorate = false,
        no_focus = true,
        no_blur  = true,
        opacity  = "1.0 override",
        move     = { "(" .. x .. ") + 4", "(" .. y .. ") + 4" },
        size     = { w, h },
        suppress_event = "maximize",
    })
end

-- Layout: 2 full-height columns -- clock left, lavat right (50%x100%
-- each). cava and sptlrx were removed from this set (see
-- widget-ctl.sh) -- they were redundant with Serpantinum's native
-- visualizer/lyrics, which are now applied via preset in "widgets p1"/"p2".
local half_w   = "(monitor_w - 5) / 2"
local right_x  = "(monitor_w - 5) / 2 + 5"

widget("widget-clock",   "0",      "0", half_w, "monitor_h")
widget("widget-lavat",   right_x,  "0", half_w, "monitor_h", false) -- no ghost

--------------------------
---- DESKTOP WIDGETS 2 ---
--------------------------
-- Clock + lyrics (sptlrx) + fullscreen cava on top -- ONE
-- single wlr-layer-shell surface via Quickshell (not kitty windows, see
-- ~/.config/quickshell/widgets2/shell.qml and widget2-ctl.sh). Same reason as
-- widgets3: no window_rule needed (float/decorate/etc don't apply to layer
-- shell); the layer_rule below (namespace "widgets2") removes its animation.

-- Widgets live on whichever workspace they were opened on: switching away
-- never closes them, it just stops rendering them until you come back.
-- Sent to the bottom of the stack so any app opened there covers them.
hl.on("window.open", function(win)
    if win and win.class and win.class:match("^widget%-") then
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom", window = win }))
    end
end)

--------------------------
---- DESKTOP WIDGETS 3 ---
--------------------------
-- widgets3: fullscreen Cava visualizer rendered by Quickshell as a
-- wlr-layer-shell surface (not a kitty window) -- namespace "widgets3",
-- see ~/.config/quickshell/widgets3/shell.qml and widget3-ctl.sh. Being a layer
-- shell and not a normal window, it does NOT need a window_rule (float/decorate/etc
-- don't apply); a layer_rule with no_anim kills any in/out fade
-- Hyprland would add by default, so it feels 100% part of the
-- wallpaper with no transition.
hl.layer_rule({
    name    = "widgets3-no-anim",
    match   = { namespace = "^(widgets3)$" },
    no_anim = true,
})
hl.layer_rule({
    name    = "widgets2-no-anim",
    match   = { namespace = "^(widgets2)$" },
    no_anim = true,
})

--------------------------
---- DESKTOP WIDGETS 4 ---
--------------------------
-- widgets4: mini desktop (terminal + Now Playing/cava + btop).
-- The "Now Playing + mini cava" part is a wlr-layer-shell surface
-- (namespace "widgets4", layer_rule below) -- see
-- ~/.config/quickshell/widgets4/shell.qml. The mini terminal and btop ARE
-- normal kitty windows (interactive, they can't be click-through):
-- they live
-- on the target workspace, and widget4_visibility.py moves them to a
-- special workspace ("special:widgets4") to hide/show them
-- instantly WITHOUT killing them (so the terminal keeps its history/session).
-- no_anim=true on all 3 so that move-to-special is instant, without
-- Hyprland's open/close fade.
hl.layer_rule({
    name    = "widgets4-no-anim",
    match   = { namespace = "^(widgets4)$" },
    no_anim = true,
})

-- Positions/sizes set by hand live --
-- btop's in particular had to grow: at 420x340 btop threw
-- "Terminal size too small" (it wants 80x24 cells, only 44x16 fit).
hl.window_rule({
    match    = { class = "^(widget4-term)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "23", "458" },
    size     = { 768, 603 },
    suppress_event = "maximize",
})
hl.window_rule({
    match    = { class = "^(widget4-btop)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "802", "23" },
    size     = { 1097, 588 },
    suppress_event = "maximize",
})
hl.window_rule({
    match    = { class = "^(widget4-unimatrix)$" },
    float    = true,
    decorate = false,
    -- NO no_focus: unlike the old pipes, you need to be able to
    -- drag/resize it with the mouse to adjust the layout (e.g.
    -- the size pass for "widgets4 p1"). An unfocusable window is never a
    -- drag/resize target.
    no_anim  = true,
    move     = { "794", "625" },
    size     = { 1095, 430 },
    suppress_event = "maximize",
})
-- widget4-lavat: replaces the mini cava/Now Playing when no
-- player is playing (see widgets4's shell.qml and widget4_visibility.py).
-- Geometry = same area the Now Playing card takes on p2 (HDMI); the
-- per-monitor snap in widget4_visibility.py readjusts it for p1.
hl.window_rule({
    match    = { class = "^(widget4-lavat)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "26", "21" },
    size     = { 754, 417 },
    suppress_event = "maximize",
})

-- widgets5 (p2/HDMI-A-1 only, anchored to a workspace -- see widgets5-ctl.sh
-- and widgets5_visibility.py): term + unimatrix + lavat, geometry taken from
-- positions set live.
-- Note: "lavat covering the whole terminal area" did NOT mean
-- enlarging the lavat window to cover the terminal one on screen
-- (that was tried and reverted) -- it means lavat fills 100% of ITS
-- OWN kitty window (no padding), each one with its original geometry.
hl.window_rule({
    match    = { class = "^(widget5-term)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "20", "582" },
    size     = { 647, 495 },
    suppress_event = "maximize",
})
hl.window_rule({
    match    = { class = "^(widget5-unimatrix)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "1406", "15" },
    size     = { 504, 627 },
    suppress_event = "maximize",
})
hl.window_rule({
    match    = { class = "^(widget5-lavat)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "22", "16" },
    size     = { 649, 538 },
    suppress_event = "maximize",
})

-- widgets6 p1 (eDP-1): unimatrix + lavat + btop, geometry taken live
-- with a guide terminal -- official
-- version.
hl.window_rule({
    match    = { class = "^(widget6-unimatrix)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "3", "4" },
    size     = { 197, 856 },
    suppress_event = "maximize",
})
hl.window_rule({
    match    = { class = "^(widget6-lavat)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "203", "3" },
    size     = { 1331, 320 },
    suppress_event = "maximize",
})
hl.window_rule({
    match    = { class = "^(widget6-btop)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "204", "326" },
    size     = { 1329, 536 },
    suppress_event = "maximize",
})

-- widgets6 p2 (HDMI-A-1, ws21): same layout as p1 (narrow strip on the
-- left + 2 stacked panels on the right), its own geometry taken
-- live -- official version. Separate
-- classes (widget6-p2-*) so they don't clash with the p1 rule above.
hl.window_rule({
    match    = { class = "^(widget6-p2-unimatrix)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "5", "1" },
    size     = { 257, 1078 },
    suppress_event = "maximize",
})
hl.window_rule({
    match    = { class = "^(widget6-p2-lavat)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "266", "1" },
    size     = { 1654, 340 },
    suppress_event = "maximize",
})
hl.window_rule({
    match    = { class = "^(widget6-p2-btop)$" },
    float    = true,
    decorate = false,
    no_anim  = true,
    move     = { "265", "344" },
    size     = { 1654, 738 },
    suppress_event = "maximize",
})
-- If one of a pair (main/ghost) is closed, kill the other one too
hl.on("window.close", function(win)
    if not (win and win.class) then return end
    local base = win.class:match("^(widget%-%a+)%-ghost$")
    if base then
        hl.exec_cmd("pkill -f 'kitty --class " .. base .. " -o'")
    elseif win.class:match("^widget%-%a+$") then
        hl.exec_cmd("pkill -f 'kitty --class " .. win.class .. "-ghost -o'")
    end
    if base or win.class:match("^widget%-%a+$") then
        -- Marks a 5s cooldown ONLY if this didn't come from one of our restarts
        -- (song change, glow, etc) -- see widget-close-guard.sh.
        hl.exec_cmd("bash " .. os.getenv("HOME") .. "/scripts/widget-close-guard.sh")
    end
end)

-- Dragging (SUPER+click) a fullscreen window to another monitor
-- drops its FS -- Hyprland releases it when the drag starts and there's no way to
-- avoid it from the bind. Each window's FS state is remembered, and
-- if one loses it and lands on ANOTHER monitor within 30s, it's re-applied
-- there (e.g. Netflix in Brave).
local fs_memory = {}

local function monitor_name(win)
    return win.monitor and win.monitor.name or nil
end

hl.on("window.fullscreen", function(win)
    if not (win and win.address) then return end
    local fs = win.fullscreen or 0
    if fs > 0 then
        fs_memory[win.address] = {
            internal = fs,
            client = win.fullscreen_client or fs,
            monitor = monitor_name(win),
        }
    elseif fs_memory[win.address] then
        fs_memory[win.address].lost_at = os.time()
    end
end)

hl.on("window.move_to_workspace", function(win)
    if not (win and win.address) then return end
    local m = fs_memory[win.address]
    if not (m and m.lost_at) then return end
    if os.time() - m.lost_at > 30 then
        fs_memory[win.address] = nil
        return
    end
    if (win.fullscreen or 0) ~= 0 or monitor_name(win) == m.monitor then return end
    fs_memory[win.address] = nil
    hl.dispatch(hl.dsp.window.fullscreen_state({ internal = m.internal, client = m.client, window = win }))
end)

hl.on("window.destroy", function(win)
    if win and win.address then fs_memory[win.address] = nil end
end)





-- GLASS for the workspace OSD (astrax-ws-osd). Can be deleted together with
-- ~/.config/quickshell/astrax-ws-osd/Glass.qml if you don't like it.
hl.layer_rule({
    name         = "astrax-ws-osd-glass",
    match        = { namespace = "^(astrax-ws-osd)$" },
    blur         = true,
    ignore_alpha = 0.01,
})

-- GLASS for the Dynamic Island (astrax-island): blurs what is behind the
-- translucent notification / music cards. The idle pill is opaque black.
hl.layer_rule({
    name         = "astrax-island-glass",
    match        = { namespace = "^(astrax-island)$" },
    blur         = true,
    ignore_alpha = 0.05,
})

-- Liquid Glass blur for the Dynamic Island (and Serpantinum's liquid glass); see island-blur.lua.
require("config.island-blur")