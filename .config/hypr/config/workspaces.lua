-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Add your workspace rules here. Increment the workspace number as you go. Do not have duplicate workspaces.
hl.workspace_rule({ workspace = "name:gaming", monitor = PRIMARY_MONITOR })

-- eDP-1 (portatil): NUM_WPM workspaces (1..NUM_WPM)
for i = 1, NUM_WPM do
    hl.workspace_rule({ workspace = tostring(i), monitor = MONITOR1, default = true, persistent = true })
end

-- HDMI-A-1 (external monitor): NUM_WPM workspaces (NUM_WPM+1..NUM_WPM*2)
for i = 1, NUM_WPM do
    hl.workspace_rule({ workspace = tostring(NUM_WPM + i), monitor = MONITOR2, default = true, persistent = true })
end

-- For other layouts such as scrolling, see example below
-- hl.workspace_rule({ workspace = "1", monitor = MONITOR1, default = true, persistent = true, layout = scroling })
