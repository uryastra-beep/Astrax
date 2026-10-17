function mouse --description 'Change the cursor animation mode (hypr-dynamic-cursors)'
    set -l config "$HOME/.config/hypr/config/plugins.lua"
    set -l config_fix "$HOME/.config/hypr/config/misc.lua"
    set -l modes tilt rotate stretch none

    if not test -f "$config"
        echo "mouse: $config doesn't exist" >&2
        return 1
    end

    set -l current (hyprctl getoption plugin:dynamic-cursors:mode 2>/dev/null | string match -rg '^str: (.+)$')

    switch "$argv[1]"
        case '' status
            if test -z "$current"
                echo "mode: (plugin not loaded)"
            else
                echo "mode: $current"
            end
            echo "type 'mouse help' to see the commands"
            return 0

        case help -h --help
            echo "mouse -- cursor animation mode"
            echo
            echo "  mouse tilt      tilts the cursor with horizontal speed (subtle)"
            echo "  mouse rotate    rotates the cursor towards where it moves"
            echo "  mouse stretch   stretches/deforms the cursor with speed"
            echo "  mouse none      no movement animation (keeps only shake to find)"
            echo
            echo "  mouse fix on    software cursor (visible when screen sharing, e.g. Discord/Vesktop)"
            echo "  mouse fix off   back to the hardware cursor (default)"
            echo
            echo "  mouse           shows the active mode"
            echo "  mouse status    idem"
            echo "  mouse help      this help"
            echo
            echo "The change is written to plugins.lua, so it survives restarts."
            echo
            echo "Fixed modes per cursor shape (shape_rule in plugins.lua,"
            echo "not touched by this command):"
            echo "  text (I)     rotate"
            echo "  hand         rotate"
            echo
            echo "The reactive cursor's style and animations: cursor-style (SUPER+C > General)."
            return 0

        case $modes
            set -l new_value $argv[1]

            # the plugin does NOT validate 'mode': a typo is silently accepted and
            # leaves the cursor without animation, so we validate here first.
            # anchored to the @mouse-mode marker to touch ONLY the global mode
            # and not the "mode" of the per-shape shape_rules.
            sed -i -E "s/^(\s*)mode = \"[a-z]*\", -- @mouse-mode\$/\1mode = \"$new_value\", -- @mouse-mode/" "$config"

            if not grep -qE "^\s*mode = \"$new_value\", -- @mouse-mode\$" "$config"
                echo "mouse: couldn't write the mode to $config" >&2
                return 1
            end

            hyprctl reload >/dev/null 2>&1

            set -l applied (hyprctl getoption plugin:dynamic-cursors:mode 2>/dev/null | string match -rg '^str: (.+)$')
            if test "$applied" = "$new_value"
                echo "mode: $new_value"
            else
                echo "mouse: wrote '$new_value' but Hyprland reports '$applied'" >&2
                echo "       check the error banner on screen" >&2
                return 1
            end

        case fix
            if not test -f "$config_fix"
                echo "mouse: $config_fix doesn't exist" >&2
                return 1
            end

            set -l new_value
            switch "$argv[2]"
                case on
                    set new_value 1
                case off
                    set new_value 2
                case '*'
                    echo "mouse: use 'mouse fix on' or 'mouse fix off'" >&2
                    return 1
            end

            sed -i -E "s/^(\s*)no_hardware_cursors = [0-9]+, -- @mouse-fix\$/\1no_hardware_cursors = $new_value, -- @mouse-fix/" "$config_fix"

            if not grep -qE "^\s*no_hardware_cursors = $new_value, -- @mouse-fix\$" "$config_fix"
                echo "mouse: couldn't write to $config_fix" >&2
                return 1
            end

            hyprctl reload >/dev/null 2>&1

            set -l applied (hyprctl getoption cursor:no_hardware_cursors 2>/dev/null | string match -rg '^int: (-?[0-9]+)$')
            if test "$applied" = "$new_value"
                if test "$new_value" = 1
                    echo "fix: on  (software cursor -- visible when screen sharing)"
                else
                    echo "fix: off (hardware cursor -- default)"
                end
            else
                echo "mouse: wrote '$new_value' but Hyprland reports '$applied'" >&2
                return 1
            end

        case '*'
            echo "mouse: unknown mode '$argv[1]'" >&2
            echo "       valid: $modes" >&2
            echo "       'mouse help' for help" >&2
            return 1
    end
end
