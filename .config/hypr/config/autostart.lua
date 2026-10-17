-- Auto-start config

-- monitors.lua's MONITOR_LAYOUT is re-applied here: custom modes don't
-- survive a reload on their own (see monitors.lua).

-- opti: the optimized mode (fewer blur passes + taskbar watcher
-- stopped) is saved in ~/.local/state/opti and re-applied here. Without this,
-- ANY reload would silently wipe it -- including the internal reload
-- caelestia does when turning its gameMode OFF. See `opti status`.
local function reapply_opti()
    hl.exec_cmd(os.getenv("HOME") .. "/scripts/opti-ctl.sh reapply")
end

-- CTRL+SUPER+G (sharp corners + blur off): without this, any reload
-- (including Hyprland's own on config.reloaded) would re-read
-- rounding/blur from decorations.lua and silently turn it off.
local function reapply_sharp_transparent()
    hl.exec_cmd(os.getenv("HOME") .. "/scripts/sharp-transparent-ctl.sh reapply")
end

hl.on("config.reloaded", function ()
    apply_monitors()
    reapply_opti()
    reapply_sharp_transparent()
end)

hl.on("hyprland.start", function ()
    apply_monitors()

    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    -- splash screen: covers everything and reveals the desktop with theme
    -- waves (~5s, closes by itself). Runs first so it covers the startup.
    -- By hand: the `intro` command.
    hl.exec_cmd(os.getenv("HOME") .. "/scripts/intro.sh --boot")
    -- reactive cursor: apply the saved style's theme (cursor-style, SUPER+C > General)
    hl.exec_cmd(os.getenv("HOME") .. "/scripts/cursor-style.sh apply")
    -- intro when waking from suspend/hibernate without a lock (e.g. lid)
    hl.exec_cmd([[sh -c 'flock -n /tmp/resume-intro.lock bash ~/scripts/resume-intro.sh > /dev/null 2>&1']])
    -- HYPR_SHELL=serpantinum comes from the alternative SDDM session
    -- (/usr/share/wayland-sessions/hyprland-serpantinum.desktop). Without that
    -- variable (normal startup) it behaves exactly as usual.
    if os.getenv("HYPR_SHELL") == "serpantinum" then
        hl.exec_cmd("setsid nohup " .. os.getenv("HOME") .. "/.local/bin/serpantinumd start >/tmp/serpantinumd-boot.log 2>&1 < /dev/null &")
    else
        hl.exec_cmd("caelestia shell -d")
    end
    -- cliphist: without this "caelestia clipboard" (SUPER+V) breaks because
    -- nothing is storing the clipboard history. flock -n keeps it to one
    -- watcher per type (a `pgrep -f` guard here matched its own `sh -c`
    -- command line, so the watcher never started).
    hl.exec_cmd([[sh -c 'flock -n "${XDG_RUNTIME_DIR:-/tmp}/cliphist-text.lock" wl-paste --type text --watch cliphist store']])
    hl.exec_cmd([[sh -c 'flock -n "${XDG_RUNTIME_DIR:-/tmp}/cliphist-image.lock" wl-paste --type image --watch cliphist store']])
    -- custom launcher (tap SUPER). idempotent: won't start another if one is running.
    hl.exec_cmd([[sh -c 'mkdir -p ~/.local/state/astrax-launcher; qs list --all 2>/dev/null | grep -q "astrax-launcher/shell.qml" || qs -c astrax-launcher -d > /tmp/astrax-launcher.log 2>&1']])
    -- Astrax update check: a minute after login, then every 6 h; notifies once per new version
    hl.exec_cmd([[sh -c 'flock -n "${XDG_RUNTIME_DIR:-/tmp}/astrax-update.lock" bash ~/scripts/astrax-update.sh daemon > /tmp/astrax-update.log 2>&1']])
    -- bind search (SUPER+I), idempotent
    hl.exec_cmd([[sh -c 'qs list --all 2>/dev/null | grep -q "astrax-binds/shell.qml" || qs -c astrax-binds -d > /tmp/astrax-binds.log 2>&1']])
    -- custom app-switcher (Menu key), sister of astrax-launcher --
    -- lists open windows per screen. Same idempotent pattern.
    hl.exec_cmd([[sh -c 'mkdir -p ~/.local/state/astrax-app-switcher; qs list --all 2>/dev/null | grep -q "astrax-app-switcher/shell.qml" || qs -c astrax-app-switcher -d > /tmp/astrax-app-switcher.log 2>&1']])
    -- workspace number OSD (bottom-right corner, fades out by
    -- itself). Same idempotent pattern as the launchers.
    hl.exec_cmd([[sh -c 'qs list --all 2>/dev/null | grep -q "astrax-ws-osd/shell.qml" || qs -c astrax-ws-osd -d > /tmp/astrax-ws-osd.log 2>&1']])
    -- black power-off wave (physical button / power menu). idempotent.
    hl.exec_cmd([[sh -c 'qs list --all 2>/dev/null | grep -q "astrax-power-wave/shell.qml" || qs -c astrax-power-wave -d > /tmp/astrax-power-wave.log 2>&1']])
    -- logind must not power off on its own when the physical button is pressed:
    -- the bind above starts the cancellable wave instead. A session inhibitor
    -- (no root, released when the session ends) replaces editing logind.conf.
    hl.exec_cmd([[sh -c 'flock -n "${XDG_RUNTIME_DIR:-/tmp}/astrax-powerkey.lock" systemd-inhibit --what=handle-power-key --mode=block --who=Astrax --why="The power button starts the power-off wave" sleep infinity']])
    -- polkit agent: password window for pkexec (root with approval).
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    -- watchdog: relaunches it every 10s if Hyprland kills it. flock -n so
    -- it isn't duplicated if hyprland.start fires again.
    hl.exec_cmd([[sh -c 'flock -n /tmp/app-switcher-watchdog.lock bash ~/scripts/app-switcher-watchdog.sh > /dev/null 2>&1']])
    hl.exec_cmd([[sh -c 'log=/tmp/caelestia-autolock.log; : > $log; for i in $(seq 1 60); do if caelestia shell lock lock >> $log 2>&1; then echo locked on attempt $i >> $log; break; fi; echo attempt $i failed >> $log; sleep 0.5; done']])
    hl.exec_cmd("xhost +SI:localuser:root")
    -- mpvpaper disabled: the quoting was broken (sh -c only got
    -- "pgrep -f mpvpaper || mpvpaper -o no-audio") and pgrep -f also
    -- matched itself, so it never started. Serpantinum has its own
    -- wallpaper engine. Fixed version, Caelestia only:
    -- hl.exec_cmd([[sh -c 'pgrep -x mpvpaper || mpvpaper -o "no-audio loop hwdec=auto" "*" ~/wallpaper.mp4']])
    -- flock -n: if "hyprland.start" fires again (e.g. a hyprctl reload,
    -- not only the real startup), the second attempt doesn't get the lock and
    -- doesn't launch a duplicate watcher. Without this we ended up with 2-3
    -- instances of each script fighting each other (home monitor bouncing,
    -- widgets split across screens, turning on/off by themselves).
    hl.exec_cmd([[sh -c 'flock -n /tmp/widget-visibility.lock python3 ~/scripts/widget_visibility.py > /tmp/widget-visibility.log 2>&1']])
    -- SUPER+R window lock: puts pinned windows back in place.
    hl.exec_cmd([[sh -c 'flock -n /tmp/window-lock.lock python3 ~/scripts/window_lock.py daemon > /tmp/window-lock.log 2>&1']])
    hl.exec_cmd([[sh -c 'flock -n /tmp/border-colors.lock python3 ~/scripts/border_colors.py > /tmp/border-colors.log 2>&1']])
    hl.exec_cmd([[sh -c 'flock -n /tmp/gamemode-watcher.lock python3 ~/scripts/gamemode_watcher.py > /tmp/gamemode-watcher.log 2>&1']])
    -- opt-in (kills Brave once it has no windows left): touch ~/.config/astrax/enable-brave-watcher
    hl.exec_cmd([[sh -c '[ -e ~/.config/astrax/enable-brave-watcher ] || exit 0; flock -n /tmp/brave-watcher.lock bash ~/scripts/brave_watcher.sh > /tmp/brave-watcher.log 2>&1']])
    -- cursor_colors.py (cursor reacting to the song color) disabled
    -- on purpose: the mouse should NOT change color with the music.
    -- hl.exec_cmd([[sh -c 'flock -n /tmp/cursor-colors.lock python3 ~/scripts/cursor_colors.py > /tmp/cursor-colors.log 2>&1']])
    -- Taskbar: eww runs its own daemon (it handles the deflistens in
    -- eww.yuck by itself, no separate autostart needed for those). The only
    -- external piece is the watcher that shows/hides it based on the mouse.
    -- only if eww is installed: without eww the watcher kept polling
    -- Hyprland every 0.1s for nothing.
    hl.exec_cmd([[sh -c 'command -v eww >/dev/null || exit 0; flock -n /tmp/eww-daemon.lock eww daemon > /tmp/eww-daemon.log 2>&1']])
    hl.exec_cmd([[sh -c 'command -v eww >/dev/null || exit 0; sleep 1; flock -n /tmp/taskbar-visibility.lock python3 ~/scripts/taskbar_visibility.py > /tmp/taskbar-visibility.log 2>&1']])
    -- the internal speaker volume starts at ~41% even if it was left at
    -- 0% (WirePlumber bug, see boot_volume_fix.sh). Only on a real boot,
    -- not on every reload, so it doesn't override the volume while you're
    -- listening to something and reload the config.
    hl.exec_cmd([[sh -c 'sleep 2; bash ~/scripts/boot_volume_fix.sh > /tmp/boot-volume-fix.log 2>&1']])
    reapply_opti()
    reapply_sharp_transparent()
end)
