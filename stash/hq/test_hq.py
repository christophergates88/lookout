#!/usr/bin/env python3
"""Exercise Gates HQ in headless Chromium with a mocked artifact runtime.
Usage: python3 test_hq.py gates_hq.html [--shots DIR]
"""
import json, os, sys, time, datetime
from playwright.sync_api import sync_playwright

HTML = os.path.abspath(sys.argv[1])
SHOTS = sys.argv[sys.argv.index("--shots") + 1] if "--shots" in sys.argv else None
if SHOTS: os.makedirs(SHOTS, exist_ok=True)
today = datetime.date.today()
k = lambda d: d.isoformat()
seed = {
  "tasks/t1": {"title": "Call Sree about the referral pitch", "area": "statefarm", "due": k(today), "top": True, "done": False, "notes": "Bring the one-pager", "created": "2026-10-15T10:00:00Z"},
  "tasks/t2": {"title": "Run calibrator lot 2261 QC", "area": "lab", "due": k(today - datetime.timedelta(days=2)), "top": True, "done": False, "notes": "", "created": "2026-10-14T10:00:00Z"},
  "tasks/t3": {"title": "Oil change on the Silverado", "area": "home", "due": k(today + datetime.timedelta(days=1)), "top": True, "done": False, "notes": "", "created": "2026-10-13T10:00:00Z"},
  "tasks/t4": {"title": "Fourth pinned task (should still be visible somewhere)", "area": "general", "due": "", "top": True, "done": False, "notes": "", "created": "2026-10-12T10:00:00Z"},
  "tasks/t5": {"title": "Create the two GitHub repos for Roomprint", "area": "venture:roomprint", "due": "", "top": False, "done": False, "notes": "", "created": "2026-10-17T10:00:00Z"},
  "tasks/t6": {"title": "Done lab thing", "area": "lab", "due": "", "top": False, "done": True, "doneAt": datetime.datetime.utcnow().isoformat() + "Z", "notes": "", "created": "2026-10-11T10:00:00Z"},
  "ventures/roomprint": {"name": "Roomprint", "status": "active", "line": "Self-recorded home contents records.", "next": "Link the Mac or create the two GitHub repos", "links": [{"label": "Roomprint HQ", "url": "https://example.com"}], "decisions": [{"date": "2026-10-17", "text": "Hands-off model."}], "order": 1,
                         "updates": [{"at": "2026-10-18T01:00:00Z", "text": "Customer app and record builder built and tested.", "by": "Claude"}], "needs": "Link the Mac in the Claude app, or create the two GitHub repos; send your PayPal email."},
  "ventures/lookout": {"name": "Lookout", "status": "live", "line": "Situational awareness app.", "next": "Wait on the GDOT key.", "links": [], "decisions": [], "order": 3},
  "ventures/noname": {"status": "exploring", "line": "A venture someone saved without a name", "order": 9},
  "household/katie": {"kind": "person", "name": "Katie", "detail": "", "dates": [{"when": k(today + datetime.timedelta(days=3)), "what": "Anniversary dinner"}], "log": []},
  "household/truck": {"kind": "vehicle", "name": "Silverado", "detail": "2023 1500 Custom", "dates": [{"when": k(today), "what": "Registration due"}], "log": [{"date": "2026-09-01", "miles": 21000, "text": "Oil change"}]},
  "bills/b1": {"name": "Mortgage", "amount": 1850, "cadence": "monthly", "dueDay": 1, "cat": "bill", "active": True},
  "bills/b2": {"name": "Netflix", "amount": 15.49, "cadence": "monthly", "dueDay": today.day, "cat": "subscription", "active": True},
  "bills/b3": {"name": "Affirm couch", "amount": 120, "cadence": "monthly", "dueDay": 15, "cat": "bnpl", "balance": 1200, "active": True},
  "bills/b4": {"name": "Truck loan", "amount": 640, "cadence": "monthly", "dueDay": 20, "cat": "debt", "balance": 31000, "active": True},
  "bills/b5": {"name": "Amazon Prime", "amount": 139, "cadence": "yearly", "dueDay": 5, "dueMonth": "", "cat": "subscription", "active": True},
  "income/i1": {"source": "Lab salary", "amount": 3400, "cadence": "biweekly"},
  "income/i2": {"source": "Charlie Pelt Insurance", "amount": 900, "cadence": "monthly"},
  "watchlist/w1": {"question": "BTC above $150k by Dec 31?", "side": "Yes", "note": "ETF flows"},
  "days/" + k(today): {"date": k(today), "brief": "## Saturday, October 17\nQuiet day. **Rain** after 4.\n\n## Needs you\n- Create the Roomprint repos\n- Pay the Affirm bill\n\n## Top 3\n- Call Sree\n- QC run\n- Oil change", "notes": ""},
  "me/fitness": {"sessions": [{"id": "s1", "date": k(today), "type": "Boxing", "min": 45}, {"id": "s2", "date": k(today - datetime.timedelta(days=2)), "type": "Lift", "min": 60}]},
  "me/btc": {"btc": 0.5, "basis": 20000, "price": 118000, "priceAt": k(today)},
  "notes/lab": {"text": "Lot 2261 looks fine.", "updated": "2026-10-17T12:00:00Z"},
  "notes/builds": {"text": "", "updated": ""},
  "notes/referrals": {"text": "Report sent to the team: 3 contacted, 1 reply.", "updated": "2026-10-13T11:00:00Z"},
  "settings/statefarm": {"agent": "Sree Alangad", "teammate": "Dariann", "inbox": "weeklyreferrals@gmail.com", "email": "chris.gates.vaha3s@statefarm.com", "reportDay": "Monday", "notes": ""},
  "imports/im1": {"label": "Checking Sep", "rows": [["2026-09-02", "KROGER #412", -84.12], ["2026-09-03", "NETFLIX.COM", -15.49], ["2026-09-05", "PAYROLL LAKE COUNTRY MEDICAL", 3400], ["2026-09-15", "AFFIRM PAYMENT", -120], ["2026-10-03", "NETFLIX.COM", -15.49], ["2026-10-04", "SHELL OIL", -62.3]], "from": "2026-09-02", "to": "2026-10-04", "created": "2026-10-10T00:00:00Z"},
}

def run(offline=False, width=390, dark=False, label="phone"):
    errors = []
    with sync_playwright() as pw:
        b = pw.chromium.launch()
        ctx = b.new_context(viewport={"width": width, "height": 844 if width < 900 else 900}, device_scale_factor=2, color_scheme="dark" if dark else "light", permissions=["clipboard-read", "clipboard-write"])
        page = ctx.new_page()
        page.route("https://fonts.googleapis.com/**", lambda r: r.abort())
        page.on("pageerror", lambda e: errors.append("PAGEERROR " + str(e)))
        page.on("console", lambda m: errors.append("console." + m.type + ": " + m.text) if m.type == "error" and "fonts" not in m.text and "ERR_FAILED" not in m.text else None)
        page.add_init_script("window.__seed=" + json.dumps(seed) + ";window.__offline=" + ("true" if offline else "false") + ";")
        page.add_init_script(path=os.path.join(os.path.dirname(HTML), "mock.js"))
        page.goto("file://" + HTML)
        page.wait_for_timeout(600)
        def shot(name):
            if SHOTS: page.screenshot(path=os.path.join(SHOTS, f"{label}-{name}.png"), full_page=True)
        shot("today")
        if offline:
            assert "Not connected" in page.inner_text("[data-r=brief]"), "offline message missing"
            b.close(); return errors
        text = page.inner_text("#pane-today")
        assert "Fourth pinned task" in text, "4th pinned task vanished from Today"
        assert "Mortgage" in text or "Netflix" in text, "bills due missing"
        # quick add
        page.fill("#quick-title", "Test task from harness"); page.press("#quick-title", "Enter"); page.wait_for_timeout(200)
        assert any(w["op"] == "set" and w["path"].startswith("tasks/") and w["data"]["title"] == "Test task from harness" for w in page.evaluate("()=>window.__hqMock.writes")), "quick add did not write"
        # toggle task done then undo if available
        page.click('[data-act="task-toggle"][data-id="t5"]'); page.wait_for_timeout(200)
        st = page.evaluate("()=>window.__hqMock.store['tasks/t5'].done"); assert st is True, "toggle failed"
        # open sheet, edit, save
        page.click('[data-act="task-edit"][data-id="t1"] .title'); page.wait_for_selector("#sheet:not([hidden])")
        page.fill("#f-title", "Call Sree about the referral pitch (edited)"); page.click("#sheet-save"); page.wait_for_timeout(200)
        assert page.evaluate("()=>window.__hqMock.store['tasks/t1'].title").endswith("(edited)"), "sheet save failed"
        # journal autosave / save
        page.fill("#journal", "Good day. Built Roomprint."); page.click('[data-act="journal-save"]'); page.wait_for_timeout(200)
        d = page.evaluate("()=>window.__hqMock.store['days/" + k(today) + "']"); assert d["notes"].startswith("Good day") and d.get("brief"), "journal save lost the brief"
        # work
        page.click('.tabbar [data-nav="work"]' if width < 900 else '.rail [data-nav="work"]'); page.wait_for_timeout(100); shot("work")
        assert "Sree" in page.inner_text("#pane-work")
        page.click('[data-seg="work"][data-val="lab"]'); page.wait_for_timeout(100)
        page.fill("#notes-lab", "Lot 2261 looks fine. Added a line."); page.click('[data-act="notes-save"][data-key="lab"]'); page.wait_for_timeout(200)
        assert page.evaluate("()=>window.__hqMock.store['notes/lab'].text").endswith("Added a line.")
        # ventures
        page.click('.tabbar [data-nav="ventures"]' if width < 900 else '.rail [data-nav="ventures"]'); page.wait_for_timeout(100); shot("ventures")
        vt = page.inner_text("#pane-ventures"); assert "Roomprint" in vt and "Lookout" in vt, "ventures missing"
        page.click('[data-act="venture-status"][data-id="lookout"]'); page.wait_for_timeout(200)
        assert page.evaluate("()=>window.__hqMock.store['ventures/lookout'].status") == "parked"
        # money
        page.click('.tabbar [data-nav="money"]' if width < 900 else '.rail [data-nav="money"]'); page.wait_for_timeout(100); shot("money")
        mt = page.inner_text("[data-r=money-tiles]")
        print("money tiles:", mt.replace("\n", " | "))
        page.fill("#csv-text", "Date,Description,Amount\n10/05/2026,KROGER #412,-54.10\n10/06/2026,NETFLIX.COM,-15.49\n10/07/2026,PAYROLL LAKE COUNTRY MEDICAL,3400.00\n")
        page.fill("#csv-label", "Checking Oct"); page.click('[data-act="csv-import"]'); page.wait_for_timeout(300)
        assert "Imported 3 rows" in page.inner_text("#csv-status"), page.inner_text("#csv-status")
        page.click('[data-act="bill-new"]'); page.wait_for_selector("#sheet:not([hidden])"); page.fill("#f-name", "Georgia Power"); page.fill("#f-amount", "210"); page.click("#sheet-save"); page.wait_for_timeout(200)
        assert any(w["op"] == "set" and w["path"].startswith("bills/") and w["data"]["name"] == "Georgia Power" for w in page.evaluate("()=>window.__hqMock.writes"))
        # life
        page.click('.tabbar [data-nav="life"]' if width < 900 else '.rail [data-nav="life"]'); page.wait_for_timeout(100); shot("life-home")
        assert "Silverado" in page.inner_text("#pane-life")
        page.click('[data-seg="life"][data-val="me"]'); page.wait_for_timeout(100); shot("life-me")
        page.fill("#fit-min", "30"); page.click('[data-act="fit-add"]'); page.wait_for_timeout(200)
        assert len(page.evaluate("()=>window.__hqMock.store['me/fitness'].sessions")) == 3
        page.click('[data-act="btc-edit"]'); page.wait_for_selector("#sheet:not([hidden])"); page.fill("#f-price", "120000"); page.click("#sheet-save"); page.wait_for_timeout(200)
        print("btc doc:", page.evaluate("()=>window.__hqMock.store['me/btc']"))
        page.click('[data-act="export"]'); page.wait_for_timeout(300)
        assert any(w["op"] == "download" for w in page.evaluate("()=>window.__hqMock.writes")), "export did not download"
        page.click('[data-act="brief-copy"]'); page.wait_for_timeout(300)
        clip = page.evaluate("()=>navigator.clipboard.readText()")
        assert clip.startswith("GATES HQ"), "brief copy failed: " + clip[:60]
        # sheet delete (double tap)
        page.click('.tabbar [data-nav="today"]' if width < 900 else '.rail [data-nav="today"]'); page.wait_for_timeout(100)
        page.click('[data-act="task-edit"][data-id="t3"] .title'); page.wait_for_selector("#sheet:not([hidden])"); page.click("#sheet-delete"); page.click("#sheet-delete"); page.wait_for_timeout(200)
        assert page.evaluate("()=>!window.__hqMock.store['tasks/t3']"), "delete failed"
        shot("today-after")
        b.close()
    return errors

if __name__ == "__main__":
    allerr = []
    for args in [dict(width=390), dict(width=1280, label="desktop"), dict(width=390, dark=True, label="dark"), dict(offline=True, label="offline")]:
        try:
            errs = run(**args); print(args, "->", "OK" if not errs else errs)
            allerr += errs
        except AssertionError as e:
            print(args, "-> ASSERTION:", e); allerr.append(str(e))
    print("RESULT:", "CLEAN" if not allerr else f"{len(allerr)} problem(s)")
