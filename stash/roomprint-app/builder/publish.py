#!/usr/bin/env python3
"""Write record files and status to a home's branch and push.

Usage:
  python3 publish.py UPLOADS_REPO_DIR JOB_ID --state built --from WORK_OUT_DIR [--password 1234] [--message "..."] \
          --items 212 --rooms 11 --total 48300
  python3 publish.py UPLOADS_REPO_DIR JOB_ID --state needs_more --message "The kitchen video was too dark..."
  python3 publish.py UPLOADS_REPO_DIR JOB_ID --state paid --txn 1AB23456CD789 [--paid-at ISO]
  python3 publish.py UPLOADS_REPO_DIR JOB_ID --delivered           (marks deliveredAt on the current state)
  python3 publish.py UPLOADS_REPO_DIR JOB_ID --cleanup             (deletes raw frames/photos, keeps record/)

The branch job-<ID> is checked out, files under jobs/<ID>/record/ are updated, status.json is merged
(existing fields kept unless overridden), then committed and pushed. Prints the final status.json.
"""
import argparse, datetime, json, os, shutil, subprocess, sys

def git(repo, *args, check=True):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout

def now(): return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo"); ap.add_argument("job")
    ap.add_argument("--state"); ap.add_argument("--from", dest="src"); ap.add_argument("--password"); ap.add_argument("--message", default=None)
    ap.add_argument("--items", type=int); ap.add_argument("--rooms", type=int); ap.add_argument("--total", type=int)
    ap.add_argument("--txn"); ap.add_argument("--paid-at"); ap.add_argument("--delivered", action="store_true"); ap.add_argument("--cleanup", action="store_true")
    ap.add_argument("--welcome", action="store_true", help="record that the welcome email went out")
    ap.add_argument("--reminder", action="store_true", help="count one payment reminder sent")
    a = ap.parse_args()
    repo, jid = a.repo, a.job; branch = f"job-{jid}"
    git(repo, "fetch", "origin")
    git(repo, "checkout", "-q", "-B", branch, f"origin/{branch}")
    git(repo, "config", "user.name", "Roomprint builder"); git(repo, "config", "user.email", "builder@roomprint.local")
    rec = os.path.join(repo, "jobs", jid, "record"); os.makedirs(rec, exist_ok=True)
    sp = os.path.join(rec, "status.json")
    st = {}
    if os.path.exists(sp):
        with open(sp) as f: st = json.load(f)
    if a.src:
        files = []
        for name in ("record.pdf", "record.csv", "summary.json", "record.json"):
            p = os.path.join(a.src, name)
            if os.path.exists(p):
                shutil.copyfile(p, os.path.join(rec, name)); files.append(name)
        st["files"] = [f for f in ("record.pdf", "record.csv") if f in files]
        if "summary.json" in files:
            with open(os.path.join(a.src, "summary.json")) as f: summ = json.load(f)
            st.setdefault("items", summ.get("items")); st.setdefault("rooms", summ.get("rooms")); st.setdefault("total", summ.get("total"))
            st["items"], st["rooms"], st["total"] = summ.get("items"), summ.get("rooms"), summ.get("total")
    if a.items is not None: st["items"] = a.items
    if a.rooms is not None: st["rooms"] = a.rooms
    if a.total is not None: st["total"] = a.total
    if a.password: st["password"] = a.password
    if a.message is not None: st["message"] = a.message
    if a.state:
        st["state"] = a.state
        if a.state in ("built", "needs_more"): st["builtAt"] = now()
        if a.state == "paid":
            st["paidAt"] = a.paid_at or now()
            if a.txn: st["txn"] = a.txn
    if a.delivered: st["deliveredAt"] = now(); st["state"] = "delivered" if st.get("state") in ("paid", "delivered") else st.get("state")
    if a.welcome:
        st["welcomeAt"] = now(); st.setdefault("state", "received")
    if a.reminder:
        st["reminders"] = int(st.get("reminders", 0)) + 1; st["lastReminderAt"] = now()
    if a.cleanup:
        jdir = os.path.join(repo, "jobs", jid)
        for d in os.listdir(jdir):
            p = os.path.join(jdir, d)
            if os.path.isdir(p) and d != "record": shutil.rmtree(p)
        st["cleanedAt"] = now()
    st["updatedAt"] = now()
    with open(sp, "w") as f: json.dump(st, f, indent=2)
    git(repo, "add", "-A", f"jobs/{jid}")
    if git(repo, "status", "--porcelain", f"jobs/{jid}").strip():
        git(repo, "commit", "-q", "-m", f"Home {jid}: {a.state or ('delivered' if a.delivered else 'cleanup' if a.cleanup else 'welcome' if a.welcome else 'reminder' if a.reminder else 'update')}")
        git(repo, "push", "-q", "origin", branch)
    print(json.dumps(st, indent=2))

if __name__ == "__main__":
    main()
