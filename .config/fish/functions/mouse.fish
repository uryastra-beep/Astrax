function mouse --description 'Change the cursor animation mode (hypr-dynamic-cursors)'
    set -l config "$HOME/.config/hypr/config/plugins.lua"
    set -l config_fix "$HOME/.config/hypr/config/misc.lua"
    set -l modos tilt rotate stretch none
    set -l stock_so "/var/cache/hyprpm/$USER/dynamic-cursors/dynamic-cursors.so"
    set -l trail_so "$HOME/.local/share/hypr-plugins/dynamic-cursors-trail.so"

    if not test -f "$config"
        echo "mouse: no existe $config" >&2
        return 1
    end

    set -l actual (hyprctl getoption plugin:dynamic-cursors:mode 2>/dev/null | string match -rg '^str: (.+)$')

    switch "$argv[1]"
        case '' status
            if test -z "$actual"
                echo "mode: (plugin not loaded)"
            else
                echo "mode: $actual"
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
            echo "  mouse trail on  cursor trail (UNOFFICIAL build, PR #161)"
            echo "  mouse trail off back to the normal plugin"
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
            echo "  text (I)     stretch"
            echo "  hand         tilt"
            return 0

        case $modos
            set -l nuevo $argv[1]

            # the plugin does NOT validate 'mode': a typo is silently accepted and
            # leaves the cursor without animation, so we validate here first.
            # anchored to the @mouse-mode marker to touch ONLY the global mode
            # and not the "mode" of the per-shape shape_rules.
            sed -i -E "s/^(\s*)mode = \"[a-z]*\", -- @mouse-mode\$/\1mode = \"$nuevo\", -- @mouse-mode/" "$config"

            if not grep -qE "^\s*mode = \"$nuevo\", -- @mouse-mode\$" "$config"
                echo "mouse: couldn't write the mode to $config" >&2
                return 1
            end

            hyprctl reload >/dev/null 2>&1

            set -l aplicado (hyprctl getoption plugin:dynamic-cursors:mode 2>/dev/null | string match -rg '^str: (.+)$')
            if test "$aplicado" = "$nuevo"
                echo "mode: $nuevo"
            else
                echo "mouse: wrote '$nuevo' but Hyprland reports '$aplicado'" >&2
                echo "       check the error banner on screen" >&2
                return 1
            end

        case trail
            # The trail lives in a patched build that is NOT in the config:
            # it is loaded/unloaded live, so it never survives a restart
            # (or a hyprctl reload triggered by something else).
            switch "$argv[2]"
                case on
                    if not test -f "$trail_so"
                        echo "mouse: missing $trail_so" >&2
                        echo "       rebuild it with ~/.local/share/hypr-plugins/build-trail.sh" >&2
                        return 1
                    end

                    if test (hyprctl getoption plugin:dynamic-cursors:trail:enabled 2>/dev/null | head -1) != "no such option"
                        echo "trail: already on"
                        return 0
                    end

                    hyprctl plugin unload "$stock_so" >/dev/null 2>&1
                    if not string match -q "ok*" (hyprctl plugin load "$trail_so" 2>&1)
                        echo "mouse: couldn't load the trail build" >&2
                        hyprctl plugin load "$stock_so" >/dev/null 2>&1
                        hyprctl reload >/dev/null 2>&1
                        return 1
                    end

                    # the plugin was loaded live, so it starts with the
                    # defaults: re-apply the global mode, shake and the
                    # per-shape rules that plugins.lua normally sets.
                    set -l modo_actual (string match -rg '^\s*mode = "([a-z]+)", -- @mouse-mode$' < "$config" | head -1)
                    test -n "$modo_actual"; or set modo_actual rotate
                    set -l shake_actual (string match -rg '^\s*enabled = (true|false), -- @mouse-shake$' < "$config" | head -1)
                    test -n "$shake_actual"; or set shake_actual false
                    hyprctl repl "hl.config({ plugin = { dynamic_cursors = { enabled = true, mode = \"$modo_actual\", shake = { enabled = $shake_actual }, trail = { enabled = true, rate = 3, lifetime = 500.0, fade = true } } } })" >/dev/null 2>&1
                    hyprctl repl 'hl.plugin.dynamic_cursors.shape_rule({ shape = "text", mode = "stretch" })' >/dev/null 2>&1
                    hyprctl repl 'hl.plugin.dynamic_cursors.shape_rule({ shape = "pointer", mode = "tilt" })' >/dev/null 2>&1

                    if test (hyprctl getoption plugin:dynamic-cursors:trail:enabled 2>/dev/null | head -1) = "bool: true"
                        echo "trail: on  (mode $modo_actual -- ephemeral, gone on any reload)"
                    else
                        echo "mouse: the build loaded but the trail isn't active" >&2
                        return 1
                    end

                case off
                    if test (hyprctl getoption plugin:dynamic-cursors:trail:enabled 2>/dev/null | head -1) = "no such option"
                        echo "trail: already off"
                        return 0
                    end

                    hyprctl plugin unload "$trail_so" >/dev/null 2>&1
                    hyprctl reload >/dev/null 2>&1

                    # unloading by hand leaves the plugin bookkeeping out
                    # of sync and the config's hl.plugin.load becomes a
                    # no-op: if no plugin is left, load it explicitly.
                    if test -z (hyprctl plugin list 2>/dev/null | string match -r 'dynamic-cursors')
                        hyprctl plugin load "$stock_so" >/dev/null 2>&1
                        hyprctl reload >/dev/null 2>&1
                    end

                    set -l m (hyprctl getoption plugin:dynamic-cursors:mode 2>/dev/null | string match -rg '^str: (.+)$')
                    if test -n "$m"
                        echo "trail: off  (mode $m)"
                    else
                        echo "mouse: the normal plugin didn't load back" >&2
                        return 1
                    end

                case '*'
                    echo "mouse: usa 'mouse trail on' o 'mouse trail off'" >&2
                    return 1
            end

        case fix
            if not test -f "$config_fix"
                echo "mouse: no existe $config_fix" >&2
                return 1
            end

            set -l nuevo
            switch "$argv[2]"
                case on
                    set nuevo 1
                case off
                    set nuevo 2
                case '*'
                    echo "mouse: usa 'mouse fix on' o 'mouse fix off'" >&2
                    return 1
            end

            sed -i -E "s/^(\s*)no_hardware_cursors = [0-9]+, -- @mouse-fix\$/\1no_hardware_cursors = $nuevo, -- @mouse-fix/" "$config_fix"

            if not grep -qE "^\s*no_hardware_cursors = $nuevo, -- @mouse-fix\$" "$config_fix"
                echo "mouse: couldn't write to $config_fix" >&2
                return 1
            end

            hyprctl reload >/dev/null 2>&1

            set -l aplicado (hyprctl getoption cursor:no_hardware_cursors 2>/dev/null | string match -rg '^int: (-?[0-9]+)$')
            if test "$aplicado" = "$nuevo"
                if test "$nuevo" = 1
                    echo "fix: on  (software cursor -- visible when screen sharing)"
                else
                    echo "fix: off (hardware cursor -- default)"
                end
            else
                echo "mouse: wrote '$nuevo' but Hyprland reports '$aplicado'" >&2
                return 1
            end

        case '*'
            echo "mouse: unknown mode '$argv[1]'" >&2
            echo "       valid: $modos" >&2
            echo "       'mouse help' for help" >&2
            return 1
    end
end
