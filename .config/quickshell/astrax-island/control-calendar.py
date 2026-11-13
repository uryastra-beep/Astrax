#!/usr/bin/env python3
"""Next reminders for the island control panel, from a Google Calendar *secret iCal address* (no OAuth).

Config: ~/.config/astrax-island/control.json  {"calendarIcs": "https://calendar.google.com/calendar/ical/.../basic.ics"}
Prints one JSON object: {"ok": bool, "error": str, "events": [{"title", "ts", "allDay"}]} (next 4, cached 5 min).
Supports DAILY/WEEKLY/MONTHLY/YEARLY RRULE with INTERVAL/COUNT/UNTIL/BYDAY (enough for typical reminders).
"""
import json, os, re, sys, time, urllib.request
from datetime import datetime, timedelta, timezone, date

HOME = os.path.expanduser("~")
CFG = HOME + "/.config/astrax-island/control.json"
CACHE = HOME + "/.cache/astrax-island-calendar.ics"
LOCAL = datetime.now().astimezone().tzinfo
DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

def out(o):
    print(json.dumps(o)); sys.exit(0)

def load_ics(url):
    if os.path.exists(CACHE) and time.time() - os.path.getmtime(CACHE) < 300:
        return open(CACHE, encoding="utf-8").read()
    with urllib.request.urlopen(url, timeout=10) as r:
        txt = r.read().decode("utf-8", "replace")
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    open(CACHE, "w", encoding="utf-8").write(txt)
    return txt

def unfold(txt):
    return re.sub(r"\r?\n[ \t]", "", txt).splitlines()

def parse_dt(val, params):
    v = val.strip()
    if "VALUE=DATE" in params or len(v) == 8:
        d = datetime.strptime(v[:8], "%Y%m%d")
        return d.replace(tzinfo=LOCAL), True
    if v.endswith("Z"):
        return datetime.strptime(v, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc).astimezone(LOCAL), False
    return datetime.strptime(v[:15], "%Y%m%dT%H%M%S").replace(tzinfo=LOCAL), False

def events(lines):
    cur = None
    for ln in lines:
        if ln == "BEGIN:VEVENT": cur = {"ex": []}
        elif ln == "END:VEVENT":
            if cur and "start" in cur: yield cur
            cur = None
        elif cur is not None and ":" in ln:
            head, val = ln.split(":", 1)
            name, *params = head.split(";")
            if name == "SUMMARY": cur["title"] = val.replace("\\,", ",").replace("\\n", " ")
            elif name == "DTSTART": cur["start"], cur["allDay"] = parse_dt(val, params)
            elif name == "RRULE": cur["rrule"] = dict(p.split("=", 1) for p in val.split(";") if "=" in p)
            elif name == "EXDATE":
                for v in val.split(","):
                    try: cur["ex"].append(parse_dt(v, params)[0])
                    except Exception: pass
            elif name == "STATUS" and val == "CANCELLED": cur = None

def occurrences(ev, now, horizon):
    st, rr = ev["start"], ev.get("rrule")
    if not rr:
        yield st; return
    freq, inter = rr.get("FREQ"), int(rr.get("INTERVAL", "1"))
    until = None
    if "UNTIL" in rr:
        try: until = parse_dt(rr["UNTIL"], [])[0]
        except Exception: pass
    count = int(rr["COUNT"]) if "COUNT" in rr else None
    byday = [d[-2:] for d in rr.get("BYDAY", "").split(",") if d]
    n, cur, guard = 0, st, 0
    while cur <= horizon and guard < 5000:
        guard += 1
        cands = [cur]
        if freq == "WEEKLY" and byday:
            mon = cur - timedelta(days=cur.weekday())
            cands = [mon + timedelta(days=DAYS.index(d)) for d in byday if d in DAYS]
            cands = sorted(c.replace(hour=st.hour, minute=st.minute) for c in cands)
        for c in cands:
            if c < st or c > horizon: continue
            if until and c > until: return
            n += 1
            if count and n > count: return
            yield c
        if freq == "DAILY": cur += timedelta(days=inter)
        elif freq == "WEEKLY": cur += timedelta(weeks=inter)
        elif freq == "MONTHLY":
            m = cur.month - 1 + inter
            try: cur = cur.replace(year=cur.year + m // 12, month=m % 12 + 1)
            except ValueError: cur = cur.replace(year=cur.year + m // 12, month=m % 12 + 1, day=28)
        elif freq == "YEARLY":
            try: cur = cur.replace(year=cur.year + inter)
            except ValueError: cur = cur.replace(year=cur.year + inter, day=28)
        else: return

try: url = json.load(open(CFG)).get("calendarIcs", "")
except Exception: url = ""
if not url: out({"ok": False, "error": "no-config", "events": []})
try:
    lines = unfold(load_ics(url))
    now = datetime.now().astimezone()
    start_of_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    horizon = now + timedelta(days=60)
    res = []
    for ev in events(lines):
        for o in occurrences(ev, now, horizon):
            if o in ev["ex"]: continue
            ok = o >= start_of_today if ev["allDay"] else o >= now - timedelta(minutes=10)
            if ok: res.append({"title": ev.get("title", "(no title)"), "ts": int(o.timestamp()), "allDay": ev["allDay"]})
    res.sort(key=lambda e: e["ts"])
    out({"ok": True, "error": "", "events": res[:4]})
except Exception as e:
    out({"ok": False, "error": str(e)[:80], "events": []})
