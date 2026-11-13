#!/usr/bin/env python3
"""Weather for the hub's Widgets tab: {"temp", "code", "day", "max", "min", "city"} as one JSON line.

Same location rules as weather.py (island.weatherLat / weatherLon in Serpantinum's settings.json, else
the public-IP lookup cached in ~/.cache/astrax-island-weather-loc.json). The city name comes from
island.weatherCity when set, else from that same lookup (cached in ~/.cache/astrax-island-weather-city.json).
Open-Meteo, free, no key. Prints {} on any failure.
"""
import json, os, urllib.request

HOME = os.path.expanduser("~")
LOC = HOME + "/.cache/astrax-island-weather-loc.json"
CITY = HOME + "/.cache/astrax-island-weather-city.json"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "astrax-island"})
    with urllib.request.urlopen(req, timeout=6) as r:
        return json.load(r)


def main():
    cfg = {}
    try:
        cfg = json.load(open(HOME + "/.config/serpantinum/settings.json")).get("island", {})
    except Exception:
        pass
    lat, lon = cfg.get("weatherLat"), cfg.get("weatherLon")
    city = cfg.get("weatherCity") or ""
    if lat is None or lon is None:
        try:
            c = json.load(open(LOC))
            lat, lon = c["lat"], c["lon"]
        except Exception:
            j = get("https://ipapi.co/json/")
            lat, lon = j["latitude"], j["longitude"]
            json.dump({"lat": lat, "lon": lon}, open(LOC, "w"))
            if j.get("city"):
                json.dump({"city": j["city"]}, open(CITY, "w"))
    if not city:
        try:
            city = json.load(open(CITY)).get("city", "")
        except Exception:
            try:
                j = get("https://ipapi.co/json/")
                city = j.get("city", "")
                if city:
                    json.dump({"city": city}, open(CITY, "w"))
            except Exception:
                city = ""
    w = get("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
            "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min"
            "&timezone=auto&forecast_days=1" % (lat, lon))
    cur, daily = w["current"], w["daily"]
    print(json.dumps({
        "temp": round(cur["temperature_2m"]),
        "code": cur["weather_code"],
        "day": bool(cur["is_day"]),
        "max": round(daily["temperature_2m_max"][0]),
        "min": round(daily["temperature_2m_min"][0]),
        "city": city,
    }))


try:
    main()
except Exception:
    print("{}")
