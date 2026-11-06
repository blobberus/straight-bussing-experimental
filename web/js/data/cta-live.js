// CTA times and buses (experimental, owner 2026-11-06), kept apart from Passio's live feed (data/live.js): this module
// only writes store.ctaSchedule, store.ctaBuses, store.ctaTrips and store.cta, so a CTA failure can never hide the
// shuttle state, or the reverse (core/agency.js).
//
// Three modes (store.cta.mode):
//  - 'off'  (CTA_LIVE_URL empty, the default): CTA's published schedule only. Every minute store.ctaTrips gets the next
//           90 minutes of scheduled stop times (core/ctasched.js), marked sched:true; views label them "Scheduled, est.".
//           No CTA bus is ever drawn: there is no live position to draw.
//  - 'live' (CTA_LIVE_URL set): polls the owner's proxy (tools/cta-proxy/, a Cloudflare Worker that holds the CTA Bus
//           Tracker key; a key never ships in this static site) every 20 s for the Hyde Park routes' vehicles and
//           predictions. The request carries no rider data (no location, no stop picked, no id): it is the same URL for
//           everyone. A failure keeps the last answer for up to FALLBACK_S, then the schedule takes over (labeled).
//  - 'demo' (?demo=1): simulated CTA buses moving along CTA's own schedule, like the shuttle demo (data/demo.js).
import { decodeSchedule, scheduledTrips, tripsBetween } from '../core/ctasched.js';
import { chicagoUnix } from '../core/timeactive.js';
import { alongShape, distM, pathLength } from '../map/geometry.js';
import { bearing } from '../core/geo.js';

/**
 * The owner's CTA proxy endpoint (tools/cta-proxy/README.md), e.g.
 * 'https://straight-bussing-cta.<your-subdomain>.workers.dev/v1/hydepark'. Empty = no live CTA data: scheduled times.
 */
export const CTA_LIVE_URL = '';
/** Live poll interval (ms); the proxy caches about 20 s, so polling faster gains nothing. */
export const CTA_POLL_MS = 20000;
/** How often scheduled times are refreshed without live data (ms). */
export const SCHED_TICK_MS = 60000;
/** Demo buses move this often (ms). */
export const DEMO_TICK_MS = 4000;
/** After this long without a good live answer (s), scheduled times replace the last live ones (labeled as such). */
export const FALLBACK_S = 120;
/** A CTA vehicle report older than this (s) is not drawn (same rule as the shuttles, core/operating.js). */
export const CTA_STALE_S = 300;
/**
 * Bus Tracker v3 prediction "dyn" values that must not be shown as an arrival to board: 1 canceled, 4 expressed (drop-off
 * only), 16 / 17 invalidated (CTA's guide: do not display).
 */
export const DYN_SKIP = new Set([1, 4, 16, 17]);
/** Stops listed per simulated trip ahead of the bus. */
const DEMO_AHEAD = 14;

const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : NaN; };

/**
 * CTA Bus Tracker time ("20261106 14:03" or "20261106 14:03:22", Chicago) -> unix seconds; NaN if unreadable.
 * @param {string} s
 * @returns {number}
 */
export function parseCtaTime(s) {
  const m = /^(\d{4})(\d{2})(\d{2}) (\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(String(s || '').trim());
  if (!m) return NaN;
  return chicagoUnix(+m[1], +m[2], +m[3], +m[4], +m[5]) + (m[6] ? +m[6] : 0);
}

/**
 * The proxy's answer ({ts, vehicles:[Bus Tracker vehicle], predictions:[Bus Tracker prd]}, tools/cta-proxy) -> store
 * slices. Only routes and stops the app knows (the Hyde Park ones) are kept; ids get the "cta:" prefix.
 * @param {any} j
 * @param {{routes:object, stops:object}} state
 * @param {number} nowS
 * @returns {{buses:object[], trips:object[], feedTs:number}}
 */
export function parseCtaLive(j, state, nowS) {
  const routes = state.routes || {}, stops = state.stops || {};
  const buses = [], byTrip = new Map();
  let feedTs = num(j && j.ts) || 0;
  for (const v of Array.isArray(j && j.vehicles) ? j.vehicles : []) {
    if (!v || typeof v !== 'object') continue;
    const rid = 'cta:' + String(v.rt ?? ''), lat = num(v.lat), lon = num(v.lon), vid = String(v.vid ?? '');
    if (!routes[rid] || !vid || !Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    const ts = parseCtaTime(v.tmstmp);
    const t = Number.isFinite(ts) ? ts : feedTs || nowS;
    if (nowS - t > CTA_STALE_S) continue;
    if (t > feedTs) feedTs = t;
    buses.push({ vehicle: { id: 'cta:' + vid, label: vid }, position: { latitude: lat, longitude: lon, bearing: num(v.hdg) },
      trip: { trip_id: 'cta:' + String(v.tatripid || 'v' + vid), route_id: rid }, timestamp: t, cta: true, des: String(v.des || '') });
  }
  for (const p of Array.isArray(j && j.predictions) ? j.predictions : []) {
    if (!p || typeof p !== 'object') continue;
    const rid = 'cta:' + String(p.rt ?? ''), sid = 'cta:' + String(p.stpid ?? ''), vid = String(p.vid ?? ''), t = parseCtaTime(p.prdtm);
    if (!routes[rid] || !stops[sid] || !vid || !Number.isFinite(t)) continue;
    if (DYN_SKIP.has(Number(p.dyn))) continue;   // canceled, drop-off only or invalidated: never shown as a bus to catch
    const key = vid + '|' + String(p.tatripid || ''), tid = 'cta:' + String(p.tatripid || 'v' + vid);
    if (!byTrip.has(key)) byTrip.set(key, { trip: { trip_id: tid, route_id: rid }, vehicle: { id: 'cta:' + vid, label: vid }, stop_time_update: [] });
    byTrip.get(key).stop_time_update.push({ stop_id: sid, arrival: { time: t } });
  }
  const trips = [...byTrip.values()];
  for (const tu of trips) tu.stop_time_update.sort((a, b) => a.arrival.time - b.arrival.time);
  for (const b of buses) {   // the next stop of each bus (route page "heading here"), from its own predictions
    let best = null;
    for (const tu of trips) if (tu.vehicle.id === b.vehicle.id && tu.stop_time_update[0] && (!best || tu.stop_time_update[0].arrival.time < best.arrival.time)) best = tu.stop_time_update[0];
    if (best) b.stop_id = best.stop_id;
  }
  return { buses, trips, feedTs };
}

/**
 * Simulated CTA buses (demo mode) from the schedule: every trip under way at nowS is a bus between its last and next
 * stop, on CTA's line shape; trips under way or starting within 30 minutes predict their next stops.
 * @param {object} state store state (routes, stops, shapes)
 * @param {ReturnType<typeof decodeSchedule>} sched
 * @param {number} nowS
 * @param {Map} [cache] road paths between stops, reused across ticks
 * @returns {{buses:object[], trips:object[]}}
 */
export function demoCta(state, sched, nowS, cache = new Map()) {
  const buses = [], trips = [];
  for (const x of tripsBetween(sched, nowS, nowS + 1800, { overlap: true })) {
    if (!state.routes?.[x.rid]) continue;
    const idx = x.times.map((t, i) => (t != null && state.stops?.[x.stops[i]] ? i : -1)).filter((i) => i >= 0);
    if (idx.length < 2) continue;
    const key = `${x.rid.slice(4)}-${x.di}-${x.start}`, label = String(7000 + (Math.floor(x.start / 60) % 997));
    const vid = 'cta:demo-' + key, tid = 'cta:demo-trip-' + key;
    const first = x.times[idx[0]], last = x.times[idx[idx.length - 1]];
    if (first <= nowS && nowS <= last) {
      let k = 0;
      while (k < idx.length - 2 && x.times[idx[k + 1]] <= nowS) k++;
      const i = idx[k], j = idx[k + 1], ck = `${x.rid}|${x.di}|${i}|${j}`;
      if (!cache.has(ck)) {
        const a = state.stops[x.stops[i]], b = state.stops[x.stops[j]];
        const line = alongShape(state.shapes?.[x.rid], x.stops, a, b, [[a.lat, a.lon], [b.lat, b.lon]]);
        const cum = [0];
        for (let n = 1; n < line.length; n++) cum.push(cum[n - 1] + distM(line[n - 1], line[n]));
        cache.set(ck, { line, cum, len: pathLength(line) });
      }
      const span = x.times[j] - x.times[i], pos = pointOn(cache.get(ck), span > 0 ? (nowS - x.times[i]) / span : 0);
      buses.push({ vehicle: { id: vid, label }, position: { latitude: pos.lat, longitude: pos.lon, bearing: pos.bearing },
        trip: { trip_id: tid, route_id: x.rid }, timestamp: Math.floor(nowS - 4), cta: true, des: x.dir, stop_id: x.stops[j] });
    }
    const stu = idx.filter((i) => x.times[i] > nowS).slice(0, DEMO_AHEAD).map((i) => ({ stop_id: x.stops[i], arrival: { time: x.times[i] } }));
    if (stu.length) trips.push({ trip: { trip_id: tid, route_id: x.rid }, vehicle: { id: vid, label }, stop_time_update: stu });
  }
  return { buses, trips };
}

/** Point and heading at fraction f along a road path {line, cum, len} (data/demo.js pointAlong, kept here so the demo
 * module stays out of the first render). */
function pointOn(p, f) {
  const { line, cum, len } = p;
  if (line.length < 2 || !(len > 0)) { const q = line[0] || [0, 0]; return { lat: q[0], lon: q[1], bearing: 0 }; }
  const d = Math.min(1, Math.max(0, f)) * len;
  let i = 1;
  while (i < line.length - 1 && cum[i] < d) i++;
  const a = line[i - 1], b = line[i], seg = cum[i] - cum[i - 1], t = seg > 0 ? (d - cum[i - 1]) / seg : 0;
  return { lat: a[0] + (b[0] - a[0]) * t, lon: a[1] + (b[1] - a[1]) * t, bearing: Math.round(bearing({ lat: a[0], lon: a[1] }, { lat: b[0], lon: b[1] })) % 360 };
}

/** Resolves once static data (with store.ctaPatterns) has loaded. */
function whenStatic(store) {
  if (store.get().staticLoaded) return Promise.resolve();
  return new Promise((resolve) => { const off = store.subscribe((s) => { if (s.staticLoaded) { off(); resolve(); } }); });
}

/**
 * Start CTA times and buses (see the module header). Never throws; the shuttle feed is never touched.
 * @param {{get():object, set(patch:object):void, subscribe(fn:Function):Function}} store
 * @param {{url?:string, demo?:boolean, fetch?:typeof fetch, now?:() => number, base?:string, pollMs?:number,
 *   timeoutMs?:number, keepAlive?:() => boolean}} [opts] url: the proxy (default CTA_LIVE_URL); demo: ?demo=1
 * @returns {{stop():void, tick():Promise<void>, mode:'off'|'live'|'demo'}}
 */
export function startCtaLive(store, opts = {}) {
  const url = opts.url ?? CTA_LIVE_URL, mode = opts.demo ? 'demo' : url ? 'live' : 'off';
  const fetchFn = opts.fetch || ((...a) => globalThis.fetch(...a));
  const nowFn = opts.now || (() => Date.now() / 1000), base = opts.base ?? 'data/';
  const every = mode === 'live' ? opts.pollMs ?? CTA_POLL_MS : mode === 'demo' ? DEMO_TICK_MS : SCHED_TICK_MS;
  const doc = typeof document !== 'undefined' ? document : null;
  const keepAlive = () => { try { return !!(opts.keepAlive && opts.keepAlive()); } catch (e) { return false; } };
  let timer = 0, stopped = false, sched = null, busy = null, lastOk = 0;
  const cache = new Map();
  store.set({ cta: { mode, lastOk: 0, failed: false, feedTs: 0, loaded: false } });

  const setCta = (patch) => store.set({ cta: { ...store.get().cta, mode, ...patch } });
  const schedOnly = (t) => ({ ctaTrips: sched ? scheduledTrips(sched, t) : [], ctaBuses: [] });

  async function loadSchedule() {
    await whenStatic(store);
    try {
      const r = await fetchFn(base + 'cta/schedule.json', { cache: 'no-cache' });
      if (r && r.ok) sched = decodeSchedule(await r.json(), store.get().ctaPatterns);
    } catch (e) { sched = null; }
    if (!stopped) store.set({ ctaSchedule: sched });
  }

  async function poll(t) {
    const ctl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const to = setTimeout(() => ctl && ctl.abort(), opts.timeoutMs ?? 8000);
    try {
      const r = await fetchFn(url + (url.includes('?') ? '&' : '?') + '_=' + Math.floor(t / 10), { cache: 'no-store', signal: ctl && ctl.signal });
      if (!r || !r.ok) throw new Error('CTA proxy HTTP ' + (r ? r.status : '?'));
      const j = await r.json();
      if (!j || typeof j !== 'object' || !Array.isArray(j.vehicles)) throw new Error('CTA proxy: bad answer');
      if (j.ok === false) throw new Error('CTA proxy: ' + (Array.isArray(j.errors) ? j.errors.join('; ') : 'not ok'));   // flagged; the schedule after FALLBACK_S
      const got = parseCtaLive(j, store.get(), t);
      lastOk = t;
      store.set({ ctaBuses: got.buses, ctaTrips: got.trips, cta: { mode, loaded: true, failed: false, lastOk: t, feedTs: got.feedTs || t } });
    } catch (e) {
      if (stopped) return;
      const patch = t - lastOk > FALLBACK_S ? schedOnly(t) : {};   // stale live times give way to the schedule, labeled
      store.set({ ...patch, cta: { ...store.get().cta, mode, loaded: true, failed: true } });
    } finally { clearTimeout(to); }
  }

  async function tick() {
    if (stopped) return;
    if (busy) return busy;
    busy = (async () => {
      if (!store.get().ctaSchedule && !sched) await loadSchedule();
      const t = nowFn();
      if (mode === 'live') await poll(t);
      else if (mode === 'demo') {
        const d = sched ? demoCta(store.get(), sched, t, cache) : { buses: [], trips: [] };
        store.set({ ctaBuses: d.buses, ctaTrips: d.trips, cta: { mode, loaded: true, failed: false, lastOk: t, feedTs: t } });
      } else {
        store.set(schedOnly(t));
        setCta({ loaded: true });
      }
    })().catch((e) => console.warn('CTA update failed', e)).finally(() => { busy = null; schedule(); });
    return busy;
  }

  const hidden = () => !!(doc && doc.hidden) && !keepAlive();
  function schedule() {
    clearTimeout(timer);
    timer = 0;
    if (!stopped && !hidden()) timer = setTimeout(tick, every);
  }
  const onVis = () => { if (!stopped && !hidden()) tick(); };
  doc?.addEventListener('visibilitychange', onVis);
  tick();
  return {
    mode,
    tick,
    stop() { stopped = true; clearTimeout(timer); doc?.removeEventListener('visibilitychange', onVis); },
  };
}
