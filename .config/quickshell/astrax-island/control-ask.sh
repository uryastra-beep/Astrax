#!/bin/sh
# Ask Claude or Codex one question from the island control panel. Prints only the answer.
# usage: control-ask.sh claude|codex "question" [file…]
# Attached files are read-only: Claude gets the Read tool limited to their folders, Codex runs read-only
# (images go in with -i so it sees them).
who="$1"; q="$2"; shift 2
cd /tmp || exit 1
list=""
for f in "$@"; do [ -e "$f" ] && list="$list
- $f"; done
[ -n "$list" ] && q="$q

Attached files (read them before answering):$list"
case "$who" in
  claude)
    if [ $# -gt 0 ]; then
      for f in "$@"; do shift; [ -e "$f" ] && set -- "$@" "--add-dir=$(dirname "$f")"; done
      set -- --tools Read "$@"
    else
      set -- --tools ""
    fi
    exec timeout 120 claude -p --model haiku "$@" --no-session-persistence \
      --append-system-prompt "Answer in the same language as the question, short and direct (6 lines max). No heavy markdown." "$q" </dev/null ;;
  codex)
    for f in "$@"; do shift; case "$f" in *.png|*.jpg|*.jpeg|*.webp|*.gif|*.PNG|*.JPG|*.JPEG) set -- "$@" -i "$f";; esac; done
    out="$(mktemp)"
    # `codex` from the PATH; fall back to the copy bundled with the desktop app
    codex_bin="$(command -v codex 2>/dev/null || true)"
    [ -z "$codex_bin" ] && [ -x "$HOME/.local/lib/chatgpt/resources/codex" ] && codex_bin="$HOME/.local/lib/chatgpt/resources/codex"
    [ -z "$codex_bin" ] && { echo "codex not found" >&2; exit 127; }
    timeout 150 "$codex_bin" exec --skip-git-repo-check --ephemeral -s read-only "$@" \
      --output-last-message "$out" "Answer only what is asked, in the same language as the question, short and direct (6 lines max). Question: $q" </dev/null >/dev/null 2>&1
    cat "$out"; rm -f "$out" ;;
  *) echo "who?" >&2; exit 2 ;;
esac
