#!/usr/bin/env python3
"""cfgset.py <dotted.path> <json-value>  -- merge one value into Serpantinum's settings.json (atomic write)."""
import json, os, sys, tempfile

path = os.path.expanduser("~/.config/serpantinum/settings.json")
keys = sys.argv[1].split(".")
value = json.loads(sys.argv[2])

with open(path, encoding="utf-8") as f:
    data = json.load(f)
node = data
for k in keys[:-1]:
    if not isinstance(node.get(k), dict):
        node[k] = {}
    node = node[k]
node[keys[-1]] = value

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings-", suffix=".tmp")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)

if keys[0] == "liquidGlass":
    import subprocess
    subprocess.Popen(["python3", os.path.expanduser("~/.config/astrax-common/lg/lg-apply.py")],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
