function clear --description 'Clear the screen and scrollback without closing the session'
    printf '\033[2J\033[3J\033[H'
end
