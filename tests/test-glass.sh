#!/usr/bin/env bash
# Level 2: island-blur.lua against a fake `hl` API (no Hyprland needed): Liquid Glass blur is off
# while opti is on and comes back when it is off. Run: bash tests/test-glass.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LUA="$(command -v lua5.4 || command -v lua || true)"
[ -n "$LUA" ] || { echo "  skip no lua interpreter"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { local what="$1"; shift; if "$@"; then printf '  ok   %s\n' "$what"; else printf '  FAIL %s\n' "$what"; fail=1; fi; }

mkdir -p "$T/.local/state" "$T/.config/hypr/config" "$T/.config/serpantinum"
cp "$REPO/.config/hypr/config/decorations.lua" "$T/.config/hypr/config/"
run() {  # run <opti on|off> <sharp on|off> <srp liquid true|false> -> prints the last blur config
    echo "$1" > "$T/.local/state/opti"; echo "$2" > "$T/.local/state/sharp-transparent"
    echo "{\"blurBackground\": $3, \"blurStyle\": \"liquid\"}" > "$T/.config/serpantinum/settings.json"
    HOME="$T" "$LUA" - "$REPO/.config/hypr/config/island-blur.lua" <<'LUA'
local last = {}
local function rule() return { set_enabled = function(_, v) end } end
hl = { window_rule = rule, layer_rule = rule,
       config = function(t) local b = t.decoration.blur; for k, v in pairs(b) do last[k] = v end end }
dofile(arg[1])
print(tostring(last.enabled) .. " " .. tostring(last.size) .. " " .. tostring(last.passes))
LUA
}
check "opti off, nothing else: back to decorations.lua values" [ "$(run off off false)" = "true 5 4" ]
check "opti off + Serpantinum liquid glass: size 3, 2 passes" [ "$(run off off true)" = "true 3 2" ]
check "opti off + sharp mode: blur stays on for the island" [ "$(run off on false)" = "true 1 2" ]
check "opti on: size and passes are left to opti" [ "$(run on off true)" = "true nil nil" ]
check "opti on + sharp mode: blur fully off" [ "$(run on on false)" = "false nil nil" ]
[ "$fail" = 0 ] && echo "All good." || { echo "Some checks failed."; exit 1; }
