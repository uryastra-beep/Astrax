from pathlib import Path
import json, os, shutil
mem = dict(line.split(":", 1) for line in Path("/proc/meminfo").read_text().splitlines())
total = int(mem["MemTotal"].split()[0]); available = int(mem["MemAvailable"].split()[0])
disk = shutil.disk_usage(Path.home())
print(json.dumps({"uptime": float(Path("/proc/uptime").read_text().split()[0]),
    "memory": f"{(total-available)/1048576:.1f} / {total/1048576:.1f} GiB",
    "load": f"{os.getloadavg()[0]:.2f}", "storage": f"{disk.free/1073741824:.0f} GiB free / {disk.total/1073741824:.0f} GiB"}))
