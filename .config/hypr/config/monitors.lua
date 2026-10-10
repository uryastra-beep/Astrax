-- Monitors: the ONLY place where they are configured.
--
-- By default MONITOR_LAYOUT is empty and Hyprland sets up every output by
-- itself (preferred mode, automatic position and scale), so Astrax works on
-- any hardware. Add one entry per output to pin a mode/position/scale. The
-- names come from `hyprctl monitors`; variables.lua names the two outputs the
-- scripts call p1 and p2 (MONITOR1 / MONITOR2).
--
-- Example (the author's laptop + 200Hz HDMI monitor):
--   MONITOR_LAYOUT = {
--       { output = "eDP-1",    mode = "1920x1080@60",  position = "-1536x0", scale = "1.25" },
--       { output = "HDMI-A-1", mode = "1920x1080@200", position = "0x0",     scale = "1" },
--   }
--
-- A custom mode outside the EDID (an overclock) does NOT survive a
-- "hyprctl reload" on an already connected monitor -- Hyprland resets it to the
-- preferred one. That's why autostart.lua calls apply_monitors() again on
-- "hyprland.start" and "config.reloaded". Overclocking is entirely optional and
-- at your own risk: test it on YOUR panel (see `hz` in scripts/hz-ctl.sh).
MONITOR_LAYOUT = {
}

function apply_monitors()
    for _, m in ipairs(MONITOR_LAYOUT) do
        hl.monitor(m)
    end
end

apply_monitors()
