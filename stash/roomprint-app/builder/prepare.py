#!/usr/bin/env python3
"""Prepare a home for cataloging: contact sheets per room + an index the builder reads.

Usage: python3 prepare.py UPLOADS_REPO_DIR JOB_ID WORK_DIR

Reads  UPLOADS_REPO_DIR/jobs/JOB_ID/job.json (the job branch must be checked out).
Writes WORK_DIR/JOB_ID/index.md, WORK_DIR/JOB_ID/sheets/<room>-<n>.jpg, WORK_DIR/JOB_ID/labels/<room>-<file>.jpg
Only media listed in job.json is used; files the customer removed are ignored.
"""
import json, os, shutil, sys
from PIL import Image, ImageDraw, ImageFont, ImageOps

TILE_W, TILE_H, COLS, ROWS = 600, 420, 3, 3

def font(sz):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
        if os.path.exists(p): return ImageFont.truetype(p, sz)
    return ImageFont.load_default()

def sheet(paths, labels, out):
    n = len(paths)
    rows = (n + COLS - 1) // COLS
    im = Image.new("RGB", (COLS * TILE_W + (COLS + 1) * 8, rows * (TILE_H + 26) + (rows + 1) * 8), (24, 30, 40))
    d = ImageDraw.Draw(im); f = font(20)
    for i, p in enumerate(paths):
        r, c = divmod(i, COLS)
        x = 8 + c * (TILE_W + 8); y = 8 + r * (TILE_H + 26 + 8)
        try:
            with Image.open(p) as src:
                src = ImageOps.exif_transpose(src).convert("RGB")
                src.thumbnail((TILE_W, TILE_H))
                im.paste(src, (x + (TILE_W - src.width) // 2, y + (TILE_H - src.height) // 2))
        except Exception as e:
            d.text((x + 10, y + 10), "unreadable: " + os.path.basename(p), fill=(255, 120, 100), font=f)
        d.rectangle([x, y + TILE_H, x + TILE_W, y + TILE_H + 26], fill=(243, 238, 226))
        d.text((x + 6, y + TILE_H + 3), labels[i], fill=(22, 38, 58), font=f)
    im.save(out, "JPEG", quality=82)

def main():
    repo, jid, work = sys.argv[1], sys.argv[2], sys.argv[3]
    jdir = os.path.join(repo, "jobs", jid)
    with open(os.path.join(jdir, "job.json")) as fh: job = json.load(fh)
    out = os.path.join(work, jid); sheets = os.path.join(out, "sheets"); labels = os.path.join(out, "labels")
    for d in (sheets, labels): os.makedirs(d, exist_ok=True)
    lines = [f"# {job.get('homeName') or 'Home'} — job {jid}", "",
             f"Customer: {job.get('name')} · {job.get('email')} · {job.get('phone') or 'no phone'} · {job.get('town') or ''}",
             f"Plan: {job.get('planLabel')} (${job.get('price')}) · status {job.get('status')} · ready {job.get('readyAt')}",
             f"Payment note from customer: {job.get('paidNote') or '(none)'}", ""]
    total_imgs = 0; room_count = 0
    for room in job.get("rooms", []):
        media = [m for m in room.get("media", []) if m.get("file")]
        if not media and not room.get("notes"):
            continue
        rdir = os.path.join(jdir, room["slug"])
        lines.append(f"## {room['name']}  (slug `{room['slug']}`, kind {room.get('kind','room')}, {len(media)} images)")
        if room.get("notes"): lines.append(f"Owner's notes: {room['notes'].strip()}")
        if not media:
            lines.append("(no images)"); lines.append(""); continue
        room_count += 1; total_imgs += len(media)
        frames = sorted([m for m in media if m.get("kind") == "frame"], key=lambda m: (m.get("t") or 0, m["file"]))
        photos = [m for m in media if m.get("kind") != "frame"]
        if room.get("kind") in ("labels", "receipts"):
            # Label and receipt photos are copied individually: they must be read at full size.
            for m in photos + frames:
                src = os.path.join(rdir, m["file"])
                if not os.path.exists(src): lines.append(f"- missing file {m['file']}"); continue
                dst = os.path.join(labels, f"{room['slug']}-{m['file']}")
                try:
                    with Image.open(src) as im:
                        im = ImageOps.exif_transpose(im).convert("RGB"); im.thumbnail((2000, 2000)); im.save(dst, "JPEG", quality=88)
                except Exception: shutil.copyfile(src, dst)
                lines.append(f"- photo `{dst}`")
        else:
            allm = frames + photos
            per = COLS * ROWS
            for si in range(0, len(allm), per):
                chunk = allm[si:si + per]
                paths = [os.path.join(rdir, m["file"]) for m in chunk]
                labs = [(f"video {int((m.get('t') or 0)//60)}:{int((m.get('t') or 0)%60):02d}" if m.get("kind") == "frame" else "photo") + f"  {m['file']}" for m in chunk]
                sp = os.path.join(sheets, f"{room['slug']}-{si//per + 1}.jpg")
                sheet(paths, labs, sp)
                lines.append(f"- sheet `{sp}`: " + ", ".join(m["file"] for m in chunk))
            lines.append(f"Full-size frames are in `{rdir}/` (open one only when a label needs reading).")
        lines.append("")
    lines.insert(5, f"Rooms with images: {room_count} · images: {total_imgs}")
    with open(os.path.join(out, "index.md"), "w") as fh: fh.write("\n".join(lines))
    print(json.dumps({"job": jid, "rooms": room_count, "images": total_imgs, "index": os.path.join(out, "index.md")}))

if __name__ == "__main__":
    main()
