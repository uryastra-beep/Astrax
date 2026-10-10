function sudo --description 'sudo with a guard against "rm -rf / --no-preserve-root"'
    set -l joined (string join ' ' -- $argv)

    # --no-preserve-root is the only real reason for rm to ignore its
    # own built-in protection against deleting "/" -- almost nobody
    # actually needs it. If it shows up next to rm, block it outright.
    if string match -qi '*rm*' -- $joined; and string match -q '*--no-preserve-root*' -- $joined
        echo "BLOCKED: 'rm ... --no-preserve-root' -- not running it." >&2
        return 1
    end

    # extra guard: recursive/forced rm pointing literally at "/"
    # (with or without --no-preserve-root -- in case the flag order changes).
    if string match -qr -- '(^|\s)rm\s+.*-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*(\s+\S+)*\s+/(\s|$)' -- $joined
        or string match -qr -- '(^|\s)rm\s+.*-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*(\s+\S+)*\s+/(\s|$)' -- $joined
        echo "BLOCKED: looks like 'rm -rf /' -- not running it." >&2
        return 1
    end

    command sudo $argv
end
