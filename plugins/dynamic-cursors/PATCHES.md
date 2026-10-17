# Astrax patches to hypr-dynamic-cursors

This is a fork of [virtcode/hypr-dynamic-cursors](https://github.com/virtcode/hypr-dynamic-cursors)
(commit `5a22428`), BSD-3-Clause like upstream (see `LICENSE.md`). Upstream's `README.md` is kept as is.
Astrax's changes:

- **Glow by cursor shape** (`src/halo.hpp`): the plugin draws a colored halo around a plain arrow
  (the `Bibata-ArrowBare` theme), colored by what the cursor means:

  | Glow | Cursor type |
  |---|---|
  | blue | clickable (links, buttons) |
  | white | text |
  | light blue | draggable (grab, move, drag & drop) |
  | orange | crosshair / cell |
  | pink | resize |
  | green | copy |
  | red | forbidden / not allowed |
  | half blue, half white | alias (link or shortcut) |
  | every color, spinning | loading |
  | purple | anything else (default arrow, help, menus, zoom) |

- **Three styles**, read live from `~/.config/cursor-style` (set with `cursor-style`): `normal` (classic
  white Bibata-Modern-Ice, no glow and no animations, apps may set their own cursor), `astrax` (the
  palette above) and `highcontrast` (another palette, based on Okabe-Ito).
- **Animations**, each one switchable in `~/.config/cursor-anims` (`name=0|1`): a continuous light trail,
  shrink on click, stretch toward the scroll direction (arrow and light) with a spring back, a 320 ms
  glow color fade, stretch by speed and rotation with movement.
- Glow and arrow are clipped to the monitor holding the pointer.
- **Cursor lock** (`src/main.cpp`): apps can't set their own cursor image, except a hidden cursor and
  the window classes listed in `~/.config/cursor-allow.txt` (prefix, case-insensitive).
- The `Makefile` tracks headers (`-MMD -MP`): a stale object file once corrupted the heap.

**Limitation:** color is the only cue that tells the cursor types apart. Making the colors
configurable, or adding different shapes per type, is future work.

## Build

```bash
make            # -> out/dynamic-cursors.so
```

Astrax's installer builds it with `cursor-plugin build`. **Rebuild it after every Hyprland update**
(`cursor-plugin check` compares the hash of the Hyprland headers it was built against). **Never
hot-reload the plugin** (`hyprctl plugin load/unload`, or the Makefile's `load`/`unload` targets): that
can crash Hyprland. Log out and back in instead.
