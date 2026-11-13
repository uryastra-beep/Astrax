#!/usr/bin/python3 -I
"""AI monitor for the Dynamic Island: state and usage of Claude and Codex.

AiPanel.qml starts it ONLY while the panel is open; it prints one JSON line per second.
Everything is local, no network:
  Claude : ~/.claude/sessions/*.json (live sessions + name) + $XDG_RUNTIME_DIR/astrax-pet/<id>.json
           (state written by an optional astrax-pet-hook) + today's transcripts (tokens).
  Codex  : ~/.codex/sessions/**/rollout-*.jsonl (task_started/complete, approvals, token_count with
           the 5 h and weekly limits) + ~/.codex/session_index.jsonl (names).
"""
import glob, json, os, re, sys, time

HOME = os.path.expanduser("~")
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
NOW = time.time

CREATE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")
ASK = ("approval_request", "request_user_input", "request_permissions", "elicitation_request")
CODEX_LIVE = 10 * 60          # a rollout touched more recently than this counts as an active session
LIST_IDLE = 45 * 60           # idle sessions are listed up to this age
STALE_WORK = 20 * 60          # "working" with no events for this long => treated as dead


def jload(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def alive(pid):
    return os.path.isdir("/proc/%s" % pid)


# ------------------------------------------------------------------ Claude
def claude_label(st):
    ev, tool = st.get("ev", ""), st.get("tool", "")
    if st.get("state") == "attention":
        return "attention", "Needs input"
    if st.get("state") == "sleeping":
        return "limit", "Limit reached"
    if st.get("state") == "working":
        if ev == "PreToolUse" and tool in CREATE_TOOLS:
            return "creating", "Creating…"
        if ev == "PreToolUse":
            return "working", "Working…"
        # UserPromptSubmit / PostToolUse / SubagentStart: the model is deciding
        if ev in ("UserPromptSubmit", "PostToolUse", "PostToolUseFailure"):
            return "thinking", "Thinking…"
        return "working", "Working…"
    return "idle", "Done"


def claude_sessions():
    out = []
    for p in glob.glob(os.path.join(HOME, ".claude/sessions/*.json")):
        d = jload(p)
        if not d or not d.get("pid") or not alive(d["pid"]):
            continue
        if str(d.get("cwd", "")).startswith("/tmp"):       # auxiliary SDK sessions (tmp-xx)
            continue
        sid = d.get("sessionId", "")
        st = jload(os.path.join(RUN, "astrax-pet", sid + ".json")) or {}
        ts = st.get("ts") or (d.get("statusUpdatedAt") or d.get("updatedAt") or 0) / 1000.0
        if not st:
            st = {"state": "working" if d.get("status") == "busy" else "idle", "ev": "", "ts": ts}
        if st.get("state") == "working" and NOW() - ts > STALE_WORK:
            st = dict(st, state="idle")
        kind, label = claude_label(st)
        out.append({"id": sid, "name": d.get("name") or os.path.basename(d.get("cwd", "")) or "Session",
                    "kind": kind, "label": label, "ts": ts})
    return out


_cpos, _ctoks = {}, {"day": "", "in": 0, "out": 0, "msgs": 0}


def claude_tokens():
    """Sum today's tokens and messages, reading only what is new in the transcripts touched today."""
    day = time.strftime("%Y-%m-%d")
    t0 = time.mktime(time.strptime(day, "%Y-%m-%d"))
    if _ctoks["day"] != day:
        _ctoks.update(day=day, **{"in": 0, "out": 0, "msgs": 0})
        _cpos.clear()
    for p in glob.glob(os.path.join(HOME, ".claude/projects/*/*.jsonl")):
        try:
            st = os.stat(p)
        except OSError:
            continue
        if st.st_mtime < t0:
            continue
        pos = _cpos.get(p, 0)
        if st.st_size <= pos:
            continue
        try:
            with open(p, "rb") as f:
                f.seek(pos)
                chunk = f.read()
        except OSError:
            continue
        cut = chunk.rfind(b"\n")
        if cut < 0:
            continue
        _cpos[p] = pos + cut + 1
        for line in chunk[:cut].split(b"\n"):
            if b'"usage"' not in line or b'"assistant"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if not str(d.get("timestamp", "")).startswith(day):
                # the timestamp is UTC; compare as epoch so it doesn't break at night
                try:
                    t = time.mktime(time.strptime(d["timestamp"][:19], "%Y-%m-%dT%H:%M:%S")) - time.timezone
                except Exception:
                    continue
                if t < t0:
                    continue
            u = (d.get("message") or {}).get("usage") or {}
            _ctoks["in"] += int(u.get("input_tokens", 0)) + int(u.get("cache_creation_input_tokens", 0))
            _ctoks["out"] += int(u.get("output_tokens", 0))
            _ctoks["msgs"] += 1
    return {"in": _ctoks["in"], "out": _ctoks["out"], "msgs": _ctoks["msgs"]}


# ------------------------------------------------------------------ Codex
_names = {"mt": 0, "v": {}}


def codex_names():
    p = os.path.join(HOME, ".codex/session_index.jsonl")
    try:
        mt = os.stat(p).st_mtime
    except OSError:
        return _names["v"]
    if mt != _names["mt"]:
        v = {}
        try:
            with open(p) as f:
                for l in f:
                    try:
                        d = json.loads(l)
                        v[d["id"]] = d.get("thread_name") or ""
                    except Exception:
                        pass
        except OSError:
            pass
        _names.update(mt=mt, v=v)
    return _names["v"]


def tail(path, n=300_000):
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - n))
        data = f.read().decode("utf-8", "ignore")
    lines = data.splitlines()
    return lines[1:] if size > n else lines


def codex_scan(path):
    """Estado de un rollout leyendo su cola: (kind, label, rate_limits|None, total_tokens)."""
    started = done = -1
    last = ("", "")
    rl, total = None, 0
    for i, l in enumerate(tail(path)):
        m = re.search(r'"payload":\{"type":"([a-z_]+)"', l)
        if not m:
            continue
        t = m.group(1)
        if t == "task_started":
            started = i
        elif t in ("task_complete", "turn_aborted"):
            done = i
        elif t == "token_count":
            try:
                p = json.loads(l)["payload"]
                if p.get("rate_limits"):
                    rl = p["rate_limits"]
                total = ((p.get("info") or {}).get("total_token_usage") or {}).get("total_tokens", total)
            except Exception:
                pass
        if t not in ("token_count", "thread_settings_applied", "world_state"):
            name = ""
            if t in ("custom_tool_call", "function_call"):
                n = re.search(r'"name":"([^"]+)"', l)
                name = n.group(1) if n else ""
            last = (t, name)
    t, name = last
    if t in ASK:
        return "attention", "Needs input", rl, total
    if started > done:
        if t == "reasoning":
            return "thinking", "Thinking…", rl, total
        if t in ("custom_tool_call", "function_call"):
            if "patch" in name or "write" in name:
                return "creating", "Creating…", rl, total
            return "working", "Working…", rl, total
        return "working", "Working…", rl, total
    return "idle", "Done", rl, total


def codex_state():
    names = codex_names()
    now = NOW()
    files = glob.glob(os.path.join(HOME, ".codex/sessions/*/*/*/rollout-*.jsonl"))
    files = sorted(files, key=os.path.getmtime, reverse=True)[:12]
    sessions, usage, tokens_today = [], None, 0
    t0 = time.mktime(time.strptime(time.strftime("%Y-%m-%d"), "%Y-%m-%d"))
    for i, p in enumerate(files):
        try:
            mt = os.path.getmtime(p)
        except OSError:
            continue
        age = now - mt
        if i > 0 and age > LIST_IDLE:
            break
        kind, label, rl, total = codex_scan(p)
        if rl and not usage:
            usage = rl
        if age > CODEX_LIVE and kind != "idle":
            kind, label = "idle", "Done"          # rollout abandonado a medias
        if age > LIST_IDLE:
            continue
        m = re.search(r"rollout-.*?-([0-9a-f]{8}-[0-9a-f-]{27})\.jsonl$", p)
        tid = m.group(1) if m else ""
        sessions.append({"id": tid, "name": names.get(tid) or "Codex session", "kind": kind,
                         "label": label, "ts": mt})
        if mt >= t0:
            tokens_today += total
    return sessions, usage, tokens_today


def rate(w):
    if not w:
        return None
    ra = w.get("resets_at") or 0
    if ra and ra < NOW():          # window already reset: the saved % is stale
        return {"pct": 0, "reset": 0, "stale": True, "mins": w.get("window_minutes")}
    return {"pct": w.get("used_percent"), "reset": ra, "stale": False, "mins": w.get("window_minutes")}


# ------------------------------------------------------------------ resumen
PRIO = {"attention": 5, "limit": 4, "creating": 3, "thinking": 3, "working": 3, "idle": 1}
LAB = {"attention": "Needs input", "limit": "Limit reached", "creating": "Creating…",
       "thinking": "Thinking…", "working": "Working…", "idle": "Done"}


def summary(sessions):
    if not sessions:
        return {"kind": "none", "label": "No sessions"}
    sessions.sort(key=lambda s: (-PRIO.get(s["kind"], 0), -s["ts"]))
    top = sessions[0]
    return {"kind": top["kind"], "label": top["label"] or LAB.get(top["kind"], "")}


def build():
    cs = claude_sessions()
    xs, usage, xtok = codex_state()
    ct = claude_tokens()
    cs = sorted(cs, key=lambda s: (-PRIO.get(s["kind"], 0), -s["ts"]))
    xs = sorted(xs, key=lambda s: (-PRIO.get(s["kind"], 0), -s["ts"]))
    return {
        "ts": NOW(),
        "claude": {**summary(list(cs)), "sessions": cs[:6], "count": len(cs), "tokens": ct},
        "codex": {**summary(list(xs)), "sessions": xs[:6], "count": len(xs), "tokensToday": xtok,
                  "five": rate((usage or {}).get("primary")), "week": rate((usage or {}).get("secondary")),
                  "plan": (usage or {}).get("plan_type")},
    }


def main():
    once = "--once" in sys.argv
    last = None
    while True:
        try:
            snap = build()
        except Exception as e:                          # never dies: sends the error and keeps going
            snap = {"error": str(e)}
        s = json.dumps(snap, ensure_ascii=False)
        key = re.sub(r'"ts": [0-9.]+,?', "", s)
        if key != last:
            sys.stdout.write(s + "\n")
            sys.stdout.flush()
            last = key
        if once:
            return
        time.sleep(1)


if __name__ == "__main__":
    main()
