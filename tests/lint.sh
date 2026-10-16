#!/usr/bin/env bash
# Level 1: fast static checks. Run from anywhere: bash tests/lint.sh
# Needs: bash, python3, jq, luac (lua 5.4); shellcheck is used when present.
set -uo pipefail

cd "$(dirname "$0")/.."
fail=0
ok()  { printf '  ok   %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; fail=1; }

# every tracked file of a type (git ls-files keeps .git and junk out)
files() { git ls-files -z "$@" | xargs -0 -r -n1 echo; }

echo "== bash syntax (bash -n)"
n=0
while read -r f; do
    n=$((n + 1))
    bash -n "$f" 2>/tmp/astrax-lint.err || bad "$f: $(head -1 /tmp/astrax-lint.err)"
done < <(files '*.sh')
ok "$n shell scripts parsed"

echo "== shellcheck (errors only)"
if command -v shellcheck >/dev/null; then
    mapfile -t sh < <(files '*.sh')
    if shellcheck -S error "${sh[@]}"; then ok "${#sh[@]} scripts"; else bad "shellcheck found errors"; fi
else
    echo "  skip shellcheck not installed"
fi

echo "== python syntax"
n=0
while read -r f; do
    n=$((n + 1))
    python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>/tmp/astrax-lint.err \
        || bad "$f: $(tail -1 /tmp/astrax-lint.err)"
done < <(files '*.py')
ok "$n python files parsed"

echo "== lua syntax (luac -p)"
LUAC="$(command -v luac5.4 || command -v luac || true)"
if [ -n "$LUAC" ]; then
    n=0
    while read -r f; do
        n=$((n + 1))
        "$LUAC" -p "$f" 2>/tmp/astrax-lint.err || bad "$(head -1 /tmp/astrax-lint.err)"
    done < <(files '*.lua')
    ok "$n lua files parsed"
else
    bad "luac not installed"
fi

echo "== json syntax (jq)"
n=0
while read -r f; do
    n=$((n + 1))
    jq empty "$f" 2>/tmp/astrax-lint.err || bad "$f: $(head -1 /tmp/astrax-lint.err)"
done < <(files '*.json')
ok "$n json files parsed"

echo "== installer commands point at real scripts"
while read -r target; do
    [ -f "scripts/$target" ] || bad "install.sh links a command to scripts/$target, which doesn't exist"
done < <(grep -oE '\]=[A-Za-z0-9_.-]+\.(sh|py)' install.sh | cut -c3- | sort -u)
ok "command targets checked"

echo "== scripts the binds/autostart call exist"
# ~/scripts/<name> and os.getenv("HOME") .. "/scripts/<name>" references in the Hyprland config
while read -r ref; do
    [ -f "scripts/$ref" ] || bad "hypr config calls scripts/$ref, which isn't in the repo"
done < <(grep -rhoE '(~|HOME[")]* *\.\. *"|\$HOME)/scripts/[A-Za-z0-9_.-]+' .config/hypr | sed -E 's|.*/scripts/||' | sort -u)
ok "script references checked"

echo "== quickshell configs named in binds/autostart exist"
while read -r cfg; do
    [ -f ".config/quickshell/$cfg/shell.qml" ] || bad "hypr config starts quickshell config '$cfg', missing .config/quickshell/$cfg/shell.qml"
done < <(grep -rhoE 'qs (ipc )?-c [A-Za-z0-9_-]+|qs ipc -c [A-Za-z0-9_-]+' .config/hypr | awk '{print $NF}' | sort -u)
ok "quickshell config references checked"

echo "== no personal data"
# the public repo must not carry the author's home path, private names or email
if git grep -nIE '/home/ury|ury-(launcher|app-switcher|binds|intro|power-wave|ws-osd)|mazu_21|hotmail\.com' -- . ':!tests/lint.sh'; then
    bad "personal data found (see above)"
else
    ok "clean"
fi

echo
if [ "$fail" = 0 ]; then echo "lint: all checks passed"; else echo "lint: FAILED"; fi
exit "$fail"
