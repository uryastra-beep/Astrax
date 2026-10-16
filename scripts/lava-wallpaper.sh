#!/usr/bin/env bash
# lava-wallpaper [on|off|toggle|status] — WORT, the lava wallpaper (see README)
PAT='^quickshell -c lava-wallpaper'
case "${1:-on}" in
  on) pgrep -f "$PAT" >/dev/null || { pkill -f '^quickshell -c glass-wallpaper'; setsid -f quickshell -c lava-wallpaper >/dev/null 2>&1; } ;;
  off) pkill -f "$PAT" ;;
  toggle) if pgrep -f "$PAT" >/dev/null; then pkill -f "$PAT"; else setsid -f quickshell -c lava-wallpaper >/dev/null 2>&1; fi ;;
  status) pgrep -f "$PAT" >/dev/null && echo on || echo off ;;
esac
exit 0
