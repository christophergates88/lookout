#!/usr/bin/env python3
"""Roomprint home record generator: record.json -> locked PDF, CSV, summary.json.

Usage:
  python3 make_record.py record.json OUT_DIR [--password SECRET]

Writes OUT_DIR/record.pdf (locked if --password), OUT_DIR/record-unlocked.pdf, OUT_DIR/record.csv,
OUT_DIR/summary.json.  Totals are computed here; never typed by hand.

record.json:
{
  "home": "The Whitfield home", "town": "Eatonton, GA", "recordedOn": "2026-10-18", "recordId": "RP-0001",
  "preparedFor": "Pat Whitfield", "email": "pat@example.com",
  "items": [
    {"room": "Kitchen", "item": "French-door refrigerator", "detail": "LG LRFXS2503S · SN 211KRHT2X419",
     "qty": 1, "unit": 2300, "proof": "s", "evidence": "label photo 1", "photo": "/abs/path/frame.jpg",
     "confidence": "high"}
  ],
  "todo": ["..."],            # optional; built automatically if absent
  "notes": "..."              # optional note shown on the cover
}
proof: "s" serial number recorded, "r" receipt/appraisal/owner record, "" none.
"""
import csv, datetime, json, os, sys
from collections import OrderedDict

from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Frame, Image, KeepTogether, PageBreak,
                                PageTemplate, Paragraph, Spacer, Table, TableStyle)

NAVY = colors.HexColor("#16263A"); VELLUM = colors.HexColor("#F3EEE2"); REC = colors.HexColor("#D9472F")
INK = NAVY; MUTED = colors.HexColor("#5D6A79"); LINE = colors.HexColor("#DDD8CE"); BAND = colors.HexColor("#F6F4EF")
OK = colors.HexColor("#2F7D5B"); WARN = colors.HexColor("#A86E14")
HIGH_VALUE = 1000

def money(n): return "${:,.0f}".format(round(float(n or 0)))
def esc(s): return str(s or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
def nice_date(s):
    try: return datetime.date.fromisoformat(str(s)[:10]).strftime("%B %-d, %Y")
    except Exception: return str(s or "")

S = {
    "h1": ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=28, leading=32, textColor=INK),
    "h2": ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=16, leading=20, textColor=INK, spaceBefore=6, spaceAfter=4),
    "body": ParagraphStyle("body", fontName="Helvetica", fontSize=10, leading=14, textColor=INK),
    "muted": ParagraphStyle("muted", fontName="Helvetica", fontSize=9, leading=12, textColor=MUTED),
    "label": ParagraphStyle("label", fontName="Helvetica", fontSize=8, leading=10, textColor=MUTED),
    "big": ParagraphStyle("big", fontName="Helvetica-Bold", fontSize=26, leading=30, textColor=INK),
    "mid": ParagraphStyle("mid", fontName="Helvetica-Bold", fontSize=18, leading=22, textColor=INK),
    "cell": ParagraphStyle("cell", fontName="Helvetica", fontSize=9, leading=11.5, textColor=INK),
    "cellb": ParagraphStyle("cellb", fontName="Helvetica-Bold", fontSize=9.5, leading=12, textColor=INK),
    "cellr": ParagraphStyle("cellr", fontName="Helvetica-Bold", fontSize=9.5, leading=12, textColor=INK, alignment=TA_RIGHT),
    "cellm": ParagraphStyle("cellm", fontName="Helvetica", fontSize=8, leading=10, textColor=MUTED),
    "cellmr": ParagraphStyle("cellmr", fontName="Helvetica", fontSize=8, leading=10, textColor=MUTED, alignment=TA_RIGHT),
}

def draw_mark(c, x, y, size):
    k = size / 64.0
    c.saveState()
    c.setFillColor(NAVY); c.roundRect(x, y, size, size, 14 * k, stroke=0, fill=1)
    P = lambda px, py: (x + px * k, y + (64 - py) * k)
    c.setStrokeColor(VELLUM); c.setLineJoin(1); c.setLineWidth(4.5 * k)
    p = c.beginPath(); p.moveTo(*P(12, 29)); p.lineTo(*P(32, 13)); p.lineTo(*P(52, 29)); p.lineTo(*P(52, 51)); p.lineTo(*P(12, 51)); p.close()
    c.drawPath(p, stroke=1, fill=0)
    c.setLineWidth(2.6 * k); c.setLineCap(1)
    for pts in [[(21, 34), (21, 31), (24, 31)], [(43, 34), (43, 31), (40, 31)], [(21, 41), (21, 44), (24, 44)], [(43, 41), (43, 44), (40, 44)]]:
        q = c.beginPath(); q.moveTo(*P(*pts[0]))
        for pt in pts[1:]: q.lineTo(*P(*pt))
        c.drawPath(q, stroke=1, fill=0)
    c.setFillColor(colors.HexColor("#E5533D")); cx, cy = P(32, 37.5); c.circle(cx, cy, 3.6 * k, stroke=0, fill=1)
    c.restoreState()

def thumb(path, w=0.9 * inch, h=0.68 * inch):
    try:
        from PIL import Image as PILImage
        with PILImage.open(path) as im:
            iw, ih = im.size
        s = min(w / iw, h / ih)
        return Image(path, width=iw * s, height=ih * s)
    except Exception:
        return Paragraph("", S["cellm"])

def build(data, out_dir, password=None):
    os.makedirs(out_dir, exist_ok=True)
    items = data.get("items", [])
    for i, it in enumerate(items):
        it["_n"] = "RP-%03d" % (i + 1)
        it["_qty"] = int(it.get("qty") or 1)
        it["_unit"] = float(it.get("unit") or 0)
        it["_total"] = it["_qty"] * it["_unit"]
    rooms = OrderedDict()
    for it in items:
        rooms.setdefault(it.get("room") or "Other", []).append(it)
    total = sum(it["_total"] for it in items)
    count = sum(it["_qty"] for it in items)
    need_proof = [it for it in items if not it.get("proof") and it["_total"] >= HIGH_VALUE]
    low_conf = [it for it in items if (it.get("confidence") or "").lower() == "low"]
    todo = data.get("todo")
    if not todo:
        todo = []
        if need_proof:
            todo.append("Photograph the serial-number label, or find a receipt or appraisal, for these high-value items: " + "; ".join(it["item"] for it in need_proof[:12]) + ("…" if len(need_proof) > 12 else ""))
        jewel = [it for it in items if any(k in (it["item"] + " " + (it.get("detail") or "")).lower() for k in ("jewel", "ring", "necklace", "watch", "art", "painting", "collect", "antique", "coin", "gun", "rifle"))]
        if jewel:
            todo.append("Get a written appraisal for jewelry, art, firearms and collectibles; most policies cap these without one: " + "; ".join(it["item"] for it in jewel[:10]))
        if low_conf:
            todo.append("Check these items we couldn't see clearly and tell us if anything is wrong: " + "; ".join(it["item"] for it in low_conf[:10]))
        todo.append("Keep this record and the spreadsheet somewhere outside the home (email, cloud drive, a relative). Ask your insurance agent whether your contents coverage is at least " + money(total) + ".")
        todo.append("Update the record once a year or after big purchases.")

    home = data.get("home", "Home"); town = data.get("town", ""); rec_id = data.get("recordId", "")
    recorded = nice_date(data.get("recordedOn", datetime.date.today().isoformat()))
    prepared = data.get("preparedFor", "")

    unlocked = os.path.join(out_dir, "record-unlocked.pdf")
    W, H = letter
    doc = BaseDocTemplate(unlocked, pagesize=letter, leftMargin=0.7 * inch, rightMargin=0.7 * inch, topMargin=0.85 * inch, bottomMargin=0.8 * inch,
                          title=f"{home} — Home Contents Record", author="Roomprint", subject="Home contents record")
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)

    def on_page(c, d):
        c.saveState()
        c.setFillColor(NAVY); c.rect(0, H - 0.55 * inch, W, 0.55 * inch, stroke=0, fill=1)
        draw_mark(c, 0.7 * inch, H - 0.47 * inch, 0.36 * inch)
        c.setFillColor(VELLUM); c.setFont("Helvetica-Bold", 11); c.drawString(0.7 * inch + 0.46 * inch, H - 0.37 * inch, "Roomprint")
        c.setFont("Helvetica", 9); c.drawRightString(W - 0.7 * inch, H - 0.37 * inch, f"{home} · {rec_id} · Page {d.page}")
        c.setFillColor(MUTED); c.setFont("Helvetica", 7.5)
        c.drawString(0.7 * inch, 0.45 * inch, "Values are estimated replacement costs (what a similar new item costs today), not appraisals. Not insurance advice.")
        c.drawRightString(W - 0.7 * inch, 0.45 * inch, "Private to " + (prepared or "the owner"))
        c.restoreState()

    def cover_page(c, d):
        c.saveState()
        c.setFillColor(NAVY); c.rect(0, H - 3.6 * inch, W, 3.6 * inch, stroke=0, fill=1)
        draw_mark(c, 0.7 * inch, H - 1.4 * inch, 0.7 * inch)
        c.setFillColor(VELLUM); c.setFont("Helvetica-Bold", 16); c.drawString(0.7 * inch + 0.85 * inch, H - 1.15 * inch, "Roomprint")
        c.setFont("Helvetica", 10); c.setFillColor(colors.HexColor("#C9D2DD")); c.drawString(0.7 * inch + 0.85 * inch, H - 1.33 * inch, "Home contents record")
        c.setFillColor(VELLUM); c.setFont("Helvetica-Bold", 30); c.drawString(0.7 * inch, H - 2.35 * inch, home[:40])
        c.setFont("Helvetica", 12); c.setFillColor(colors.HexColor("#C9D2DD"))
        c.drawString(0.7 * inch, H - 2.65 * inch, " · ".join(x for x in [town, "Recorded " + recorded, rec_id] if x))
        if prepared: c.drawString(0.7 * inch, H - 2.9 * inch, "Prepared for " + prepared)
        c.setFillColor(MUTED); c.setFont("Helvetica", 7.5)
        c.drawString(0.7 * inch, 0.45 * inch, "Values are estimated replacement costs (what a similar new item costs today), not appraisals. Not insurance advice.")
        c.restoreState()

    doc.addPageTemplates([PageTemplate(id="cover", frames=[Frame(doc.leftMargin, doc.bottomMargin, doc.width, H - 3.6 * inch - doc.bottomMargin - 0.3 * inch, id="c", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)], onPage=cover_page),
                          PageTemplate(id="body", frames=[frame], onPage=on_page)])
    story = []

    # Cover summary
    room_rows = [[Paragraph("<b>Room</b>", S["cell"]), Paragraph("<b>Items</b>", S["cellr"]), Paragraph("<b>Replacement value</b>", S["cellr"])]]
    for rn, its in rooms.items():
        room_rows.append([Paragraph(esc(rn), S["cell"]), Paragraph(str(sum(i["_qty"] for i in its)), S["cellr"]), Paragraph(money(sum(i["_total"] for i in its)), S["cellr"])])
    room_rows.append([Paragraph("<b>Total</b>", S["cellb"]), Paragraph("<b>%d</b>" % count, S["cellr"]), Paragraph("<b>%s</b>" % money(total), S["cellr"])])
    big = Table([[Paragraph("Items recorded", S["label"]), Paragraph("Rooms", S["label"]), Paragraph("Estimated replacement value", S["label"])],
                 [Paragraph(str(count), S["big"]), Paragraph(str(len(rooms)), S["big"]), Paragraph(money(total), S["big"])]], colWidths=[doc.width * 0.3, doc.width * 0.25, doc.width * 0.45])
    big.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "BOTTOM"), ("BOTTOMPADDING", (0, 0), (-1, 0), 0), ("TOPPADDING", (0, 1), (-1, 1), 2)]))
    story += [Spacer(1, 0.1 * inch), big, Spacer(1, 0.18 * inch)]
    t = Table(room_rows, colWidths=[doc.width * 0.55, doc.width * 0.15, doc.width * 0.30], repeatRows=1)
    t.setStyle(TableStyle([("LINEBELOW", (0, 0), (-1, 0), 1, INK), ("LINEBELOW", (0, 1), (-1, -2), 0.4, LINE), ("LINEABOVE", (0, -1), (-1, -1), 1, INK),
                           ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4), ("LEFTPADDING", (0, 0), (-1, -1), 2), ("RIGHTPADDING", (0, 0), (-1, -1), 2)]))
    story += [t, Spacer(1, 0.16 * inch)]
    if data.get("notes"):
        story += [Paragraph(esc(data["notes"]), S["muted"]), Spacer(1, 0.1 * inch)]
    story += [Paragraph("How to use this record", S["h2"]),
              Paragraph("Give the spreadsheet (CSV) to your insurer with a claim; it has one line per item with the values below. Keep this PDF as your own copy. "
                        "Items marked <b>S</b> have a serial number recorded from the label; <b>R</b> means you told us you hold a receipt, appraisal or other record. "
                        "Replacement values are rounded estimates of what a similar new item costs today.", S["body"])]
    from reportlab.platypus import NextPageTemplate
    story += [NextPageTemplate("body"), PageBreak()]

    # Rooms
    for rn, its in rooms.items():
        rows = [[Paragraph("<b>#</b>", S["cellm"]), "", Paragraph("<b>Item</b>", S["cell"]), Paragraph("<b>Qty</b>", S["cellr"]), Paragraph("<b>Each</b>", S["cellr"]), Paragraph("<b>Total</b>", S["cellr"])]]
        for it in its:
            flags = []
            if "s" in (it.get("proof") or ""): flags.append("S")
            if "r" in (it.get("proof") or ""): flags.append("R")
            label = "<b>%s</b>" % esc(it["item"])
            sub = []
            if it.get("detail"): sub.append(esc(it["detail"]))
            if it.get("evidence"): sub.append("Seen: " + esc(it["evidence"]))
            if flags: sub.append("Proof: " + "/".join(flags))
            if (it.get("confidence") or "").lower() == "low": sub.append("Please check")
            cell = Paragraph(label + ("<br/><font size=8 color='#5D6A79'>" + " · ".join(sub) + "</font>" if sub else ""), S["cell"])
            img = thumb(it["photo"]) if it.get("photo") and os.path.exists(it["photo"]) else ""
            rows.append([Paragraph(it["_n"], S["cellm"]), img, cell, Paragraph(str(it["_qty"]), S["cellr"]), Paragraph(money(it["_unit"]), S["cellmr"]), Paragraph(money(it["_total"]), S["cellr"])])
        rows.append(["", "", Paragraph("<b>%s total</b>" % esc(rn), S["cellb"]), Paragraph("<b>%d</b>" % sum(i["_qty"] for i in its), S["cellr"]), "", Paragraph("<b>%s</b>" % money(sum(i["_total"] for i in its)), S["cellr"])])
        tbl = Table(rows, colWidths=[0.5 * inch, 0.98 * inch, doc.width - 0.5 * inch - 0.98 * inch - 0.45 * inch - 0.8 * inch - 0.85 * inch, 0.45 * inch, 0.8 * inch, 0.85 * inch], repeatRows=1)
        tbl.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("LINEBELOW", (0, 0), (-1, 0), 1, INK), ("LINEBELOW", (0, 1), (-1, -2), 0.4, LINE), ("LINEABOVE", (0, -1), (-1, -1), 1, INK),
                                 ("ROWBACKGROUNDS", (0, 1), (-1, -2), [colors.white, BAND]), ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4), ("LEFTPADDING", (0, 0), (-1, -1), 3), ("RIGHTPADDING", (0, 0), (-1, -1), 3)]))
        story += [CondPageBreak(1.6 * inch), Paragraph(esc(rn), S["h2"]), tbl, Spacer(1, 0.2 * inch)]

    # To do
    story += [CondPageBreak(2 * inch), Paragraph("What to do next", S["h2"])]
    for tline in todo:
        story.append(Paragraph("• " + esc(tline), S["body"]))
    story += [Spacer(1, 0.2 * inch), Paragraph("Prepared by Roomprint from the owner's own walkthrough video and photos. Values checked against current retail prices on " + recorded + ". Questions or corrections: reply to the delivery email.", S["muted"])]
    doc.build(story)

    # Locked copy
    locked = os.path.join(out_dir, "record.pdf")
    if password:
        from pypdf import PdfReader, PdfWriter
        r = PdfReader(unlocked); w = PdfWriter()
        for pg in r.pages: w.add_page(pg)
        w.add_metadata(r.metadata or {})
        w.encrypt(user_password=str(password), owner_password=str(password) + "-rp", algorithm="AES-256")
        with open(locked, "wb") as f: w.write(f)
    else:
        import shutil; shutil.copyfile(unlocked, locked)

    # CSV
    with open(os.path.join(out_dir, "record.csv"), "w", newline="", encoding="utf-8") as f:
        wr = csv.writer(f)
        wr.writerow(["Record", "Room", "Item", "Brand / model / serial", "Qty", "Replacement cost each", "Replacement cost total", "Proof", "Where seen", "Confidence"])
        for it in items:
            wr.writerow([it["_n"], it.get("room", ""), it["item"], it.get("detail", ""), it["_qty"], int(round(it["_unit"])), int(round(it["_total"])), {"s": "Serial recorded", "r": "Owner record", "sr": "Serial + record", "rs": "Serial + record"}.get(it.get("proof") or "", ""), it.get("evidence", ""), it.get("confidence", "")])
        wr.writerow([]); wr.writerow(["", "", "TOTAL", "", count, "", int(round(total)), "", "", ""])

    summary = {"items": count, "lines": len(items), "rooms": len(rooms), "total": int(round(total)), "highValueWithoutProof": len(need_proof), "lowConfidence": len(low_conf),
               "roomTotals": {rn: int(round(sum(i["_total"] for i in its))) for rn, its in rooms.items()}, "recordId": rec_id, "home": home}
    with open(os.path.join(out_dir, "summary.json"), "w") as f: json.dump(summary, f, indent=2)
    return summary

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    pw = None
    if "--password" in sys.argv:
        pw = sys.argv[sys.argv.index("--password") + 1]
    with open(sys.argv[1]) as f: data = json.load(f)
    s = build(data, sys.argv[2], pw)
    print(json.dumps(s))
