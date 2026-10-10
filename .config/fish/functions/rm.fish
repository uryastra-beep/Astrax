function rm --description 'rm with a guard against "rm -rf / --no-preserve-root" (same rule as sudo.fish)'
    set -l joined (string join ' ' -- $argv)

    if string match -q '*--no-preserve-root*' -- $joined
        echo "BLOCKED: 'rm ... --no-preserve-root' -- not running it." >&2
        return 1
    end

    if string match -qr -- '^-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*(\s+\S+)*\s+/(\s|$)' -- $joined
        or string match -qr -- '^-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*(\s+\S+)*\s+/(\s|$)' -- $joined
        echo "BLOCKED: looks like 'rm -rf /' -- not running it." >&2
        return 1
    end

    command rm $argv
end
