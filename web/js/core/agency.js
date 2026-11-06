/**
 * @module core/agency
 * CTA bus routes beside the campus shuttles (experimental, owner 2026-11-06: "implemenent the CTA routes in the same way
 * passio go shows but make the bus shapes identifiable to be cta and make their stations square ... They should still
 * behave on the interface like the normal bus routes"). Pure, no DOM.
 *
 * The model (docs/ARCHITECTURE.md "CTA routes"):
 *  - Static: CTA routes, stops, shapes, route_stops and service hours are merged into the same store slices as Passio's
 *    (data/static.js), with ids namespaced "cta:<id>" (route "cta:171", stop "cta:1427"), so visibility, custom routes,
 *    favorites, search, the route and stop pages and Lines by Time treat them like any route. isCta tells them apart.
 *  - Live: CTA vehicles and predictions live in their OWN store slices (store.ctaBuses, store.ctaTrips, store.cta), filled
 *    by data/cta-live.js, never in store.buses / store.trips. Every Passio rule that reads those (stale pill, "no
 *    shuttles running", silent service, off-route hiding) stays Passio-only, so a CTA failure can never hide the shuttle
 *    state, or the reverse. Views that show "the buses" or "the arrivals" of any route use allBuses / allTrips.
 *  - Without live CTA data (no proxy configured, or it fails) store.ctaTrips holds SCHEDULED times (core/ctasched.js,
 *    entries marked sched:true), always labeled as schedule estimates.
 */
import { ERR_AFTER_S, LATE_AFTER_S } from "./arrivals.js";

/** Prefix of every CTA route, stop, trip and vehicle id. */
export const CTA_PREFIX = "cta:";
/** CTA's own pages: the official source for CTA service (the shuttles keep 773.702.8181). */
export const CTA_URL = "https://www.transitchicago.com/";
/** CTA customer information (phone, feedback). */
export const CTA_INFO_URL = "https://www.transitchicago.com/customer-service/";
/** CTA customer information phone (display form, from CTA's GTFS agency.txt: 1-888-YOURCTA). */
export const CTA_PHONE = "1-888-968-7282";
/** CTA customer information phone as a tel: URI. */
export const CTA_TEL = "tel:+18889687282";
/** The credit line CTA's developer terms suggest. */
export const CTA_CREDIT = "Data provided by Chicago Transit Authority";

/**
 * Is this a CTA route / stop / trip / vehicle id?
 * @param {*} id
 * @returns {boolean}
 */
export function isCta(id) {
  return id != null && String(id).startsWith(CTA_PREFIX);
}

/**
 * CTA's own id ("cta:171" -> "171"); other ids unchanged.
 * @param {*} id
 * @returns {string}
 */
export function ctaId(id) {
  const s = String(id ?? "");
  return s.startsWith(CTA_PREFIX) ? s.slice(CTA_PREFIX.length) : s;
}

/**
 * Split route ids into shuttles and CTA routes, each in input order.
 * @param {string[]} ids
 * @returns {{shuttle:string[], cta:string[]}}
 */
export function splitAgency(ids) {
  const shuttle = [], cta = [];
  for (const id of ids || []) (isCta(id) ? cta : shuttle).push(String(id));
  return { shuttle, cta };
}

let busMemo = { a: null, b: null, v: [] }, tripMemo = { a: null, b: null, v: [] };

/**
 * Every bus the app shows: Passio's operating buses (store.buses) then CTA's (store.ctaBuses). The same array comes back
 * while neither slice changes, so map signatures and memos keep working.
 * @param {{buses?:Array, ctaBuses?:Array}} state
 * @returns {Array}
 */
export function allBuses(state) {
  const a = (state && state.buses) || [], b = (state && state.ctaBuses) || [];
  if (!b.length) return a;
  if (busMemo.a !== a || busMemo.b !== b) busMemo = { a, b, v: a.concat(b) };
  return busMemo.v;
}

/**
 * Every trip update: Passio's (store.trips) then CTA's (store.ctaTrips: live predictions, or scheduled times marked
 * sched:true). Same array while neither slice changes.
 * @param {{trips?:Array, ctaTrips?:Array}} state
 * @returns {Array}
 */
export function allTrips(state) {
  const a = (state && state.trips) || [], b = (state && state.ctaTrips) || [];
  if (!b.length) return a;
  if (tripMemo.a !== a || tripMemo.b !== b) tripMemo = { a, b, v: a.concat(b) };
  return tripMemo.v;
}

/** The empty CTA status before data/cta-live.js starts. */
export const CTA_IDLE = Object.freeze({ mode: "off", lastOk: 0, failed: false, feedTs: 0, loaded: false });

/**
 * Freshness of CTA live data (store.cta, data/cta-live.js), separate from Passio's (core/arrivals.js staleLevel):
 *  'off'   no live CTA source configured (CTA_LIVE_URL empty): scheduled times only
 *  'demo'  demo mode: simulated CTA buses from the schedule
 *  'wait'  configured, first answer not in yet
 *  'err'   configured, never answered, failed, or no good answer for over 60 s: scheduled times are shown instead
 *  'late'  the newest vehicle report is over 2 minutes old
 *  ''      live and fresh
 * @param {{mode?:string, lastOk?:number, failed?:boolean, feedTs?:number, loaded?:boolean}} cta store.cta
 * @param {number} nowS
 * @returns {'off'|'demo'|'wait'|'err'|'late'|''}
 */
export function ctaLevel(cta, nowS) {
  const c = cta || CTA_IDLE;
  if (c.mode === "demo") return "demo";
  if (c.mode !== "live") return "off";
  if (!c.loaded) return "wait";
  if (!c.lastOk || c.failed || nowS - c.lastOk > ERR_AFTER_S) return "err";
  if (c.feedTs && nowS - c.feedTs > LATE_AFTER_S) return "late";
  return "";
}

/**
 * Are CTA times right now live predictions (fresh or delayed), not the schedule?
 * @param {object} cta store.cta
 * @param {number} nowS
 * @returns {boolean}
 */
export function ctaLive(cta, nowS) {
  const l = ctaLevel(cta, nowS);
  return l === "" || l === "late" || l === "demo";
}

/**
 * One line on where CTA times come from right now (CTA group heading, CTA route and stop pages). Plain text.
 * @param {object} cta store.cta
 * @param {number} nowS
 * @returns {string} e.g. "Scheduled times · CTA live data not connected"
 */
export function ctaSourceText(cta, nowS) {
  switch (ctaLevel(cta, nowS)) {
    case "off": return "Scheduled times · CTA live data not connected";
    case "wait": return "Scheduled times · connecting to CTA live data";
    case "err": return "Scheduled times · CTA live data unavailable";
    case "late": return "CTA live data, delayed";
    case "demo": return "Simulated CTA buses (demo)";
    default: return "CTA live data";
  }
}
