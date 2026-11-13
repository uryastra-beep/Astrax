#!/usr/bin/env python3
"""Privacy + VPN state for the island's idle strip. Prints one JSON line when something changes.

mic    an app is recording from a real microphone (not a sink monitor, not Bluetooth's internal capture)
cam    an app is reading the camera
screen a screen-cast stream is running
vpn    a tunnel interface (wg*, tun*, proton*, mullvad*) is up
"""
import json, os, re, subprocess, sys, time

def dump():
    try:
        return json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=4).stdout)
    except Exception:
        return []

def state():
    objs = dump()
    nodes = {o["id"]: o["info"]["props"] for o in objs if o.get("type") == "PipeWire:Interface:Node" and "info" in o}
    mic = cam = screen = False
    for o in objs:
        if o.get("type") != "PipeWire:Interface:Link":
            continue
        info = o.get("info", {})
        if info.get("state") != "active":
            continue
        src = nodes.get(info.get("output-node-id"), {})
        dst = nodes.get(info.get("input-node-id"), {})
        if src.get("media.class") == "Audio/Source" and dst.get("media.class") == "Stream/Input/Audio":
            mic = True
        elif src.get("media.class") == "Video/Source" and dst.get("media.class") == "Stream/Input/Video":
            cam = True
    for p in nodes.values():
        if p.get("media.class") == "Stream/Output/Video":
            screen = True
    vpn = False
    try:
        for name in os.listdir("/sys/class/net"):
            if re.match(r"^(wg|tun|ppp|proton|mullvad)", name):
                with open(f"/sys/class/net/{name}/operstate") as f:
                    if f.read().strip() in ("up", "unknown"):
                        vpn = True
    except Exception:
        pass
    return {"mic": mic, "cam": cam, "screen": screen, "vpn": vpn}

last = None
while True:
    cur = state()
    if cur != last:
        print(json.dumps(cur), flush=True)
        last = cur
    time.sleep(2)
