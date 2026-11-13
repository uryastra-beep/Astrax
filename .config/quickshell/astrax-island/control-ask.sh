#!/bin/sh
# Ask Claude or Codex one question from the island control panel. Prints only the answer.
# usage: control-ask.sh claude|codex "question" [file…]
# Attached files are read-only: Claude gets the Read tool limited to their folders, Codex runs read-only
# (images go in with -i so it sees them).
who="$1"; q="$2"; shift 2
# model picked in Super+C / Super+Shift+C > Dynamic Island ("" = each tool's own default)
model="$(python3 -I -c '
import json, os, sys
try:
    d = json.load(open(os.path.expanduser("~/.config/serpantinum/settings.json"))).get("island", {})
except Exception:
    d = {}
v = d.get({"claude": "askClaudeModel", "codex": "askCodexModel"}.get(sys.argv[1], ""), "")
print(v if isinstance(v, str) and v != "auto" and all(c.isalnum() or c in ".-_" for c in v) else "")' "$who" 2>/dev/null)"
cd /tmp || exit 1
effort="$(python3 -I -c '
import json, os, sys
try:
    d = json.load(open(os.path.expanduser("~/.config/serpantinum/settings.json"))).get("island", {})
except Exception:
    d = {}
v = d.get({"claude": "askClaudeEffort", "codex": "askCodexEffort"}.get(sys.argv[1], ""), "")
print(v if v in ("low", "medium", "high", "xhigh") else "")' "$who" 2>/dev/null)"
# PC control (Settings > Dynamic Island): on by default; "false" keeps Claude/Codex read-only
ctl="$(python3 -I -c '
import json, os
try:
    print("0" if json.load(open(os.path.expanduser("~/.config/serpantinum/settings.json"))).get("island", {}).get("askControl") is False else "1")
except Exception:
    print("1")' 2>/dev/null)"
CTLSYS="You are controlling the user's Linux PC (Hyprland). You may run shell commands, open apps, change files and settings to do what they ask, without asking for confirmation; use hyprctl, notify-send, etc. Never do destructive things they did not ask for (deleting their data, formatting, pushing to git). After acting, answer in the same language, short and direct (6 lines max), saying what you did."
list=""
for f in "$@"; do [ -e "$f" ] && list="$list
- $f"; done
[ -n "$list" ] && q="$q

Attached files (read them before answering):$list"
case "$who" in
  claude)
    if [ "$ctl" = 1 ]; then
      for f in "$@"; do shift; [ -e "$f" ] && set -- "$@" "--add-dir=$(dirname "$f")"; done
      set -- --permission-mode bypassPermissions "$@"
      exec timeout 300 claude -p --model "${model:-haiku}" ${effort:+--effort "$effort"} "$@" --no-session-persistence \
        --append-system-prompt "$CTLSYS" "$q" </dev/null
    fi
    if [ $# -gt 0 ]; then
      for f in "$@"; do shift; [ -e "$f" ] && set -- "$@" "--add-dir=$(dirname "$f")"; done
      set -- --tools Read "$@"
    else
      set -- --tools ""
    fi
    exec timeout 120 claude -p --model "${model:-haiku}" ${effort:+--effort "$effort"} "$@" --no-session-persistence \
      --append-system-prompt "Answer in the same language as the question, short and direct (6 lines max). No heavy markdown." "$q" </dev/null ;;
  codex)
    for f in "$@"; do shift; case "$f" in *.png|*.jpg|*.jpeg|*.webp|*.gif|*.PNG|*.JPG|*.JPEG) set -- "$@" -i "$f";; esac; done
    out="$(mktemp)"
    # `codex` from the PATH; fall back to the copy bundled with the desktop app
    codex_bin="$(command -v codex 2>/dev/null || true)"
    [ -z "$codex_bin" ] && [ -x "$HOME/.local/lib/chatgpt/resources/codex" ] && codex_bin="$HOME/.local/lib/chatgpt/resources/codex"
    [ -z "$codex_bin" ] && { echo "codex not found" >&2; exit 127; }
    if [ "$ctl" = 1 ]; then
      timeout 300 "$codex_bin" exec ${model:+-m "$model"} ${effort:+-c "model_reasoning_effort=\"$effort\""} --skip-git-repo-check --ephemeral -s danger-full-access "$@" \
        --output-last-message "$out" "$CTLSYS Request: $q" </dev/null >/dev/null 2>&1
    else
    timeout 150 "$codex_bin" exec ${model:+-m "$model"} ${effort:+-c "model_reasoning_effort=\"$effort\""} --skip-git-repo-check --ephemeral -s read-only "$@" \
      --output-last-message "$out" "Answer only what is asked, in the same language as the question, short and direct (6 lines max). Question: $q" </dev/null >/dev/null 2>&1
    fi
    cat "$out"; rm -f "$out" ;;
  *) echo "who?" >&2; exit 2 ;;
esac
