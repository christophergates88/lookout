/**
 * Roomprint — self-recorded home contents records.
 *
 * One Cloudflare Worker serves the public site, the customer walkthrough app,
 * the record download page, and a small JSON API. Customer files (video frames
 * and photos) are committed to a private GitHub repository, one branch per home,
 * where the hourly record-builder picks them up. Job state lives in KV.
 *
 * Routes
 *   GET  /                          public site
 *   GET  /start                     start a record (name, email, plan)
 *   POST /api/start                 → { id, url }
 *   GET  /w/:id/:key                walkthrough app (private link)
 *   GET  /api/job/:id?k=            job state + record status
 *   POST /api/job/:id/room?k=       { name } add a room
 *   POST /api/job/:id/room/del?k=   { slug } remove an empty room
 *   POST /api/job/:id/notes?k=      { slug, notes }
 *   PUT  /api/job/:id/upload?k=&room=&kind=frame|photo&t=&w=&h=   JPEG body
 *   POST /api/job/:id/media/del?k=  { slug, file }
 *   POST /api/job/:id/done?k=       walkthrough complete → ready for the builder
 *   POST /api/job/:id/reopen?k=
 *   POST /api/job/:id/paid-note?k=  { text }  "I paid under another email"
 *   GET  /r/:id/:key                record page (summary, pay, download)
 *   GET  /api/job/:id/file/:name?k= record download (after payment)
 *   GET  /pay/:id/:key              → PayPal checkout
 *   GET  /privacy, /health
 */
import SITE from "../pages/site.html";
import START from "../pages/start.html";
import APP from "../pages/app.html";
import PRIVACY from "../pages/privacy.html";
import ICON from "../pages/icon-180.png";

const MAX_IMAGE_BYTES = 2_500_000;
const MAX_MEDIA_PER_ROOM = 400;
const MAX_MEDIA_PER_JOB = 3000;
const MAX_ROOMS = 40;
const STATUS_CACHE_SECONDS = 45;

const ROOM_SETS = {
  home: ["Living room", "Kitchen", "Dining room", "Primary bedroom", "Bedroom 2", "Bathroom", "Office or den", "Laundry", "Garage", "Closets", "Outdoors and patio"],
  apartment: ["Living room", "Kitchen", "Bedroom", "Bathroom", "Closets", "Storage"],
  full: ["Living room", "Kitchen", "Dining room", "Primary bedroom", "Bedroom 2", "Bedroom 3", "Bathroom", "Office or den", "Laundry", "Garage", "Closets", "Attic or basement", "Shed and outbuildings", "Outdoors and patio", "Dock and boat"],
};
const SPECIAL_SECTIONS = [
  { name: "Big-ticket labels", kind: "labels", hint: "Close-up photos of the label on your TV, fridge, washer and dryer, mower, tools, bikes, kayaks, anything over $300. The label has the model and serial number." },
  { name: "Receipts and appraisals", kind: "receipts", hint: "Optional. Photos of receipts, appraisals or warranty cards you still have. These make the record much stronger." },
];

export default {
  async fetch(request, env, ctx) {
    try {
      return await route(request, env, ctx);
    } catch (e) {
      console.error("unhandled", e && e.stack || e);
      return json({ error: "server_error", message: String(e && e.message || e) }, 500);
    }
  },
};

async function route(request, env, ctx) {
  const url = new URL(request.url);
  const p = url.pathname.replace(/\/+$/, "") || "/";
  const m = request.method;

  if (p === "/" && m === "GET") return html(fill(SITE, siteVars(env, url)));
  if (p === "/start" && m === "GET") return html(fill(START, siteVars(env, url)));
  if (p === "/privacy" && m === "GET") return html(fill(PRIVACY, siteVars(env, url)));
  if (p === "/icon-180.png" && m === "GET") return new Response(ICON, { headers: { "content-type": "image/png", "cache-control": "public, max-age=604800" } });
  if (p === "/health") return json({ ok: true, time: new Date().toISOString(), github: env.MOCK_GITHUB === "1" ? "mock" : (env.GH_TOKEN ? "configured" : "missing token") });

  if (p === "/api/start" && m === "POST") return apiStart(request, env, url);

  let r;
  if ((r = p.match(/^\/w\/([A-Z0-9]{6,12})\/([A-Za-z0-9]{16,48})$/)) && m === "GET") {
    const job = await loadJob(env, r[1]);
    if (!job || job.key !== r[2]) return html(fill(START, { ...siteVars(env, url), BAD_LINK: "1" }), 404);
    return html(fill(APP, { ...siteVars(env, url), JOB_ID: job.id, JOB_KEY: job.key }), 200, { "Referrer-Policy": "no-referrer", "Cache-Control": "no-store" });
  }
  if ((r = p.match(/^\/r\/([A-Z0-9]{6,12})\/([A-Za-z0-9]{16,48})$/)) && m === "GET") {
    // The record page is the walkthrough app in its "sent" state.
    const job = await loadJob(env, r[1]);
    if (!job || job.key !== r[2]) return html(fill(START, { ...siteVars(env, url), BAD_LINK: "1" }), 404);
    return html(fill(APP, { ...siteVars(env, url), JOB_ID: job.id, JOB_KEY: job.key }), 200, { "Referrer-Policy": "no-referrer", "Cache-Control": "no-store" });
  }
  if ((r = p.match(/^\/pay\/([A-Z0-9]{6,12})\/([A-Za-z0-9]{16,48})$/)) && m === "GET") {
    const job = await loadJob(env, r[1]);
    if (!job || job.key !== r[2]) return html(fill(START, { ...siteVars(env, url), BAD_LINK: "1" }), 404);
    const link = payLink(env, url, job);
    if (!link) return Response.redirect(recordUrl(url, job), 302);
    return Response.redirect(link, 302);
  }

  if ((r = p.match(/^\/api\/job\/([A-Z0-9]{6,12})(?:\/(.*))?$/))) {
    const job = await loadJob(env, r[1]);
    const key = url.searchParams.get("k") || "";
    if (!job || job.key !== key) return json({ error: "not_found" }, 404);
    const sub = r[2] || "";
    if (sub === "" && m === "GET") return apiJob(env, url, job);
    if (sub === "room" && m === "POST") return apiAddRoom(request, env, job);
    if (sub === "room/del" && m === "POST") return apiDelRoom(request, env, job);
    if (sub === "notes" && m === "POST") return apiNotes(request, env, job);
    if (sub === "upload" && m === "PUT") return apiUpload(request, env, url, job);
    if (sub === "media/del" && m === "POST") return apiDelMedia(request, env, job);
    if (sub === "done" && m === "POST") return apiDone(env, url, job);
    if (sub === "reopen" && m === "POST") return apiReopen(env, url, job);
    if (sub === "paid-note" && m === "POST") return apiPaidNote(request, env, url, job);
    if (sub.startsWith("file/") && m === "GET") return apiFile(env, job, sub.slice(5));
    return json({ error: "no_such_route" }, 404);
  }

  return html(fill(SITE, siteVars(env, url)), 404);
}

/* ------------------------------------------------------------------ pages */

function siteVars(env, url) {
  return {
    ORIGIN: url.origin,
    BUSINESS_NAME: env.BUSINESS_NAME || "Roomprint",
    BUSINESS_EMAIL: env.BUSINESS_EMAIL || "",
    PRICE_HOME: env.PRICE_HOME || "199",
    PRICE_FULL: env.PRICE_FULL || "299",
    PRICE_UPDATE: env.PRICE_UPDATE || "59",
    PAY_READY: (env.PAYPAL_EMAIL || env.PAYPAL_ME) ? "1" : "",
    BAD_LINK: "",
    JOB_ID: "",
    JOB_KEY: "",
  };
}

function fill(tpl, vars) {
  return tpl.replace(/\{\{([A-Z_]+)\}\}/g, (_, k) => (k in vars ? escapeHtml(String(vars[k])) : ""));
}

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function html(body, status = 200, extra = {}) {
  return new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8", "x-content-type-options": "nosniff", ...extra } });
}

function json(obj, status = 200, extra = {}) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra } });
}

/* ------------------------------------------------------------------- jobs */

const ID_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const KEY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

function randomString(alphabet, n) {
  const bytes = new Uint8Array(n);
  crypto.getRandomValues(bytes);
  let s = "";
  for (let i = 0; i < n; i++) s += alphabet[bytes[i] % alphabet.length];
  return s;
}

async function loadJob(env, id) {
  if (!id) return null;
  return env.JOBS.get("job:" + id, "json");
}

async function saveJob(env, job) {
  job.updated = new Date().toISOString();
  await env.JOBS.put("job:" + job.id, JSON.stringify(job));
  return job;
}

function slugify(name) {
  return String(name).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32) || "room";
}

function uniqueSlug(job, base) {
  let s = base, i = 2;
  while (job.rooms.some((r) => r.slug === s)) { s = base + "-" + i; i++; }
  return s;
}

function makeRoom(job, name, kind, hint) {
  return { name: String(name).trim().slice(0, 48), slug: uniqueSlug(job, slugify(name)), kind: kind || "room", hint: hint || "", notes: "", media: [], done: false, counter: 0, order: job.rooms.length + 1 };
}

function planInfo(env, plan) {
  const plans = {
    home: { plan: "home", label: "Home Record", price: Number(env.PRICE_HOME || 199), rooms: ROOM_SETS.home },
    full: { plan: "full", label: "Full Property Record", price: Number(env.PRICE_FULL || 299), rooms: ROOM_SETS.full },
    apartment: { plan: "apartment", label: "Home Record (apartment or condo)", price: Number(env.PRICE_HOME || 199), rooms: ROOM_SETS.apartment },
  };
  return plans[plan] || plans.home;
}

function publicJob(job, extra = {}) {
  const { key, counter, ...rest } = job;
  const rooms = job.rooms.map(({ counter, ...r }) => ({ ...r, media: r.media.map((m) => ({ file: m.file, kind: m.kind, t: m.t, w: m.w, h: m.h, added: m.added })) }));
  return { ...rest, rooms, totalImages: countMedia(job), ...extra };
}

function countMedia(job) {
  return job.rooms.reduce((n, r) => n + r.media.length, 0);
}

async function readJsonBody(request, limit = 20_000) {
  const text = await request.text();
  if (text.length > limit) throw new Error("body too large");
  try { return JSON.parse(text || "{}"); } catch { return {}; }
}

/* -------------------------------------------------------------------- API */

async function apiStart(request, env, url) {
  const b = await readJsonBody(request);
  const name = String(b.name || "").trim().slice(0, 80);
  const email = String(b.email || "").trim().slice(0, 120);
  const phone = String(b.phone || "").trim().slice(0, 32);
  const town = String(b.town || "").trim().slice(0, 60);
  const homeName = String(b.homeName || "").trim().slice(0, 80);
  if (!name) return json({ error: "missing_name", message: "Please add your name." }, 400);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "bad_email", message: "Please add a working email address; that's where your record goes." }, 400);
  const pi = planInfo(env, b.plan);

  let id;
  for (let i = 0; i < 5; i++) { id = randomString(ID_ALPHABET, 8); if (!(await loadJob(env, id))) break; }
  const job = {
    id, key: randomString(KEY_ALPHABET, 28),
    name, email, phone, town, homeName: homeName || (name.split(" ")[0] ? "The " + lastName(name) + " home" : "My home"),
    plan: pi.plan, planLabel: pi.label, price: pi.price,
    status: "uploading", created: new Date().toISOString(), readyAt: "", paidNote: "",
    rooms: [], counter: 0,
  };
  for (const r of pi.rooms) job.rooms.push(makeRoom(job, r));
  for (const s of SPECIAL_SECTIONS) job.rooms.push(makeRoom(job, s.name, s.kind, s.hint));
  await saveJob(env, job);

  // Record the job in GitHub right away so the builder and the morning check can see it.
  const gh = github(env);
  try {
    await gh.ensureBranch(branchOf(job));
    await gh.putFile(branchOf(job), `jobs/${job.id}/job.json`, JSON.stringify(jobManifest(job, url), null, 2), `Start home ${job.id}`);
  } catch (e) {
    console.error("github at start", e && e.message);
    job.githubError = String(e && e.message || e).slice(0, 200);
    await saveJob(env, job);
  }
  return json({ id: job.id, url: walkUrl(url, job), job: publicJob(job) });
}

function lastName(n) { const parts = n.trim().split(/\s+/); return parts[parts.length - 1]; }
function branchOf(job) { return "job-" + job.id; }
function walkUrl(url, job) { return `${url.origin}/w/${job.id}/${job.key}`; }
function recordUrl(url, job) { return `${url.origin}/r/${job.id}/${job.key}`; }

function jobManifest(job, url) {
  return {
    id: job.id, name: job.name, email: job.email, phone: job.phone, town: job.town, homeName: job.homeName,
    plan: job.plan, planLabel: job.planLabel, price: job.price,
    status: job.status, created: job.created, readyAt: job.readyAt, paidNote: job.paidNote || "",
    walkthroughUrl: walkUrl(url, job), recordUrl: recordUrl(url, job), payUrl: `${url.origin}/pay/${job.id}/${job.key}`,
    rooms: job.rooms.map((r) => ({ name: r.name, slug: r.slug, kind: r.kind, notes: r.notes, done: !!r.done, media: r.media.map((m) => ({ file: m.file, kind: m.kind, t: m.t, w: m.w, h: m.h, added: m.added })) })),
    totalImages: countMedia(job),
  };
}

async function apiJob(env, url, job) {
  const record = await recordStatus(env, job);
  return json({ job: publicJob(job), record, walkthroughUrl: walkUrl(url, job), recordUrl: recordUrl(url, job), payUrl: `${url.origin}/pay/${job.id}/${job.key}`, payReady: !!(env.PAYPAL_EMAIL || env.PAYPAL_ME) });
}

async function apiAddRoom(request, env, job) {
  if (job.status !== "uploading") return json({ error: "locked", message: "This walkthrough was sent already. Tap “Add more” first." }, 409);
  const b = await readJsonBody(request);
  const name = String(b.name || "").trim().slice(0, 48);
  if (!name) return json({ error: "missing_name" }, 400);
  if (job.rooms.length >= MAX_ROOMS) return json({ error: "too_many_rooms" }, 400);
  const room = makeRoom(job, name);
  job.rooms.push(room);
  await saveJob(env, job);
  return json({ ok: true, room: { ...room, counter: undefined }, job: publicJob(job) });
}

async function apiDelRoom(request, env, job) {
  if (job.status !== "uploading") return json({ error: "locked" }, 409);
  const b = await readJsonBody(request);
  const i = job.rooms.findIndex((r) => r.slug === b.slug);
  if (i < 0) return json({ error: "no_such_room" }, 404);
  if (job.rooms[i].media.length) return json({ error: "not_empty", message: "Remove its images first." }, 400);
  job.rooms.splice(i, 1);
  await saveJob(env, job);
  return json({ ok: true, job: publicJob(job) });
}

async function apiNotes(request, env, job) {
  const b = await readJsonBody(request, 60_000);
  const room = job.rooms.find((r) => r.slug === b.slug);
  if (!room) return json({ error: "no_such_room" }, 404);
  room.notes = String(b.notes || "").slice(0, 4000);
  if (typeof b.done === "boolean") room.done = b.done;
  await saveJob(env, job);
  return json({ ok: true });
}

async function apiUpload(request, env, url, job) {
  if (job.status !== "uploading") return json({ error: "locked", message: "This walkthrough was sent already. Tap “Add more” first." }, 409);
  const slug = url.searchParams.get("room") || "";
  const kind = url.searchParams.get("kind") === "frame" ? "frame" : "photo";
  const t = Math.max(0, Math.round(Number(url.searchParams.get("t") || 0) * 10) / 10);
  const w = Math.min(10000, Math.max(0, parseInt(url.searchParams.get("w") || "0", 10) || 0));
  const h = Math.min(10000, Math.max(0, parseInt(url.searchParams.get("h") || "0", 10) || 0));
  const room = job.rooms.find((r) => r.slug === slug);
  if (!room) return json({ error: "no_such_room" }, 404);
  if (room.media.length >= MAX_MEDIA_PER_ROOM) return json({ error: "room_full", message: "That's plenty for one room." }, 400);
  if (countMedia(job) >= MAX_MEDIA_PER_JOB) return json({ error: "job_full", message: "This home has reached the image limit." }, 400);
  const ct = (request.headers.get("content-type") || "").toLowerCase();
  if (!ct.startsWith("image/jpeg")) return json({ error: "bad_type", message: "Send a JPEG." }, 415);
  const buf = await request.arrayBuffer();
  if (buf.byteLength < 2000) return json({ error: "too_small" }, 400);
  if (buf.byteLength > MAX_IMAGE_BYTES) return json({ error: "too_large", message: "That image is too large." }, 413);
  const bytes = new Uint8Array(buf);
  if (!(bytes[0] === 0xff && bytes[1] === 0xd8)) return json({ error: "bad_type", message: "That isn't a JPEG." }, 415);

  room.counter = (room.counter || 0) + 1;
  const file = `${kind}-${String(room.counter).padStart(3, "0")}.jpg`;
  const path = `jobs/${job.id}/${room.slug}/${file}`;
  const gh = github(env);
  try {
    if (!job.branchReady) { await gh.ensureBranch(branchOf(job)); job.branchReady = true; }
    await gh.putFile(branchOf(job), path, bytes, `${job.id} ${room.slug} ${file}`);
  } catch (e) {
    console.error("github upload", e && e.message);
    job.branchReady = false;
    return json({ error: "storage", message: "Upload failed on our side. Please try again in a moment.", detail: String(e && e.message || e).slice(0, 160) }, 502);
  }
  const m = { file, kind, t, w, h, added: new Date().toISOString(), bytes: buf.byteLength };
  room.media.push(m);
  delete job.githubError;
  await saveJob(env, job);
  return json({ ok: true, file, count: room.media.length, total: countMedia(job) });
}

async function apiDelMedia(request, env, job) {
  if (job.status !== "uploading") return json({ error: "locked" }, 409);
  const b = await readJsonBody(request);
  const room = job.rooms.find((r) => r.slug === b.slug);
  if (!room) return json({ error: "no_such_room" }, 404);
  const i = room.media.findIndex((m) => m.file === b.file);
  if (i < 0) return json({ error: "no_such_file" }, 404);
  room.media.splice(i, 1);
  await saveJob(env, job);
  // The file stays in the repository until the builder cleans up; the record is built only from this list.
  return json({ ok: true, count: room.media.length, total: countMedia(job) });
}

async function apiDone(env, url, job) {
  if (countMedia(job) === 0) return json({ error: "empty", message: "Add at least one room's video or photos first." }, 400);
  job.status = "ready";
  job.readyAt = new Date().toISOString();
  await saveJob(env, job);
  const gh = github(env);
  try {
    await gh.ensureBranch(branchOf(job));
    await gh.putFile(branchOf(job), `jobs/${job.id}/job.json`, JSON.stringify(jobManifest(job, url), null, 2), `Home ${job.id} ready for the record`);
  } catch (e) {
    console.error("github done", e && e.message);
    job.githubError = String(e && e.message || e).slice(0, 200);
    await saveJob(env, job);
    return json({ error: "storage", message: "We saved your walkthrough but couldn't hand it to the builder. Please tap Send again in a minute." }, 502);
  }
  await env.JOBS.delete("st:" + job.id);
  return json({ ok: true, job: publicJob(job) });
}

async function apiReopen(env, url, job) {
  const record = await recordStatus(env, job);
  if (record && ["built", "paid", "delivered"].includes(record.state)) return json({ error: "already_built", message: "Your record is already built. Reply to our email to add rooms." }, 409);
  job.status = "uploading";
  await saveJob(env, job);
  const gh = github(env);
  try { await gh.putFile(branchOf(job), `jobs/${job.id}/job.json`, JSON.stringify(jobManifest(job, url), null, 2), `Home ${job.id} reopened`); } catch (e) { console.error("github reopen", e && e.message); }
  return json({ ok: true, job: publicJob(job) });
}

async function apiPaidNote(request, env, url, job) {
  const b = await readJsonBody(request);
  job.paidNote = String(b.text || "").slice(0, 300);
  await saveJob(env, job);
  const gh = github(env);
  try { await gh.putFile(branchOf(job), `jobs/${job.id}/job.json`, JSON.stringify(jobManifest(job, url), null, 2), `Home ${job.id} payment note`); } catch (e) { console.error("github note", e && e.message); }
  return json({ ok: true });
}

/* The builder writes jobs/<id>/record/status.json on the job branch:
   { state: "building" | "built" | "needs_more" | "paid" | "delivered", items, total, rooms, builtAt, paidAt,
     password (PDF password), message (shown to the customer), files: ["record.pdf", "record.csv"] } */
async function recordStatus(env, job) {
  const cacheKey = "st:" + job.id;
  const cached = await env.JOBS.get(cacheKey, "json");
  if (cached && cached._at && Date.now() - cached._at < STATUS_CACHE_SECONDS * 1000) return cached.value;
  let value = null;
  try {
    const txt = await github(env).getFileText(branchOf(job), `jobs/${job.id}/record/status.json`);
    value = txt ? JSON.parse(txt) : null;
  } catch (e) {
    console.error("status read", e && e.message);
    if (cached) return cached.value;
  }
  await env.JOBS.put(cacheKey, JSON.stringify({ _at: Date.now(), value }), { expirationTtl: 3600 });
  return value;
}

async function apiFile(env, job, name) {
  if (!/^[a-z0-9._-]{1,64}$/i.test(name)) return json({ error: "bad_name" }, 400);
  const st = await recordStatus(env, job);
  if (!st || !["paid", "delivered"].includes(st.state)) return json({ error: "not_unlocked", message: "The record unlocks after payment." }, 403);
  if (!(st.files || []).includes(name)) return json({ error: "no_such_file" }, 404);
  const res = await github(env).getFileRaw(branchOf(job), `jobs/${job.id}/record/${name}`);
  if (!res) return json({ error: "missing", message: "That file isn't there yet. Try again in a few minutes." }, 404);
  const types = { pdf: "application/pdf", csv: "text/csv; charset=utf-8", json: "application/json", zip: "application/zip" };
  const ext = name.split(".").pop().toLowerCase();
  const nice = `${(job.homeName || "Home").replace(/[^A-Za-z0-9 ]+/g, "")} Record.${ext}`;
  return new Response(res.body, { status: 200, headers: { "content-type": types[ext] || "application/octet-stream", "content-disposition": `attachment; filename="${nice}"`, "cache-control": "no-store", "referrer-policy": "no-referrer" } });
}

function payLink(env, url, job) {
  const amount = Number(job.price || 0).toFixed(2);
  const back = recordUrl(url, job);
  if (env.PAYPAL_EMAIL) {
    // invoice and custom both carry the home id, so the builder can match the payment in PayPal's transaction list.
    const q = new URLSearchParams({ cmd: "_xclick", business: env.PAYPAL_EMAIL, item_name: `${env.BUSINESS_NAME || "Roomprint"} ${job.planLabel} (home ${job.id})`, item_number: job.id, invoice: job.id, custom: job.id, amount, currency_code: "USD", no_shipping: "1", no_note: "1", return: back, cancel_return: back });
    return "https://www.paypal.com/cgi-bin/webscr?" + q.toString();
  }
  if (env.PAYPAL_ME) return `https://www.paypal.me/${encodeURIComponent(env.PAYPAL_ME)}/${amount}USD`;
  return "";
}

/* ----------------------------------------------------------------- GitHub */

function github(env) {
  if (env.MOCK_GITHUB === "1") return mockGithub(env);
  const owner = env.GH_OWNER, repo = env.GH_REPO, base = env.GH_BRANCH_BASE || "main";
  const token = env.GH_TOKEN;
  const api = "https://api.github.com";
  const headers = (extra = {}) => ({ authorization: "Bearer " + token, accept: "application/vnd.github+json", "user-agent": "roomprint-worker", "x-github-api-version": "2022-11-28", ...extra });
  if (!token) {
    const err = () => { throw new Error("GH_TOKEN secret is not set in the Worker"); };
    return { ensureBranch: err, putFile: err, getFileText: async () => null, getFileRaw: async () => null };
  }
  async function call(method, path, body, extraHeaders) {
    const res = await fetch(api + path, { method, headers: headers(extraHeaders), body: body == null ? undefined : JSON.stringify(body) });
    return res;
  }
  async function branchExists(branch) {
    const r = await call("GET", `/repos/${owner}/${repo}/git/ref/heads/${encodeURIComponent(branch)}`);
    return r.status === 200;
  }
  return {
    async ensureBranch(branch) {
      if (await branchExists(branch)) return;
      const baseRef = await call("GET", `/repos/${owner}/${repo}/git/ref/heads/${encodeURIComponent(base)}`);
      if (baseRef.status !== 200) throw new Error(`base branch ${base} not found (${baseRef.status}) — does the uploads repository have a first commit?`);
      const sha = (await baseRef.json()).object.sha;
      const r = await call("POST", `/repos/${owner}/${repo}/git/refs`, { ref: `refs/heads/${branch}`, sha });
      if (r.status !== 201 && r.status !== 422) throw new Error(`could not create branch (${r.status}): ${(await r.text()).slice(0, 200)}`);
    },
    async putFile(branch, path, content, message) {
      const b64 = typeof content === "string" ? b64encode(new TextEncoder().encode(content)) : b64encode(content);
      const p = `/repos/${owner}/${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}`;
      let sha;
      for (let attempt = 0; attempt < 4; attempt++) {
        const body = { message, content: b64, branch };
        if (sha) body.sha = sha;
        const r = await call("PUT", p, body);
        if (r.status === 200 || r.status === 201) return (await r.json()).content.sha;
        const txt = await r.text();
        if (r.status === 422 && /sha.*wasn.t supplied|"sha" wasn't supplied/i.test(txt)) {
          const g = await call("GET", p + `?ref=${encodeURIComponent(branch)}`);
          if (g.status === 200) { sha = (await g.json()).sha; continue; }
        }
        if ((r.status === 409 || r.status === 422 || r.status >= 500) && attempt < 3) { await sleep(300 * (attempt + 1)); continue; }
        if (r.status === 401 || r.status === 403) throw new Error(`GitHub refused the token (${r.status}). Check the GH_TOKEN secret and its permissions.`);
        if (r.status === 404) throw new Error(`GitHub repository ${owner}/${repo} not found for this token (404).`);
        throw new Error(`GitHub ${r.status}: ${txt.slice(0, 160)}`);
      }
      throw new Error("GitHub kept rejecting the write");
    },
    async getFileText(branch, path) {
      const r = await call("GET", `/repos/${owner}/${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${encodeURIComponent(branch)}`, null, { accept: "application/vnd.github.raw+json" });
      if (r.status === 404) return null;
      if (r.status !== 200) throw new Error(`GitHub read ${r.status}`);
      return r.text();
    },
    async getFileRaw(branch, path) {
      const r = await call("GET", `/repos/${owner}/${repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${encodeURIComponent(branch)}`, null, { accept: "application/vnd.github.raw+json" });
      if (r.status === 404) return null;
      if (r.status !== 200) throw new Error(`GitHub read ${r.status}`);
      return r;
    },
  };
}

/* Local testing only: files live in KV. */
function mockGithub(env) {
  return {
    async ensureBranch() {},
    async putFile(branch, path, content) {
      const bytes = typeof content === "string" ? new TextEncoder().encode(content) : content;
      await env.JOBS.put(`mock:${branch}:${path}`, b64encode(bytes));
      return "mock";
    },
    async getFileText(branch, path) {
      const v = await env.JOBS.get(`mock:${branch}:${path}`);
      return v == null ? null : new TextDecoder().decode(b64decode(v));
    },
    async getFileRaw(branch, path) {
      const v = await env.JOBS.get(`mock:${branch}:${path}`);
      return v == null ? null : new Response(b64decode(v));
    },
  };
}

function b64encode(bytes) {
  let s = "";
  const CH = 0x8000;
  for (let i = 0; i < bytes.length; i += CH) s += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
  return btoa(s);
}
function b64decode(s) {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
