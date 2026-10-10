function fish_user_key_bindings
    # Don't recall previous commands with the up/down arrows.
    for map in default insert
        bind -M $map up ''
        bind -M $map down ''
    end
end
