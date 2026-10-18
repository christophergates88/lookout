// Local test server for the Worker: runs src/index.js under plain Node with an in-memory KV
// and the GitHub mock. Usage: node test/serve.mjs [port]
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const PORT = Number(process.argv[2] || process.env.PORT || 8788);

// Turn the Worker's text/data imports into inline constants so Node can load it.
let src = fs.readFileSync(path.join(root, "src/index.js"), "utf8");
src = src.replace(/^import\s+(\w+)\s+from\s+"\.\.\/pages\/([^"]+)";$/gm, (_, name, file) => {
  const p = path.join(root, "pages", file);
  if (file.endsWith(".png")) {
    const b = fs.readFileSync(p);
    return `const ${name} = Uint8Array.from(Buffer.from("${b.toString("base64")}", "base64")).buffer;`;
  }
  return `const ${name} = ${JSON.stringify(fs.readFileSync(p, "utf8"))};`;
});
const tmp = path.join(os.tmpdir(), "roomprint-worker-" + process.pid + ".mjs");
fs.writeFileSync(tmp, src);
const worker = (await import(pathToFileURL(tmp).href)).default;

// In-memory KV with the subset of the API the Worker uses.
const store = new Map();
const KV = {
  async get(key, type) { const v = store.get(key); if (v == null) return null; return type === "json" ? JSON.parse(v) : v; },
  async put(key, value) { store.set(key, String(value)); },
  async delete(key) { store.delete(key); },
  async list({ prefix = "" } = {}) { return { keys: [...store.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true }; },
};

const env = {
  JOBS: KV,
  GH_OWNER: "test", GH_REPO: "roomprint-uploads", GH_BRANCH_BASE: "main",
  BUSINESS_NAME: "Roomprint", BUSINESS_EMAIL: "hello@example.com",
  PAYPAL_EMAIL: process.env.PAYPAL_EMAIL || "pay@example.com", PAYPAL_ME: "",
  PRICE_HOME: "199", PRICE_FULL: "299", PRICE_UPDATE: "59",
  MOCK_GITHUB: "1",
};

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
    // Test-only helpers: inspect the mock store, write a builder status file.
    if (url.pathname === "/__mock/keys") { res.setHeader("content-type", "application/json"); return res.end(JSON.stringify([...store.keys()])); }
    if (url.pathname === "/__mock/put" && req.method === "POST") {
      const body = JSON.parse(await readBody(req));
      await KV.put(`mock:${body.branch}:${body.path}`, Buffer.from(body.content, "utf8").toString("base64"));
      await KV.delete("st:" + body.branch.replace(/^job-/, ""));
      return res.end("ok");
    }
    if (url.pathname === "/__mock/get") {
      const v = await KV.get(`mock:${url.searchParams.get("branch")}:${url.searchParams.get("path")}`);
      if (v == null) { res.statusCode = 404; return res.end(""); }
      return res.end(Buffer.from(v, "base64"));
    }
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = chunks.length ? Buffer.concat(chunks) : null;
    const headers = new Headers();
    for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v);
    const request = new Request(url.href, { method: req.method, headers, body: body && req.method !== "GET" && req.method !== "HEAD" ? body : undefined });
    const out = await worker.fetch(request, env, { waitUntil() {}, passThroughOnException() {} });
    res.statusCode = out.status;
    out.headers.forEach((v, k) => res.setHeader(k, v));
    const buf = Buffer.from(await out.arrayBuffer());
    res.end(buf);
  } catch (e) {
    console.error(e);
    res.statusCode = 500; res.end(String(e && e.stack || e));
  }
});
function readBody(req) { return new Promise((r) => { let s = ""; req.on("data", (c) => (s += c)); req.on("end", () => r(s)); }); }
server.listen(PORT, "127.0.0.1", () => console.log(`roomprint dev server http://127.0.0.1:${PORT}`));
