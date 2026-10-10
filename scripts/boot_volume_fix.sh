#!/usr/bin/env bash
# WirePlumber correctly saves the internal speaker volume (0% in
# default-routes and in the raw ALSA mixer of asound.state), but doesn't
# apply it to the audio node at boot -- it falls back to its internal default
# (~0.40, shows as 41% in wpctl) no matter what it was
# left at. If the default sink at boot is the laptop's internal
# speaker, we force it to 0%. If it's bluetooth or another external output, we
# don't touch anything (it starts with its own saved volume, which does work).

for i in $(seq 1 20); do
    pactl info >/dev/null 2>&1 && break
    sleep 0.5
done

default_sink=$(pactl get-default-sink 2>/dev/null)

case "$default_sink" in
    alsa_output.pci-0000_03_00.6.*)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 0%
        ;;
esac
