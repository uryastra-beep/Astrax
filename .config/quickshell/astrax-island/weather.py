#!/usr/bin/env python3
"""Current weather for the idle strip: {"temp": 27, "code": 3, "day": true}.

Open-Meteo (free, no key). Location: island.weatherLat / island.weatherLon in Serpantinum's settings.json,
otherwise looked up once from the public IP and cached in ~/.cache/astrax-island-weather-loc.json.
"""
import json, os, urllib.request

HOME = os.path.expanduser("~")
CACHE = HOME + "/.cache/astrax-island-weather-loc.json"

def get(url):
    with urllib.request.urlopen(url, timeout=8) as r:
        return json.load(r)

def location():
    try:
        cfg = json.load(open(HOME + "/.config/serpantinum/settings.json")).get("island", {})
        if cfg.get("weatherLat") is not None and cfg.get("weatherLon") is not None:
            return float(cfg["weatherLat"]), float(cfg["weatherLon"])
    except Exception:
        pass
    try:
        c = json.load(open(CACHE))
        return c["lat"], c["lon"]
    except Exception:
        pass
    j = get("https://ipapi.co/json/")
    lat, lon = float(j["latitude"]), float(j["longitude"])
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump({"lat": lat, "lon": lon}, open(CACHE, "w"))
    return lat, lon

try:
    lat, lon = location()
    j = get(f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,weather_code,is_day")
    c = j["current"]
    print(json.dumps({"temp": round(c["temperature_2m"]), "code": int(c["weather_code"]), "day": bool(c["is_day"])}))
except Exception:
    pass
