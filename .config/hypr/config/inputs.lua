-- Input configuration

hl.config({
    input = {
        -- sensitivity = -0.25,
        accel_profile = "flat",
        -- Caps Lock only toggles with Ctrl+Caps Lock; alone it does
        -- nothing. kb_file loads a hand-compiled keymap (latam layout +
        -- the CAPS key remapped to an XKB type that only emits the
        -- Caps_Lock symbol while Control is held). kb_file replaces
        -- kb_layout/kb_options -- if you need to change the layout, you
        -- have to regenerate the file (see the comment at the end of this file).
        kb_file = os.getenv("HOME") .. "/.config/hypr/custom-capslock.xkb", -- @astrax-keymap (install.sh may swap this line for a kb_layout)
    },
    -- cursor: no_hardware_cursors lives in config/misc.lua (marker @mouse-fix,
    -- toggled by `mouse fix on|off`)
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "down",       action = "close" })
hl.gesture({ fingers = 3, direction = "up",         action = "fullscreen" })
hl.gesture({ fingers = 3, direction = "left",       action = "float" })

-- To regenerate ~/.config/hypr/custom-capslock.xkb if you need to change the
-- layout:
--   xkbcli compile-keymap --layout latam > ~/.config/hypr/custom-capslock.xkb
-- and then replace the "key <CAPS>" line (find it with grep) with:
--   key <CAPS> { type= "PC_CONTROL_LEVEL2", symbols[1]= [ NoSymbol, Caps_Lock ] };
-- (PC_CONTROL_LEVEL2 is already defined in the keymap: level 1 without Control,
-- level 2 with Control -- that's why NoSymbol/Caps_Lock is enough there).
