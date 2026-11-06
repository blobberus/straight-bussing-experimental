// Straight Bussing CTA proxy: a Cloudflare Worker (module syntax) that holds the CTA Bus Tracker API key as a secret and
// answers ONE read-only endpoint for the Hyde Park routes, so the key never ships in the static site or the app and CTA's
// daily quota does not grow with riders (one CTA refresh per CACHE_S for everyone). Owner steps: README.md here.
//
//   GET /cta/v1/live.json  -> {v:1, ok, ts, vehicles:[Bus Tracker vehicle], predictions:[Bus Tracker prd], errors:[...]}
//   GET /cta/v1/health     -> {ok, day, calls_today, cached_at, last_error}   (counts only)
//   anything else          -> 404;  only GET / OPTIONS;  no query parameter is ever passed on to CTA
//
// What it receives from a rider: nothing but the request itself (no location, no stop, no id; the app adds only a cache
// buster). It logs nothing. CORS: only the GitHub Pages origin (both the live and the experimental site are
// https://blobberus.github.io) plus any EXTRA_ORIGINS you set for local testing.
// Secrets / vars (Cloudflare dashboard > the Worker > Settings > Variables): CTA_KEY (secret, required),
// DAILY_LIMIT (optional, default 90000 CTA calls), EXTRA_ORIGINS (optional, comma separated, e.g. http://127.0.0.1:8000).
// Tested by tools/test_cta_proxy.py (headless Edge, stubbed CTA answers).

/** CTA routes in Hyde Park (same list as tools/build_cta.py ROUTES). */
export const ROUTES = ["171", "172", "2", "4", "X4", "6", "10", "15", "28", "47", "55", "59", "63", "192"];
/** Hyde Park box (tools/build_cta.py BOX): south, north, west, east. */
export const BOX = [41.7745, 41.8130, -87.6200, -87.5700];
/** Buses this far outside the box still get predictions (one coming in from downtown on route 4 or 6). */
export const NEAR_M = 3000;
/** One CTA refresh per this many seconds, for everyone (CTA updates about every 30 s). */
export const CACHE_S = 25;
/** CTA Bus Tracker API v3. */
export const API = "https://www.ctabustracker.com/bustime/api/v3/";
/** Origins allowed to read the answer in a browser. */
export const ORIGINS = ["https://blobberus.github.io"];

let memo = null;          // {at, body}: the last good answer (per Worker instance)
let inflight = null;      // a refresh in progress: every request waits for the same one
let day = "", calls = 0, lastError = "";

const chunk = (a, n) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));
const today = () => new Date().toISOString().slice(0, 10);

/** Is (lat, lon) inside the box grown by NEAR_M? */
export function nearHydePark(lat, lon) {
  const dLat = NEAR_M / 111320, dLon = NEAR_M / (111320 * Math.cos(((BOX[0] + BOX[1]) / 2) * Math.PI / 180));
  return lat >= BOX[0] - dLat && lat <= BOX[1] + dLat && lon >= BOX[2] - dLon && lon <= BOX[3] + dLon;
}

/** CORS headers for an allowed Origin (none for any other: the browser then refuses the answer). */
export function corsHeaders(origin, env = {}) {
  const extra = String(env.EXTRA_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
  const h = { "Vary": "Origin" };
  if (origin && (ORIGINS.includes(origin) || extra.includes(origin))) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Methods"] = "GET, OPTIONS";
    h["Access-Control-Max-Age"] = "86400";
  }
  return h;
}

function json(body, status, headers) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "X-Content-Type-Options": "nosniff", ...headers } });
}

/** Remove the key from any text that leaves the Worker. */
function scrub(s, env) {
  const k = env && env.CTA_KEY;
  return String(s || "").split(k || "\u0000").join("[key]").slice(0, 200);
}

/** One CTA call -> its bustime-response (errors inside a 200 answer included). */
async function cta(call, params, env) {
  if (day !== today()) { day = today(); calls = 0; }
  calls++;
  const q = new URLSearchParams({ key: env.CTA_KEY, format: "json", tmres: "s", ...params });
  const r = await fetch(API + call + "?" + q.toString(), { headers: { "Accept": "application/json" } });
  if (!r.ok) throw new Error("CTA " + call + " HTTP " + r.status);
  const j = await r.json();
  return (j && j["bustime-response"]) || {};
}

/** CTA's "error" entries, without the normal "no data" answer for a route that has no bus out. */
function realErrors(resp) {
  return (Array.isArray(resp.error) ? resp.error : []).filter((e) => !/no data found|no service scheduled|no arrival times/i.test(String(e && e.msg)));
}

/** Refresh from CTA: vehicles of every route, then predictions for the buses near Hyde Park. */
export async function refresh(env) {
  const errors = [], vehicles = [], predictions = [];
  for (const rts of chunk(ROUTES, 10)) {
    const resp = await cta("getvehicles", { rt: rts.join(",") }, env);
    for (const e of realErrors(resp)) errors.push(scrub(e.msg, env));
    for (const v of Array.isArray(resp.vehicle) ? resp.vehicle : []) {
      const lat = Number(v.lat), lon = Number(v.lon);
      if (Number.isFinite(lat) && Number.isFinite(lon) && nearHydePark(lat, lon)) vehicles.push(v);
    }
  }
  for (const vids of chunk(vehicles.map((v) => String(v.vid)), 10)) {
    const resp = await cta("getpredictions", { vid: vids.join(",") }, env);
    for (const e of realErrors(resp)) errors.push(scrub(e.msg, env));
    for (const p of Array.isArray(resp.prd) ? resp.prd : []) predictions.push(p);
  }
  const limit = errors.some((e) => /transaction limit/i.test(e));
  return { v: 1, ok: !limit && !(errors.length && !vehicles.length), ts: Math.floor(Date.now() / 1000), vehicles, predictions, errors: limit ? ["cta-limit", ...errors] : errors };
}

/** The cached answer, refreshed at most once per CACHE_S (one refresh shared by every waiting request). */
export async function live(env) {
  const now = Date.now() / 1000;
  if (memo && now - memo.at < CACHE_S) return memo.body;
  if (!env || !env.CTA_KEY) return { v: 1, ok: false, ts: Math.floor(now), vehicles: [], predictions: [], errors: ["CTA_KEY is not set"] };
  if (calls >= Number(env.DAILY_LIMIT || 90000) && day === today()) {
    return memo ? { ...memo.body, ok: false, errors: ["budget"] } : { v: 1, ok: false, ts: Math.floor(now), vehicles: [], predictions: [], errors: ["budget"] };
  }
  if (!inflight) {
    inflight = refresh(env).then((body) => {
      if (body.ok || !memo) memo = { at: Date.now() / 1000, body };
      else memo = { at: Date.now() / 1000, body: { ...memo.body, ok: false, errors: body.errors } };   // keep the last good data, flagged
      if (!body.ok) lastError = body.errors.join("; ");
      return memo.body;
    }).catch((e) => {
      lastError = scrub(e && e.message, env);
      const body = memo ? { ...memo.body, ok: false, errors: [lastError] } : { v: 1, ok: false, ts: Math.floor(Date.now() / 1000), vehicles: [], predictions: [], errors: [lastError] };
      memo = { at: Date.now() / 1000, body };   // failures are cached too: CTA is asked again only after CACHE_S
      return body;
    }).finally(() => { inflight = null; });
  }
  return inflight;
}

/** For tests: forget the cache and counters. */
export function _reset() { memo = null; inflight = null; day = ""; calls = 0; lastError = ""; }

export default {
  async fetch(request, env) {
    const url = new URL(request.url), cors = corsHeaders(request.headers.get("Origin") || "", env);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method !== "GET") return json({ ok: false, error: "method not allowed" }, 405, cors);
    if (url.pathname === "/cta/v1/live.json") return json(await live(env), 200, { ...cors, "Cache-Control": "public, max-age=10" });
    if (url.pathname === "/cta/v1/health") return json({ ok: !lastError, day, calls_today: calls, cached_at: memo ? Math.floor(memo.at) : 0, last_error: lastError }, 200, { ...cors, "Cache-Control": "no-store" });
    return json({ ok: false, error: "not found" }, 404, cors);
  },
};
