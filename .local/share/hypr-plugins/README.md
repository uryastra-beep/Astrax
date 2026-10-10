# dynamic-cursors-trail.so (optional)

UNOFFICIAL build of hypr-dynamic-cursors with the cursor trail effect from
PR https://github.com/VirtCode/hypr-dynamic-cursors/pull/161.

It isn't upstream: the PR is OPEN, unmerged, with changes requested by the
maintainer and a known bug (artifacts when moving fast against the side edges
of the monitor).

The PR branch doesn't build on Hyprland 0.56.2 (it includes
<hyprland/src/ipc/s2/S2.hpp>, an API newer than that version). So the build is
the trail diff (e9056fd..3081450) applied on top of the plugin commit that the
plugin's hyprpm.toml pins for your Hyprland version.

It's only used live, with "mouse trail on" / "mouse trail off". It's never
loaded from the config: plugins.lua always loads the hyprpm plugin.

Build it (and rebuild it after every Hyprland update):

    ~/.local/share/hypr-plugins/build-trail.sh

Needs git, make and a C++ toolchain (base-devel), like hyprpm itself.
