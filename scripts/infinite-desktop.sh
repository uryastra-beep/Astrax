#!/usr/bin/env bash
sleep 3
SPEED=1.6

# expected path: ~/scripts/
# Get the directory this script lives in
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect keyboard - prioritizing real keyboards (no "mouse" in the name)
KBD_DEV=$(python3 -c "
import glob, os

# Words that indicate it is NOT a real keyboard
ignore_words = ['mouse', 'optical', 'system control', 'consumer control']
real_keyboard = None

for dev in sorted(glob.glob('/dev/input/event*')):
    try:
        with open('/sys/class/input/'+os.path.basename(dev)+'/device/name') as f:
            name = f.read().strip().lower()
        
        # If it has words to ignore, skip it
        if any(word in name for word in ignore_words):
            continue
            
        # Check that it's a keyboard
        if 'keyboard' in name or 'kbd' in name or 'gaming keyboard' in name:
            with open('/sys/class/input/'+os.path.basename(dev)+'/device/capabilities/ev') as f:
                caps = int(f.read().strip(), 16)
            if caps & 0x1:  # Has EV_KEY
                real_keyboard = dev
                break
    except:
        continue

# If no "clean" keyboard was found, look for any keyboard that isn't the mouse's
if not real_keyboard:
    for dev in sorted(glob.glob('/dev/input/event*')):
        try:
            with open('/sys/class/input/'+os.path.basename(dev)+'/device/name') as f:
                name = f.read().strip().lower()
            
            # Explicitly exclude the mouse's keyboard interface
            if 'optical mouse keyboard' in name:
                continue
                
            if 'keyboard' in name or 'kbd' in name:
                with open('/sys/class/input/'+os.path.basename(dev)+'/device/capabilities/ev') as f:
                    caps = int(f.read().strip(), 16)
                if caps & 0x1:
                    real_keyboard = dev
                    break
        except:
            continue

print(real_keyboard if real_keyboard else '')
")

# Detect mouse - look for the device that is specifically a mouse
MOUSE_DEV=$(python3 -c "
import glob, os
mouse_found = None
for dev in sorted(glob.glob('/dev/input/event*')):
    try:
        # Check it has movement capabilities
        with open('/sys/class/input/'+os.path.basename(dev)+'/device/capabilities/rel') as f:
            caps = int(f.read().strip(), 16)
        if caps & 0b11:
            with open('/sys/class/input/'+os.path.basename(dev)+'/device/name') as f:
                name = f.read().strip().lower()
            
            # Prefer the one that says "mouse" and doesn't have "keyboard"
            if 'mouse' in name and 'keyboard' not in name:
                print(dev)
                break
            elif 'optical' in name and not mouse_found:
                mouse_found = dev
    except:
        continue

if not mouse_found:
    print('')
")

# Check detection
if [ -z "$KBD_DEV" ]; then
    echo "❌ Error: couldn't detect the keyboard" >&2
    echo "Keyboard devices found:" >&2
    for dev in /dev/input/event*; do
        name=$(cat "/sys/class/input/$(basename $dev)/device/name" 2>/dev/null)
        if echo "$name" | grep -qi "keyboard\|kbd"; then
            echo "  $dev: $name" >&2
        fi
    done
    exit 1
fi

if [ -z "$MOUSE_DEV" ]; then
    echo "Error: couldn't detect the mouse" >&2
    echo "Mouse devices found:" >&2
    for dev in /dev/input/event*; do
        name=$(cat "/sys/class/input/$(basename $dev)/device/name" 2>/dev/null)
        if echo "$name" | grep -qi "mouse\|optical"; then
            echo "  $dev: $name" >&2
        fi
    done
    exit 1
fi

echo "Detected: keyboard=$KBD_DEV mouse=$MOUSE_DEV"

# Safety check
if [ "$KBD_DEV" = "$MOUSE_DEV" ]; then
    echo "ERROR: keyboard and mouse are the same device" >&2
    exit 1
fi

exec python3 "$SCRIPT_DIR/infinite_desktop_core.py" "$KBD_DEV" "$MOUSE_DEV" "$SPEED"
