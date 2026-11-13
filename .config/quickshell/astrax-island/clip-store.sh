#!/bin/sh
# wl-paste --watch target: keep the clipboard in cliphist, except secrets flagged by password managers.
# wl-paste --watch runs handlers one at a time, so a source that never answers must not block the rest: hence the timeouts.
case "$(timeout 2 wl-paste --list-types 2>/dev/null)" in *x-kde-passwordManagerHint*) exit 0 ;; esac
exec timeout 5 cliphist store
