#!/usr/bin/env python3
"""List homes in the uploads repository and what each one needs.

Usage: python3 jobs.py UPLOADS_REPO_DIR [--json]

For every remote branch job-<ID> it reads jobs/<ID>/job.json and jobs/<ID>/record/status.json straight
from git (no checkout) and prints one line per home with the action the builder should take:
  build     customer sent the walkthrough, no record yet
  rebuild   customer reopened and sent again after a record was built (status.json older than job.json's readyAt)
  payment   record built, waiting for payment (check PayPal)
  deliver   paid, delivery email not yet marked sent
  cleanup   delivered 30+ days ago and raw frames still present
  wait      customer still uploading / nothing to do
"""
import datetime, json, subprocess, sys

def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)

def show(repo, branch, path):
    r = git(repo, "show", f"origin/{branch}:{path}")
    return r.stdout if r.returncode == 0 else None

def main():
    repo = sys.argv[1]; as_json = "--json" in sys.argv
    git(repo, "fetch", "--prune", "origin")
    r = git(repo, "branch", "-r", "--format=%(refname:short)")
    branches = [b.strip() for b in r.stdout.splitlines() if b.strip().startswith("origin/job-")]
    now = datetime.datetime.now(datetime.timezone.utc)
    out = []
    for b in branches:
        branch = b.split("/", 1)[1]; jid = branch[4:]
        jt = show(repo, branch, f"jobs/{jid}/job.json")
        if not jt: continue
        try: job = json.loads(jt)
        except Exception: continue
        st_txt = show(repo, branch, f"jobs/{jid}/record/status.json")
        st = json.loads(st_txt) if st_txt else None
        state = (st or {}).get("state")
        action = "wait"
        if job.get("status") == "ready":
            if not st or state in (None, "received", "building"):
                action = "build"
            elif state in ("built", "needs_more") and st.get("builtAt", "") < job.get("readyAt", "") and state != "needs_more":
                action = "rebuild"
            elif state == "needs_more" and job.get("readyAt", "") > st.get("builtAt", ""):
                action = "build"
            elif state == "built":
                action = "payment"
            elif state == "paid" and not st.get("deliveredAt"):
                action = "deliver"
            elif state in ("paid", "delivered") and st.get("deliveredAt") and not st.get("cleanedAt"):
                try:
                    d = datetime.datetime.fromisoformat(st["deliveredAt"].replace("Z", "+00:00"))
                    if (now - d).days >= 30: action = "cleanup"
                except Exception: pass
        raw = git(repo, "ls-tree", "-r", "--name-only", f"origin/{branch}", f"jobs/{jid}/").stdout.splitlines()
        images = [p for p in raw if p.lower().endswith(".jpg") and "/record/" not in p]
        out.append({"id": jid, "branch": branch, "action": action, "jobStatus": job.get("status"), "recordState": state, "name": job.get("name"), "email": job.get("email"),
                    "homeName": job.get("homeName"), "plan": job.get("planLabel"), "price": job.get("price"), "readyAt": job.get("readyAt"), "created": job.get("created"),
                    "imagesListed": job.get("totalImages"), "imagesInRepo": len(images), "paidNote": job.get("paidNote", ""), "payUrl": job.get("payUrl"), "recordUrl": job.get("recordUrl"),
                    "walkthroughUrl": job.get("walkthroughUrl"), "phone": job.get("phone", ""), "town": job.get("town", ""),
                    "welcomeAt": (st or {}).get("welcomeAt"), "builtAt": (st or {}).get("builtAt"), "paidAt": (st or {}).get("paidAt"), "deliveredAt": (st or {}).get("deliveredAt"),
                    "reminders": (st or {}).get("reminders", 0), "items": (st or {}).get("items"), "total": (st or {}).get("total"), "password": (st or {}).get("password")})
    out.sort(key=lambda j: (j["action"] == "wait", j.get("readyAt") or ""))
    if as_json: print(json.dumps(out, indent=2))
    else:
        for j in out: print(f"{j['action']:8} {j['id']}  {j['homeName'] or ''} · {j['name']} · {j['plan']} ${j['price']} · job {j['jobStatus']} · record {j['recordState']} · {j['imagesInRepo']} images · welcome {'yes' if j['welcomeAt'] else 'NO'}")
        if not out: print("no homes yet")

if __name__ == "__main__":
    main()
