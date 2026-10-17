#!/usr/bin/env bash
# cursor-style: changes the cursor style (Astrax's reactive cursor, see README).
#   cursor-style normal        the classic white cursor (Bibata-Modern-Ice), no glow, no animations
#   cursor-style astrax        Astrax's cursor (arrow + colored glow + animations)
#   cursor-style highcontrast  Astrax's cursor with a high-contrast palette (Okabe-Ito based)
#   cursor-style get           print the current style
#   cursor-style apply         re-apply the current style's theme (run at login)
#   cursor-style anims         print the animations (name=0|1)
#   cursor-style anim <trail|click|scroll|colorfade|roulette|speed|rotate> <0|1>   turn one on/off
# The dynamic-cursors plugin reads ~/.config/cursor-style live; the theme is changed with
# hyprctl setcursor and saved in the usual env/GTK files (when they exist) for the next login.
set -u
STATE="$HOME/.config/cursor-style"

get() { local v; v=$(head -n1 "$STATE" 2>/dev/null | tr -d '[:space:]'); case "$v" in normal) echo normal ;; highcontrast) echo highcontrast ;; *) echo astrax ;; esac; }

[ "${1:-get}" = "get" ] && { get; exit 0; }

ANIMS="$HOME/.config/cursor-anims"
KEYS="trail click scroll colorfade roulette speed rotate"
ensure_anims() { for k in $KEYS; do grep -q "^$k=" "$ANIMS" 2>/dev/null || echo "$k=1" >> "$ANIMS"; done; }

if [ "$1" = "anims" ]; then ensure_anims; for k in $KEYS; do grep "^$k=" "$ANIMS"; done; exit 0; fi
if [ "$1" = "anim" ]; then
  name="${2:-}"; val="${3:-}"
  case " $KEYS " in *" $name "*) ;; *) echo "unknown animation: $name" >&2; exit 1 ;; esac
  case "$val" in 0|1) ;; *) echo "invalid value (0|1)" >&2; exit 1 ;; esac
  ensure_anims
  sed -i -E "s/^$name=.*/$name=$val/" "$ANIMS"
  echo "$name=$val"; exit 0
fi

style="$1"
[ "$style" = "apply" ] && style="$(get)"
case "$style" in
  normal)             theme="Bibata-Modern-Ice"; size=24 ;;
  astrax|highcontrast) theme="Bibata-ArrowBare"; size=48 ;;
  *) echo "usage: cursor-style [normal|astrax|highcontrast|get|apply|anims|anim]" >&2; exit 1 ;;
esac

echo "$style" > "$STATE"

# Theme for the next login (files outside ~/.config/hypr, so Hyprland doesn't reload)
sed -i -E "s/Bibata-(ArrowBare|Arrow|Modern-Ice)/$theme/g" \
  "$HOME/.config/uwsm/env" "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" \
  "$HOME/.config/xsettingsd/xsettingsd.conf" "$HOME/.icons/default/index.theme" 2>/dev/null
sed -i -E "s/^(export (HYPRCURSOR|XCURSOR)_SIZE=).*/\1$size/" "$HOME/.config/uwsm/env" 2>/dev/null
sed -i -E "s/^(gtk-cursor-theme-size=).*/\1$size/" "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null

# Theme and size live
hyprctl setcursor "$theme" "$size" >/dev/null 2>&1

echo "$style"
