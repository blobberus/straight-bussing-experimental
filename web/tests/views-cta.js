// CTA routes in the views (experimental, owner 2026-11-06): their own Routes section, CTA badges and labels, scheduled
// times marked as estimates, shuttle stops first on Current trip, and no CTA route in the shuttle feed's states.
import { test, eq, ok } from "./lib.js";
import { fixture, onTrip, NOW } from "./views-fixtures.js";
import { renderRoutes, groupRoutes, operatingIds, listHTML } from "../js/ui/views/routes.js";
import { renderNearby, N } from "../js/ui/views/nearby.js";
import { arrivalRow, routeChip } from "../js/ui/components.js";
import { arrivalsFor, runningCount } from "../js/core/arrivals.js";
import { silentService, scheduledNoLive, scheduledRoutes } from "../js/core/operating.js";
import { showRunning } from "../js/core/custom.js";
import { routeIndexFor, searchRoutes } from "../js/core/routesearch.js";

const ALL_DAY = { first: "00:00", last: "24:00", trips: 90, buses: Array(24).fill(2), spans: [["00:00", "24:00"]] };
const WEEK = { mon: ALL_DAY, tue: ALL_DAY, wed: ALL_DAY, thu: ALL_DAY, fri: ALL_DAY, sat: ALL_DAY, sun: ALL_DAY };
/** The view fixture plus two CTA routes (171 runs all day by the schedule, 55 has no schedule today) and their stops. */
function withCta(over = {}) {
  const f = fixture();
  const routes = { ...f.routes, "cta:171": { short: "171", long: "U. of Chicago/Hyde Park", color: "#747477", text_color: "#FFFFFF", agency: "cta" },
    "cta:55": { short: "55", long: "Garfield", color: "#414145", text_color: "#FFFFFF", agency: "cta" } };
  const stops = { ...f.stops, "cta:1": { name: "55th Street & Ellis (EB)", lat: 41.7901, lon: -87.6001 }, "cta:2": { name: "University (EB)", lat: 41.7951, lon: -87.5981 } };
  const routeStops = { ...f.routeStops, "cta:171": ["cta:1", "cta:2"], "cta:55": ["cta:2", "cta:1"] };
  const stopRoutes = { ...f.stopRoutes, "cta:1": ["cta:171", "cta:55"], "cta:2": ["cta:171", "cta:55"] };
  const ctaTrips = [{ trip: { trip_id: "cta:sched:171:1:1", route_id: "cta:171" }, vehicle: null, sched: true, dir: "Northbound",
    stop_time_update: [{ stop_id: "cta:1", arrival: { time: NOW + 240 } }, { stop_id: "cta:2", arrival: { time: NOW + 420 } }] }];
  return fixture({ routes, stops, routeStops, stopRoutes, service: { routes: { "cta:171": { days: WEEK, exceptions: [] } } },
    ctaPatterns: { "cta:171": [{ dir: "Northbound", stops: ["cta:1", "cta:2"] }] }, ctaTrips, ctaBuses: [],
    cta: { mode: "off", lastOk: 0, failed: false, feedTs: 0, loaded: false },
    routeOrder: [], customRoutes: [], activeCustom: null, prevHidden: [], favStops: [], journey: null, ...over });
}
const rowOf = (h, id) => h.slice(h.indexOf(`data-action="route:open" data-id="${id}"`), h.indexOf(`data-action="routes:toggle" data-id="${id}"`));

test("Routes: CTA routes get their own CTA section after the shuttles, never a shuttle group", () => {
  const s = withCta(), h = renderRoutes(s, NOW), g = groupRoutes(s, NOW);
  ok(![...g.running, ...g.scheduled, ...g.idle, ...g.hidden].some((i) => i.startsWith("cta:")), "the shuttle groups hold shuttles only");
  const sec = h.indexOf('class="rt-cta"');
  ok(sec > 0 && h.indexOf("CTA buses") > sec, "a CTA buses section with its heading");
  ok(sec > h.indexOf('data-id="R1"') && sec > h.indexOf('data-id="R2"'), "after the shuttle routes");
  ok(h.indexOf('data-id="cta:171"') > sec && h.indexOf('data-id="cta:55"') > sec, "both CTA routes inside it");
  ok(h.includes("Scheduled times · CTA live data not connected"), "says where its times come from");
  ok(h.includes('href="https://www.transitchicago.com/"') && h.includes("Data provided by Chicago Transit Authority"), "CTA's contact and credit");
  ok(h.indexOf('class="rt-official"') > sec, "the shuttles' official phone and page stay at the bottom");
});

test("Routes: CTA row status comes from CTA's schedule, with the CTA badge and the same eye toggle", () => {
  const h = renderRoutes(withCta(), NOW);
  ok(/Scheduled until 12:00 AM/.test(rowOf(h, "cta:171")) || /Scheduled/.test(rowOf(h, "cta:171")), "scheduled by CTA's timetable");
  ok(!rowOf(h, "cta:171").includes("v-livedot"), "no live dot on a schedule-only route");
  ok(/Not running/.test(rowOf(h, "cta:55")), "a CTA route with no schedule today");
  ok(!/no live location/.test(rowOf(h, "cta:171")), "never the shuttle feed's wording");
  ok(h.includes('data-action="routes:toggle" data-id="cta:171"'), "the eye toggle");
  const hid = renderRoutes(withCta({ hiddenRoutes: ["cta:55"] }), NOW);
  ok(/rt-ctahid[^>]*>Hidden/.test(hid) && hid.indexOf('data-id="cta:55"') > hid.indexOf("rt-ctahid"), "a hidden CTA route sits under the CTA section's Hidden");
});

test("routeChip: a CTA badge is squared and says CTA (shape and text, not color alone)", () => {
  const s = withCta(), c = routeChip("cta:171", s.routes), p = routeChip("R1", s.routes);
  ok(/class="chip[^"]* chip--cta"/.test(c) && c.includes('<span class="chip-cta">CTA</span> 171'), c);
  ok(!p.includes("cta"), "shuttle badges unchanged");
});

test("arrivals: CTA scheduled times join the list marked sched; CTA buses count on their route", () => {
  const s = withCta({ ctaBuses: [{ vehicle: { id: "cta:8001", label: "8001" }, position: { latitude: 41.79, longitude: -87.6 }, trip: { trip_id: "cta:x", route_id: "cta:171" }, timestamp: NOW, cta: true }] });
  const a = arrivalsFor(s, "cta:1", { nowS: NOW });
  eq(a.map((x) => [x.rid, x.sched || false]), [["cta:171", true]]);
  eq(arrivalsFor(s, "S1", { nowS: NOW }).every((x) => !x.sched), true, "shuttle stops unchanged");
  eq(runningCount(s, "cta:171"), 1);
  eq(runningCount(s, "R1"), 1);
});

test("arrivalRow: a CTA scheduled time says Scheduled, est. with ~, and CTA route in the spoken label", () => {
  const s = withCta(), a = arrivalsFor(s, "cta:1", { nowS: NOW })[0];
  const h = arrivalRow(a, s, { now: NOW });
  ok(h.includes("Scheduled, est.") && h.includes("dot-sched") && !h.includes("dot-live"), h);
  ok(h.includes('<span class="num">~4</span>'), "the ETA is marked as an estimate");
  ok(/aria-label="CTA route 171, U\. of Chicago\/Hyde Park, arrives in 4 minutes, scheduled time, an estimate"/.test(h), h);
  const live = arrivalRow({ ...a, sched: undefined }, withCta({ cta: { mode: "live", loaded: true, lastOk: NOW - 5, feedTs: NOW - 10 } }), { now: NOW });
  ok(live.includes("dot-live") && !live.includes("~4"), "a fresh CTA prediction reads live");
  const down = arrivalRow({ ...a, sched: undefined }, withCta({ cta: { mode: "live", loaded: true, lastOk: NOW - 300, failed: true } }), { now: NOW });
  ok(down.includes("Last known") && down.includes("~4"), "a stale CTA prediction is marked, whatever the shuttle feed says");
});

test("shuttle feed states ignore CTA: no silent service, no 'no live location' from CTA's schedule", () => {
  const s = withCta({ buses: [], trips: [], service: { routes: { "cta:171": { days: WEEK, exceptions: [] } } } });
  eq(scheduledRoutes(s, NOW), [], "only CTA is scheduled: no shuttle route counts");
  eq(silentService(s, NOW), false, "an empty shuttle feed with only CTA scheduled is not silent shuttle service");
  eq(scheduledNoLive(s, "cta:171", NOW), false);
});

test("Show running keeps the CTA routes the schedule (or a CTA bus) has running", () => {
  const s = withCta();
  const ops = operatingIds(s, NOW);
  ok(ops.includes("cta:171") && !ops.includes("cta:55"), JSON.stringify(ops));
  const p = showRunning(s, ops);
  ok(!p.hiddenRoutes.includes("cta:171") && p.hiddenRoutes.includes("cta:55"), JSON.stringify(p));
});

test("route search finds CTA routes by number and by number + name", () => {
  const s = withCta(), idx = routeIndexFor(s, Object.keys(s.routes));
  eq(searchRoutes(idx, "171")[0].id, "cta:171");
  eq(searchRoutes(idx, "55 garfield")[0].id, "cta:55");
  ok(listHTML(s, NOW, "garfield").indexOf('data-id="cta:55"') < listHTML(s, NOW, "garfield").indexOf("rt-qdiv"), "a match leads the list");
});

test("Current trip: the nearest SHUTTLE stop leads even with a CTA stop closer; the CTA stop gets its own card", () => {
  N.anchor = null;
  const s = withCta({ ...onTrip(), user: { lat: 41.79005, lon: -87.60005 }, locState: "granted" });
  Object.assign(s, { routes: withCta().routes, stops: withCta().stops, routeStops: withCta().routeStops, stopRoutes: withCta().stopRoutes,
    ctaTrips: withCta().ctaTrips, cta: withCta().cta, service: withCta().service, journey: { kind: "plan", rids: ["R1", "R2", "R3", "cta:171", "cta:55"], label: "x", to: "x", t0: NOW, legs: [] } });
  const h = renderNearby(s, NOW);
  const hero = h.indexOf("pt-next"), cta = h.indexOf("CTA nearby");
  ok(hero >= 0 && h.indexOf("Main &amp; 1st", hero) > hero && h.indexOf("Main &amp; 1st", hero) < (cta < 0 ? Infinity : cta), "the shuttle stop is the hero");
  ok(cta > hero && h.indexOf("55th Street &amp; Ellis (EB)", cta) > cta, "CTA nearby: the CTA stop, after the shuttle cards");
  ok(h.slice(cta).includes("Scheduled, est."), "with its scheduled time labeled");
});
