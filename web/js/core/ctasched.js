/**
 * @module core/ctasched
 * CTA scheduled stop times (web/data/cta/schedule.json, tools/build_cta.py encode_schedule) for the Hyde Park part of
 * each CTA route. Pure, no DOM, never throws. All times America/Chicago; GTFS service-day times run past 24:00 and count
 * from noon minus 12 h of the service date (so a daylight-saving day is still right).
 *
 * Used when no live CTA data is in (data/cta-live.js): the scheduled trips become trip-update-shaped entries marked
 * sched:true in store.ctaTrips, so the stop and route pages list them like arrivals, always labeled as schedule
 * estimates; demo mode moves simulated CTA buses along the same trips; the planner can board a scheduled CTA trip.
 *
 * schedule.json: {v:1, services:{sid:{days:'1111100', start:'YYYY-MM-DD', end, add?:[iso], drop?:[iso]}},
 *   routes:{"cta:55":[{dir:'Westbound', profiles:[[offset min | null per stop]], trips:{sid:[start, profile, delta,
 *   profile, ...]}}]}}; the stop lists are web/data/cta/patterns.json (same order).
 */
import { localParts } from "./schedule.js";
import { chicagoUnix } from "./timeactive.js";

/** How far ahead scheduled trips are listed (s): the next 90 minutes. */
export const SCHED_AHEAD_S = 5400;
/** A scheduled time this far in the past still counts (the bus may be at the stop). */
export const SCHED_BACK_S = 60;

const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

/**
 * Check and decode schedule.json with the stop lists of patterns.json. Bad parts are dropped.
 * @param {any} json schedule.json
 * @param {{[rid:string]: Array<{dir:string, stops:string[]}>}} patterns store.ctaPatterns
 * @returns {{services:object, routes:{[rid:string]: Array<{dir:string, stops:string[], profiles:Array<Array<number|null>>,
 *   trips:{[sid:string]: Array<[number, number]>}, span:number}>}}|null} span = longest offset (min); null if unusable
 */
export function decodeSchedule(json, patterns) {
  if (!isObj(json) || !isObj(json.services) || !isObj(json.routes)) return null;
  const routes = {};
  for (const [rid, dirs] of Object.entries(json.routes)) {
    const pats = patterns && patterns[rid];
    if (!Array.isArray(dirs) || !Array.isArray(pats)) continue;
    const out = [];
    dirs.forEach((d, i) => {
      const stops = pats[i] && Array.isArray(pats[i].stops) ? pats[i].stops.map(String) : null;
      if (!isObj(d) || !stops || !Array.isArray(d.profiles) || !isObj(d.trips)) return;
      const profiles = d.profiles.filter((p) => Array.isArray(p) && p.length === stops.length);
      if (profiles.length !== d.profiles.length) return;
      let span = 0;
      for (const p of profiles) for (const x of p) if (typeof x === "number" && x > span) span = x;
      const trips = {};
      for (const [sid, flat] of Object.entries(d.trips)) {
        if (!Array.isArray(flat)) continue;
        const lst = [];
        let t = 0;
        for (let k = 0; k + 1 < flat.length; k += 2) {
          t += Number(flat[k]) || 0;
          const p = flat[k + 1];
          if (Number.isInteger(p) && p >= 0 && p < profiles.length) lst.push([t, p]);
        }
        trips[sid] = lst;
      }
      out.push({ dir: String(d.dir || pats[i].dir || ""), stops, profiles, trips, span });
    });
    if (out.length) routes[rid] = out;
  }
  return { services: json.services, routes };
}

/**
 * Service ids running on a Chicago calendar date.
 * @param {object} services decoded.services
 * @param {{y:number, m:number, d:number, dow:number}} day dow 0 = Monday
 * @returns {Set<string>}
 */
export function servicesOn(services, day) {
  const iso = `${day.y}-${String(day.m).padStart(2, "0")}-${String(day.d).padStart(2, "0")}`;
  const on = new Set();
  for (const [sid, s] of Object.entries(services || {})) {
    if (!isObj(s)) continue;
    if (Array.isArray(s.drop) && s.drop.includes(iso)) continue;
    const regular = typeof s.days === "string" && s.days[day.dow] === "1" && (!s.start || s.start <= iso) && (!s.end || iso <= s.end);
    if (regular || (Array.isArray(s.add) && s.add.includes(iso))) on.add(sid);
  }
  return on;
}

/**
 * Unix time of a service date's zero point (noon minus 12 h, GTFS).
 * @param {{y:number, m:number, d:number}} day
 * @returns {number}
 */
export function serviceZero(day) {
  return chicagoUnix(day.y, day.m, day.d, 12, 0) - 43200;
}

/** The service dates whose trips can touch [from, to]: the day before `from`'s Chicago date up to `to`'s date. */
function daysAround(from, to) {
  const out = [];
  const seen = new Set();
  for (let t = from - 86400; t <= to + 3600; t += 21600) {
    const p = localParts(t), k = p.y * 10000 + p.m * 100 + p.d;
    if (!seen.has(k)) { seen.add(k); out.push(p); }
  }
  return out;
}

/**
 * Every scheduled trip with a stop time in [from, to], as {rid, dir, di, sid, start, stops, times} where times[i] is the
 * unix time at stops[i] (null where the trip does not stop). Sorted by first time.
 * @param {ReturnType<typeof decodeSchedule>} sched
 * @param {number} from unix s
 * @param {number} to unix s
 * @param {{rids?:string[]|null, overlap?:boolean}} [opts] rids: only these routes; overlap: keep a trip whose first to last
 *   time overlaps [from, to] (default: a trip with a stop time inside it)
 * @returns {Array<{rid:string, dir:string, di:number, sid:string, start:number, stops:string[], times:Array<number|null>}>}
 */
export function tripsBetween(sched, from, to, opts = {}) {
  if (!sched || !isObj(sched.routes) || !(to >= from)) return [];
  const only = opts.rids ? new Set(opts.rids.map(String)) : null;
  const out = [];
  for (const day of daysAround(from, to)) {
    const zero = serviceZero(day), on = servicesOn(sched.services, day);
    if (!on.size) continue;
    for (const [rid, dirs] of Object.entries(sched.routes)) {
      if (only && !only.has(rid)) continue;
      dirs.forEach((d, di) => {
        for (const sid of on) {
          const lst = d.trips[sid];
          if (!lst) continue;
          for (const [start, pi] of lst) {
            const t0 = zero + start * 60;
            if (t0 > to) break;                                 // starts are sorted
            if (t0 + d.span * 60 < from) continue;
            const prof = d.profiles[pi];
            const times = prof.map((o) => (typeof o === "number" ? t0 + o * 60 : null));
            if (opts.overlap) {
              const ts = times.filter((x) => x != null);
              if (!ts.length || ts[0] > to || ts[ts.length - 1] < from) continue;
            } else if (!times.some((x) => x != null && x >= from && x <= to)) continue;
            out.push({ rid, dir: d.dir, di, sid, start: t0, stops: d.stops, times });
          }
        }
      });
    }
  }
  return out.sort((a, b) => a.start - b.start || (a.rid < b.rid ? -1 : a.rid > b.rid ? 1 : a.di - b.di));
}

/**
 * Scheduled trips as trip-update-shaped entries for store.ctaTrips (sched:true): the stop times from SCHED_BACK_S ago
 * to `aheadS` from now. Trip ids "cta:sched:<route>:<dir index>:<start unix>" (unique, stable for a trip).
 * @param {ReturnType<typeof decodeSchedule>} sched
 * @param {number} nowS
 * @param {{aheadS?:number, rids?:string[]|null}} [opts]
 * @returns {Array<{trip:{trip_id:string, route_id:string}, vehicle:null, sched:true, dir:string,
 *   stop_time_update:Array<{stop_id:string, arrival:{time:number}}>}>}
 */
export function scheduledTrips(sched, nowS, opts = {}) {
  const from = nowS - SCHED_BACK_S, to = nowS + (opts.aheadS ?? SCHED_AHEAD_S);
  return tripsBetween(sched, from, to, opts).map((x) => ({
    trip: { trip_id: `cta:sched:${x.rid.slice(4)}:${x.di}:${x.start}`, route_id: x.rid },
    vehicle: null,
    sched: true,
    dir: x.dir,
    stop_time_update: x.stops.map((s, i) => (x.times[i] != null && x.times[i] >= from && x.times[i] <= to
      ? { stop_id: s, arrival: { time: x.times[i] } } : null)).filter(Boolean),
  })).filter((tu) => tu.stop_time_update.length);
}

/**
 * Trips under way at nowS (first time <= now <= last time), for demo mode: where each scheduled bus is.
 * @param {ReturnType<typeof decodeSchedule>} sched
 * @param {number} nowS
 * @returns {Array<{rid:string, dir:string, di:number, sid:string, start:number, stops:string[], times:Array<number|null>}>}
 */
export function tripsUnderway(sched, nowS) {
  return tripsBetween(sched, nowS, nowS, { overlap: true }).filter((x) => {
    const ts = x.times.filter((t) => t != null);
    return ts.length >= 2 && ts[0] <= nowS && nowS <= ts[ts.length - 1];
  });
}
