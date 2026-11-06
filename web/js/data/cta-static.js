// CTA schedule data (tools/build_cta.py -> web/data/cta/*.json), merged into the same store slices as Passio's so CTA
// routes behave like the shuttle routes (owner 2026-11-06). Every id is namespaced "cta:" (core/agency.js); an entry
// without the prefix is dropped, so a bad CTA file can never replace a shuttle route or stop. All files are optional:
// missing ones mean no CTA routes, and the shuttles work as before.
import { isCta } from '../core/agency.js';

/** CTA files: [store key, file name under data/]. */
export const CTA_FILES = Object.freeze([
  ['routes', 'cta/routes.json'],
  ['stops', 'cta/stops.json'],
  ['shapes', 'cta/shapes.json'],
  ['routeStops', 'cta/route_stops.json'],
  ['service', 'cta/service.json'],
  ['ctaPatterns', 'cta/patterns.json'],
]);

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/**
 * patterns.json -> {rid: [{dir, stops}]} (CTA ids only, two or more stops each).
 * @param {any} v
 * @returns {{[rid:string]: Array<{dir:string, stops:string[]}>}}
 */
export function cleanPatterns(v) {
  const out = {};
  if (!isObj(v)) return out;
  for (const [rid, lst] of Object.entries(v)) {
    if (!isCta(rid) || !Array.isArray(lst)) continue;
    const dirs = lst.filter((p) => isObj(p) && Array.isArray(p.stops) && p.stops.length >= 2)
      .map((p) => ({ dir: String(p.dir || ''), stops: p.stops.filter((s) => isCta(s)).map(String) }));
    if (dirs.length) out[rid] = dirs;
  }
  return out;
}

/** Only the CTA-namespaced entries of an object. */
function ctaOnly(o) {
  const out = {};
  for (const [k, v] of Object.entries(o || {})) if (isCta(k)) out[k] = v;
  return out;
}

/**
 * Merge cleaned CTA slices into the static patch (in place): routes, stops, shapes and routeStops get the CTA entries
 * after the shuttle ones; service.routes too (service.ctaFeed keeps CTA's feed window); ctaPatterns is set. A CTA
 * route without stops is dropped everywhere.
 * @param {object} patch the Passio static patch (routes, stops, shapes, routeStops, service)
 * @param {{routes?:object, stops?:object, shapes?:object, routeStops?:object, service?:object, ctaPatterns?:object}} cta
 *   cleaned CTA slices (data/static.js cleanSlice; ctaPatterns from cleanPatterns)
 * @returns {object} the same patch
 */
export function mergeCta(patch, cta) {
  const rs = ctaOnly(cta.routeStops);
  const routes = {};
  for (const [rid, r] of Object.entries(ctaOnly(cta.routes))) if (rs[rid] && rs[rid].length >= 2) routes[rid] = { ...r, agency: 'cta' };
  const keep = (o) => Object.fromEntries(Object.entries(ctaOnly(o)).filter(([rid]) => routes[rid]));
  patch.routes = { ...(patch.routes || {}), ...routes };
  patch.stops = { ...(patch.stops || {}), ...ctaOnly(cta.stops) };
  patch.shapes = { ...(patch.shapes || {}), ...keep(cta.shapes) };
  patch.routeStops = { ...(patch.routeStops || {}), ...keep(cta.routeStops) };
  const svc = cta.service && isObj(cta.service.routes) ? keep(cta.service.routes) : {};
  if (Object.keys(svc).length) {
    patch.service = { ...(patch.service || {}), routes: { ...((patch.service && patch.service.routes) || {}), ...svc } };
    if (isObj(cta.service.feed)) patch.service.ctaFeed = cta.service.feed;
  }
  patch.ctaPatterns = keep(cta.ctaPatterns);
  return patch;
}
