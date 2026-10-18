#!/usr/bin/env python3
"""End-to-end test of the customer walkthrough against the local dev server (test/serve.mjs).
Needs: ffmpeg, Pillow, playwright (python) with Chromium.  Run: python3 test/e2e.py [base_url]
"""
import json, os, subprocess, sys, tempfile, urllib.request
from PIL import Image, ImageDraw

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8788"
TMP = tempfile.mkdtemp(prefix="rp-e2e-")

def http(method, path, data=None, headers=None):
    req = urllib.request.Request(BASE + path, method=method, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

def make_video(path):
    # 9 seconds of a changing test pattern so the frame picker keeps several distinct moments.
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=duration=9:size=640x360:rate=24",
                    "-c:v", "libvpx", "-b:v", "800k", "-an", path], check=True)

def make_photo(path, text):
    im = Image.new("RGB", (1600, 1200), (240, 236, 226))
    d = ImageDraw.Draw(im)
    d.rectangle([200, 300, 1400, 900], outline=(20, 30, 50), width=8)
    d.text((260, 380), text, fill=(20, 30, 50))
    for i in range(12):
        d.line([(260, 480 + i * 30), (1340, 480 + i * 30)], fill=(90, 100, 110), width=3)
    im.save(path, "JPEG", quality=85)

def main():
    from playwright.sync_api import sync_playwright
    video = os.path.join(TMP, "kitchen.webm"); make_video(video)
    p1 = os.path.join(TMP, "label1.jpg"); make_photo(p1, "LG LRFXS2503S  SN 211KRHT2X419")
    p2 = os.path.join(TMP, "label2.jpg"); make_photo(p2, "KitchenAid KSM150PS  SN W1234567")

    st, body = http("POST", "/api/start", json.dumps({"name": "Pat Whitfield", "email": "pat@example.com", "phone": "478-555-0142", "town": "Eatonton", "plan": "full"}).encode(), {"content-type": "application/json"})
    assert st == 200, body
    j = json.loads(body); url = j["url"]; jid = j["id"]; key = url.rsplit("/", 1)[1]
    print("job", jid, url)

    with sync_playwright() as pw:
        b = pw.chromium.launch()
        ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, is_mobile=True, has_touch=True)
        page = ctx.new_page()
        page.route("https://fonts.googleapis.com/**", lambda r: r.abort())  # no outside network in the test box
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("console", lambda m: errors.append("console." + m.type + ": " + m.text) if m.type == "error" and "fonts" not in m.text and "ERR_FAILED" not in m.text else None)
        page.goto(url)
        page.wait_for_selector("#introGo")
        page.screenshot(path=os.path.join(TMP, "1-intro.png"))
        page.click("#introGo")
        page.wait_for_selector("button.room")
        page.screenshot(path=os.path.join(TMP, "2-rooms.png"), full_page=True)
        assert page.locator("#footBtn").is_disabled()

        # Kitchen: video
        page.click('button.room[data-open="kitchen"]')
        page.wait_for_selector('input[data-video="kitchen"]')
        page.locator('input[data-video="kitchen"]').first.set_input_files(video)
        page.wait_for_function("() => /\\d+ moments saved/.test(document.body.textContent)", timeout=90000)
        page.wait_for_timeout(300)
        page.screenshot(path=os.path.join(TMP, "3-kitchen.png"), full_page=True)
        frames = page.locator(".th img").count()
        print("label:", page.locator(".prog").inner_text().replace("\n", " | "))
        print("kitchen frames shown:", frames)
        assert frames >= 3, "expected several frames from the test video"
        page.fill("#notes", "Fridge bought 2023, about $2,300. Have the receipt.")
        page.click("#markDone")
        page.wait_for_selector("button.room")

        # Labels: photos
        page.click('button.room[data-open="big-ticket-labels"]')
        page.wait_for_selector('input[data-photos="big-ticket-labels"]')
        page.locator('input[data-photos="big-ticket-labels"]').first.set_input_files([p1, p2])
        page.wait_for_function("() => /2 photos saved/.test(document.body.textContent)", timeout=60000)
        page.screenshot(path=os.path.join(TMP, "4-labels.png"), full_page=True)
        page.click("#back")
        page.wait_for_selector("button.room")

        # Add a custom room, then send
        page.fill("#crName", "Boat house")
        page.click("#customRoom button")
        page.wait_for_selector('button.room[data-open="boat-house"]')
        page.once("dialog", lambda d: d.accept())
        page.click("#footBtn")
        page.wait_for_function("() => /We're on it/.test(document.body.textContent)", timeout=20000)
        page.screenshot(path=os.path.join(TMP, "5-sent.png"), full_page=True)

        # Server-side checks: job.json on the branch, frames stored.
        st, keys = http("GET", "/__mock/keys"); keys = json.loads(keys)
        stored = [k for k in keys if k.startswith(f"mock:job-{jid}:jobs/{jid}/")]
        print("files in mock repo:", len(stored))
        st, jj = http("GET", f"/__mock/get?branch=job-{jid}&path=jobs/{jid}/job.json"); man = json.loads(jj)
        assert man["status"] == "ready" and man["totalImages"] >= 5, man
        assert any(r["slug"] == "kitchen" and r["notes"].startswith("Fridge") and r["done"] for r in man["rooms"])
        print("manifest ok: rooms", len(man["rooms"]), "images", man["totalImages"])

        # Builder says: built
        status = {"state": "built", "items": 212, "rooms": 11, "total": 48300, "builtAt": "2026-10-18T02:00:00Z", "message": "Two items need a clearer label photo; they're flagged in the record."}
        http("POST", "/__mock/put", json.dumps({"branch": f"job-{jid}", "path": f"jobs/{jid}/record/status.json", "content": json.dumps(status)}).encode(), {"content-type": "application/json"})
        page.reload(); page.wait_for_function("() => /Your record is ready/.test(document.body.textContent)", timeout=20000)
        page.screenshot(path=os.path.join(TMP, "6-built.png"), full_page=True)
        pay = page.locator('a:has-text("Pay $299 and unlock")')
        assert pay.count() == 1
        href = pay.get_attribute("href"); print("pay link:", href)
        assert href.startswith("/pay/") or "/pay/" in href
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *a, **k): return None
        op = urllib.request.build_opener(NoRedirect)
        try:
            op.open(BASE + "/pay/" + jid + "/" + key)
        except urllib.error.HTTPError as e:
            loc = e.headers.get("Location", "")
            assert e.code == 302 and loc.startswith("https://www.paypal.com/cgi-bin/webscr?cmd=_xclick") and ("custom=" + jid) in loc and "amount=299.00" in loc, (e.code, loc)
            print("paypal redirect ok:", loc[:90] + "…")
        # Paid: download appears
        http("POST", "/__mock/put", json.dumps({"branch": f"job-{jid}", "path": f"jobs/{jid}/record/record.pdf", "content": "%PDF-1.4 test"}).encode(), {"content-type": "application/json"})
        http("POST", "/__mock/put", json.dumps({"branch": f"job-{jid}", "path": f"jobs/{jid}/record/record.csv", "content": "room,item\nKitchen,Fridge"}).encode(), {"content-type": "application/json"})
        status.update({"state": "paid", "paidAt": "2026-10-18T03:00:00Z", "password": "0142", "files": ["record.pdf", "record.csv"]})
        http("POST", "/__mock/put", json.dumps({"branch": f"job-{jid}", "path": f"jobs/{jid}/record/status.json", "content": json.dumps(status)}).encode(), {"content-type": "application/json"})
        page.reload(); page.wait_for_function("() => /Here's your record/.test(document.body.textContent)", timeout=20000)
        page.screenshot(path=os.path.join(TMP, "7-paid.png"), full_page=True)
        st, pdf = http("GET", f"/api/job/{jid}/file/record.pdf?k={key}")
        assert st == 200 and pdf.startswith(b"%PDF"), (st, pdf[:40])
        st, nope = http("GET", f"/api/job/{jid}/file/record.pdf?k=wrongkey")
        assert st == 404
        print("downloads ok; wrong key refused")
        b.close()
        if errors:
            print("BROWSER ERRORS:"); [print("  ", e) for e in errors]
        assert not [e for e in errors if "favicon" not in e], "browser errors"
    print("ALL GOOD. Screenshots in", TMP)

if __name__ == "__main__":
    main()
