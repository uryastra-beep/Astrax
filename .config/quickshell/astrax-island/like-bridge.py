#!/usr/bin/env python3
"""Like bridge between Spotify (the astrax-like.js Spicetify extension) and the island.

Daemon:   like-bridge.py            serves 127.0.0.1:38917 and prints one JSON line per change:
                                    {"connected": bool, "liked": bool, "uri": "...", "title": "..."}
Command:  like-bridge.py toggle     asks the daemon to like / unlike the song that is playing

The extension POSTs /state when the song or its heart changes and polls /cmd for a pending toggle.
"""
import json, sys, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 38917
state = {"liked": False, "uri": "", "title": "", "seen": 0.0}
pending = {"toggle": False}
lock = threading.Lock()

def snapshot():
    with lock:
        return {"connected": time.time() - state["seen"] < 15, "liked": state["liked"], "uri": state["uri"], "title": state["title"]}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code=200, body=b"{}"):
        self.send_response(code)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_OPTIONS(self): self._send(204, b"")
    def do_GET(self):
        if self.path.startswith("/cmd"):
            with lock:
                t = pending["toggle"]; pending["toggle"] = False
                state["seen"] = time.time()
            self._send(200, json.dumps({"toggle": t}).encode())
        else:
            self._send(200, json.dumps(snapshot()).encode())
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        if self.path.startswith("/state"):
            try: j = json.loads(raw)
            except Exception: j = {}
            with lock:
                state.update(liked=bool(j.get("liked")), uri=str(j.get("uri", "")), title=str(j.get("title", "")), seen=time.time())
        elif self.path.startswith("/toggle"):
            with lock:
                pending["toggle"] = True
                state["liked"] = not state["liked"]   # optimistic, the extension confirms
        self._send()

def serve():
    # the previous daemon can still hold the port for a moment after a shell reload: keep trying
    while True:
        try:
            ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
        except OSError:
            time.sleep(1)

if len(sys.argv) > 1 and sys.argv[1] == "toggle":
    try:
        urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{PORT}/toggle", data=b"{}", method="POST"), timeout=2)
    except Exception:
        pass
    sys.exit(0)

threading.Thread(target=serve, daemon=True).start()
last = None
while True:
    cur = snapshot()
    if cur != last:
        print(json.dumps(cur), flush=True)
        last = cur
    time.sleep(0.4)
