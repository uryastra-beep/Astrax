hl.config({
    dwindle = {
        preserve_split = true,
    },
    cursor = {
        -- don't teleport the pointer when focus/workspace changes between
        -- monitors (the mouse used to jump to the widgets screen)
        no_warps = true,
        -- 1 = software cursor (visible when screen sharing in Vesktop/
        -- Discord, because the hardware cursor plane is outside what
        -- wlr-screencopy captures); 2 = auto/default. Toggle: `mouse fix on|off`
        no_hardware_cursors = 1, -- @mouse-fix
        -- hide the cursor after 2s without moving (it comes back as soon
        -- as you move/click)
        inactive_timeout = 2,
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
    misc = {
        col = {
            splash = CACHYLGREEN,
        },
        -- no Hyprland logo/background or splash text on startup: until
        -- the intro (astrax-intro) shows up only the theme base color is visible,
        -- same as the intro's first frame
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "rgba(110d12ff)",
        middle_click_paste = false,
        enable_swallow = true,
        swallow_regex = "(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)",
        vrr = 3,
    },
    render = {
        direct_scanout = 2,
    },
    xwayland = {
        force_zero_scaling = true
    },
})
