-- MONITOR1 (eDP-1) is NOT configured here: it was obsolete (old scale/mode/position
-- from an overclock experiment that no longer applies) and Hyprland also
-- resets custom modes outside the EDID on every reload, so it lives in
-- hyprland.lua (block "Custom monitor scaling") + autostart.lua
-- (function overclock_edp, re-applied on "hyprland.start" and "config.reloaded").
-- See those two files to change the laptop refresh rate/scale/position.

hl.monitor({
    output = MONITOR2,
    mode = "1920x1080@200",
    position = "0x0",
    scale = "1",
})
