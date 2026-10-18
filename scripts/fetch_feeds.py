#!/usr/bin/env python3
"""Build Lookout's cached camera feeds (runs in GitHub Actions, standard library only).

Writes into OUT_DIR (default ./out):
  ga511.json    Georgia DOT cameras + live incidents   (needs secret GA511_KEY)
  webcams.json  Windy public webcams for the Southeast (needs secret WINDY_KEY)

The page reads these from the `feeds` branch, so no key ever has to be typed on
a phone and the browser never calls 511ga.org directly (which blocks it).
Missing keys are skipped quietly; a failed fetch keeps the previous file.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
REPO = os.environ.get("GITHUB_REPOSITORY", "christophergates88/lookout")
RAW = f"https://raw.githubusercontent.com/{REPO}/feeds/"
GA_KEY = os.environ.get("GA511_KEY", "").strip()
WINDY_KEY = os.environ.get("WINDY_KEY", "").strip()
UA = "Lookout feeds (github.com/%s)" % REPO

# Centers for Windy coverage: Georgia first, then where he drives.
GRID = [
    (33.75, -84.39, "Atlanta"), (33.08, -83.23, "Milledgeville"), (32.84, -83.63, "Macon"),
    (33.95, -83.38, "Athens"), (33.47, -81.97, "Augusta"), (32.08, -81.10, "Savannah"),
    (32.46, -84.99, "Columbus"), (31.58, -84.16, "Albany"), (30.83, -83.28, "Valdosta"),
    (34.26, -85.16, "Rome"), (34.77, -84.97, "Dalton"), (34.30, -83.82, "Gainesville"),
    (31.15, -81.49, "Brunswick"), (33.57, -83.47, "Lake Oconee"),
    (35.05, -85.31, "Chattanooga"), (34.85, -82.40, "Greenville SC"), (35.23, -80.84, "Charlotte"),
    (33.52, -86.81, "Birmingham"), (32.37, -86.30, "Montgomery"),
    (30.33, -81.66, "Jacksonville"), (30.44, -84.28, "Tallahassee"), (29.21, -81.02, "Daytona"),
    (28.54, -81.38, "Orlando"), (27.95, -82.46, "Tampa"), (30.16, -85.66, "Panama City"),
    (30.39, -86.50, "Destin"), (26.12, -80.14, "Fort Lauderdale"),
]


def now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def get(url, headers=None, timeout=40):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def previous(name):
    try:
        return get(RAW + name + "?t=" + str(int(time.time())))
    except Exception:  # noqa: BLE001
        return None


def write(name, obj):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "w") as f:
        json.dump(obj, f, separators=(",", ":"))
    print(f"wrote {name}: {os.path.getsize(os.path.join(OUT, name))} bytes")


def r5(v):
    try:
        return round(float(v), 5)
    except (TypeError, ValueError):
        return None


# ------------------------------------------------------------------ GA 511
def ga511():
    prev = previous("ga511.json")
    if not GA_KEY:
        print("GA511_KEY not set; skipping Georgia DOT")
        write("ga511.json", prev or {"updated": None, "note": "no key yet", "cameras": [], "events": []})
        return
    base = "https://511ga.org/api/v2/get/"
    q = "?key=" + urllib.parse.quote(GA_KEY) + "&format=json"
    cams, events = None, None
    try:
        raw = get(base + "cameras" + q)
        cams = []
        for c in raw or []:
            lat, lon = r5(c.get("Latitude")), r5(c.get("Longitude"))
            if lat is None or lon is None:
                continue
            views = c.get("Views") or []
            v0 = views[0] if views else {}
            cams.append({
                "id": c.get("Id"), "name": c.get("Name") or c.get("Location") or c.get("Roadway") or "Camera",
                "road": c.get("Roadway") or "", "dir": c.get("Direction") or "", "lat": lat, "lon": lon,
                "url": v0.get("Url") or f"https://511ga.org/map/Cctv/{c.get('Id')}",
                "ok": "disabled" not in str(v0.get("Status") or "").lower(),
            })
    except Exception as e:  # noqa: BLE001
        print("GA cameras failed:", e)
    for path in ("event", "events"):
        try:
            raw = get(base + path + q)
            events = []
            for e in raw or []:
                lat, lon = r5(e.get("Latitude")), r5(e.get("Longitude"))
                if lat is None or lon is None:
                    continue
                events.append({
                    "type": e.get("EventType") or e.get("Type") or e.get("Category") or "Incident",
                    "sub": e.get("EventSubType") or "", "sev": e.get("Severity") or "",
                    "desc": (e.get("Description") or e.get("Headline") or e.get("Location") or "")[:160],
                    "road": e.get("RoadwayName") or e.get("Roadway") or "", "dir": e.get("DirectionOfTravel") or "",
                    "lat": lat, "lon": lon, "updated": e.get("LastUpdated") or e.get("Reported") or "",
                })
            break
        except Exception as e:  # noqa: BLE001
            print(f"GA {path} failed:", e)
    if cams is None and events is None:
        print("Georgia DOT unreachable; keeping previous file")
        write("ga511.json", prev or {"updated": None, "cameras": [], "events": []})
        return
    out = {
        "updated": now(),
        "cameras": cams if cams is not None else (prev or {}).get("cameras", []),
        "events": events if events is not None else (prev or {}).get("events", []),
    }
    write("ga511.json", out)


# ------------------------------------------------------------------- Windy
def windy():
    prev = previous("webcams.json")
    if not WINDY_KEY:
        print("WINDY_KEY not set; skipping Windy webcams")
        write("webcams.json", prev or {"updated": None, "note": "no key yet", "webcams": []})
        return
    # Webcam metadata changes slowly and the image URLs always show the latest frame,
    # so only rebuild every 6 hours; GA 511 incidents are what need the frequent runs.
    if prev and prev.get("updated"):
        try:
            age = (datetime.now(timezone.utc) - datetime.fromisoformat(prev["updated"])).total_seconds()
            if age < 6 * 3600 and prev.get("webcams"):
                print(f"webcams.json is {age/3600:.1f}h old; keeping it")
                write("webcams.json", prev)
                return
        except ValueError:
            pass
    seen, cams, requests = {}, [], 0
    for lat, lon, label in GRID:
        for offset in (0, 50):
            url = ("https://api.windy.com/webcams/api/v3/webcams?nearby=%.4f,%.4f,90&limit=50&offset=%d"
                   "&include=images,location,player,urls&lang=en" % (lat, lon, offset))
            try:
                j = get(url, {"x-windy-api-key": WINDY_KEY})
                requests += 1
            except urllib.error.HTTPError as e:
                print(f"{label} offset {offset}: HTTP {e.code}")
                if e.code == 429:
                    time.sleep(30)
                    try:
                        j = get(url, {"x-windy-api-key": WINDY_KEY})
                    except Exception:  # noqa: BLE001
                        print("rate limited twice; stopping with what we have")
                        j = None
                        break
                else:
                    j = None
                    break
            except Exception as e:  # noqa: BLE001
                print(f"{label}: {e}")
                j = None
                break
            if not j:
                break
            for w in j.get("webcams") or []:
                wid = w.get("webcamId")
                loc = w.get("location") or {}
                if not wid or wid in seen or loc.get("latitude") is None:
                    continue
                img = (w.get("images") or {}).get("current") or {}
                player = w.get("player") or {}
                seen[wid] = True
                cams.append({
                    "id": wid, "title": w.get("title") or "Webcam", "lat": r5(loc.get("latitude")), "lon": r5(loc.get("longitude")),
                    "city": loc.get("city") or "", "img": img.get("preview") or img.get("thumbnail") or "",
                    "live": bool(player.get("live") or player.get("day")),
                    "url": (w.get("urls") or {}).get("detail") or f"https://www.windy.com/webcams/{wid}",
                })
            if len(j.get("webcams") or []) < 50:
                break
            time.sleep(2)
        time.sleep(2)
    if not cams:
        print("no webcams fetched; keeping previous file")
        write("webcams.json", prev or {"updated": None, "webcams": []})
        return
    print(f"{len(cams)} webcams from {requests} requests")
    write("webcams.json", {"updated": now(), "webcams": cams})


if __name__ == "__main__":
    ga511()
    windy()
