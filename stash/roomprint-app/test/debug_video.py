import json, os, subprocess, sys, tempfile, urllib.request
from playwright.sync_api import sync_playwright
BASE = "http://127.0.0.1:8788"
TMP = tempfile.mkdtemp(prefix="rp-dbg-")
video = os.path.join(TMP, "k.webm")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=duration=9:size=640x360:rate=24", "-c:v", "libvpx", "-b:v", "800k", "-an", video], check=True)
req = urllib.request.Request(BASE + "/api/start", method="POST", data=json.dumps({"name": "Dbg Test", "email": "d@example.com", "plan": "home"}).encode(), headers={"content-type": "application/json"})
url = json.loads(urllib.request.urlopen(req).read())["url"]
with sync_playwright() as pw:
    b = pw.chromium.launch()
    page = b.new_page(viewport={"width": 390, "height": 844})
    page.on("console", lambda m: print("console", m.type, m.text))
    page.on("pageerror", lambda e: print("PAGEERROR", e))
    page.goto(url); page.click("#introGo"); page.click('button.room[data-open="kitchen"]')
    page.locator('input[data-video="kitchen"]').first.set_input_files(video)
    page.wait_for_function("() => /saved|not added|No usable/.test(document.body.textContent)", timeout=90000)
    print("LABEL:", page.locator(".prog").inner_text())
    print("canplay webm:", page.evaluate("() => document.createElement('video').canPlayType('video/webm; codecs=vp8')"))
    print("canplay mp4:", page.evaluate("() => document.createElement('video').canPlayType('video/mp4; codecs=avc1.42E01E')"))
    b.close()
