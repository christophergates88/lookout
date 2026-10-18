# Roomprint

Self-recorded home contents records. A homeowner walks through their home with their phone;
the app uploads the sharpest video frames and label photos; an hourly agent builds an itemized,
claim-ready record, collects payment and delivers it. The owner (Christopher) does nothing
unless HQ says "needs you".

## How it fits together

```
customer phone ──► Cloudflare Worker (this repo) ──► GitHub repo roomprint-uploads (private)
   site, start,        serves pages + JSON API,          one branch per home: job-<ID>
   walkthrough app     stores job state in KV            jobs/<ID>/job.json, <room>/*.jpg, record/*
                                                               │
                                              hourly Claude scheduled task ("Record builder")
                                              clones both repos, builds the record with
                                              builder/*.py, emails via Gmail, checks PayPal,
                                              logs to Roomprint HQ
```

- `src/index.js` — the Worker (routes, job API, GitHub Contents API client, PayPal link).
- `pages/` — site, start page, walkthrough app, privacy page, home-screen icon.
- `builder/` — `jobs.py` (what each home needs), `prepare.py` (contact sheets), `make_record.py`
  (PDF + CSV + summary), `publish.py` (write results to the home's branch), `emails.md`
  (customer emails), `PROMPT.md` (the scheduled task's instructions).
- `test/` — `serve.mjs` runs the Worker locally with an in-memory KV and a GitHub mock;
  `e2e.py` drives the whole customer flow in headless Chromium.

## One-time setup (about 10 minutes)

1. **GitHub**: two private repositories, `roomprint-app` (this code) and `roomprint-uploads`
   (customer files; must have at least one commit on `main`).
2. **GitHub token for the Worker**: GitHub → Settings → Developer settings → Personal access
   tokens → Fine-grained tokens → Generate new token. Name "Roomprint uploader", expiration
   1 year (set a reminder), Repository access: *Only select repositories* → `roomprint-uploads`,
   Permissions → Repository permissions → **Contents: Read and write**. Copy the token.
3. **Cloudflare**: dash.cloudflare.com → Workers & Pages → Create → **Import a repository** →
   connect GitHub → choose `roomprint-app` → Deploy (it runs `npx wrangler deploy` from
   `wrangler.toml`). Then open the Worker → Settings → Variables and Secrets → Add →
   type **Secret**, name `GH_TOKEN`, paste the token → Deploy.
   In the same place set the plain variables that are blank in `wrangler.toml`
   (or edit the file): `BUSINESS_EMAIL`, and `PAYPAL_EMAIL` (the email of the PayPal account
   that receives payments) or `PAYPAL_ME`.
4. **Check**: open `https://<worker>.workers.dev/health` — it should say `"github":"configured"`.
   Start a test home, record a room, send it, and look for the branch `job-<ID>` in
   `roomprint-uploads`.
5. **Builder**: create the hourly scheduled task with the prompt in `builder/PROMPT.md`.

## Local testing

```
node test/serve.mjs 8788        # Worker with in-memory KV + GitHub mock
python3 test/e2e.py             # full customer flow in headless Chromium
```

## Data on a home's branch

```
jobs/<ID>/job.json              written by the Worker at start, on send, on reopen
jobs/<ID>/<room-slug>/frame-001.jpg, photo-001.jpg ...
jobs/<ID>/record/status.json    written by the builder: state received|built|needs_more|paid|delivered,
                                items, rooms, total, password, files, builtAt, paidAt, deliveredAt, ...
jobs/<ID>/record/record.pdf, record.csv, summary.json, record.json
```

The customer's page reads `status.json` (cached 45 s) to show "building / ready / unlocked".
