#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"
qs_ensure_cache "lock"

# outro before locking (custom, see ~/scripts/outro-cover.sh). It stays covered
# under the lock; the intro removes it on unlock.
[ -e "$QS_RUN_DIR/lock/locked" ] || bash ~/scripts/outro-cover.sh

case "$1" in
    --static) action="activateStatic" ;;
    --reauth) action="restartAuth" ;;
    *) action="activate" ;;
esac

quickshell -p $MAIN_QML ipc call lock "$action"
