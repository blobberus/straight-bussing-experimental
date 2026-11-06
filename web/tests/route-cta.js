// ui/views/route.js for a CTA route (experimental, owner 2026-11-06): one timeline per direction, CTA's own status and
// time source, scheduled times marked "~", CTA buses heading to their next stop, CTA's contact instead of the shuttles'.
import { test, eq, ok } from "./lib.js";
import { renderRoute, busPositions, routeStatusText } from "../js/ui/views/route.js";
import { fixture, NOW } from "./views-fixtures.js";

const ALL_DAY = { first: "00:00", last: "24:00", trips: 90, buses: Array(24).fill(2), spans: [["00:00", "24:00"]] };
const WEEK = { mon: ALL_DAY, tue: ALL_DAY, wed: ALL_DAY, thu: ALL_DAY, fri: ALL_DAY, sat: ALL_DAY, sun: ALL_DAY };
function cta(over = {}) {
  const f = fixture();
  return fixture({
    routes: { ...f.routes, "cta:4": { short: "4", long: "Cottage Grove", color: "#414145", text_color: "#FFFFFF", agency: "cta" } },
    stops: { ...f.stops, "cta:10": { name: "Cottage Grove & 55th (NB)", lat: 41.795, lon: -87.606 }, "cta:11": { name: "Cottage Grove & 53rd (NB)", lat: 41.799, lon: -87.606 },
      "cta:20": { name: "Cottage Grove & 53rd (SB)", lat: 41.799, lon: -87.6062 }, "cta:21": { name: "Cottage Grove & 55th (SB)", lat: 41.795, lon: -87.6062 } },
    routeStops: { ...f.routeStops, "cta:4": ["cta:20", "cta:21", "cta:10", "cta:11"] },
    ctaPatterns: { "cta:4": [{ dir: "Southbound", stops: ["cta:20", "cta:21"] }, { dir: "Northbound", stops: ["cta:10", "cta:11"] }] },
    service: { routes: { "cta:4": { days: WEEK, exceptions: [] } } },
    ctaTrips: [{ trip: { trip_id: "cta:sched:4:1:1", route_id: "cta:4" }, vehicle: null, sched: true,
      stop_time_update: [{ stop_id: "cta:10", arrival: { time: NOW + 300 } }, { stop_id: "cta:11", arrival: { time: NOW + 480 } }] }],
    ctaBuses: [], cta: { mode: "off", lastOk: 0, failed: false, feedTs: 0, loaded: true },
    buses: [], trips: [], routeId: "cta:4", view: "route", ...over,
  });
}

test("CTA route page: a timeline per direction, CTA status and time source, scheduled times with ~", () => {
  const h = renderRoute(cta(), NOW);
  ok(h.indexOf(">Southbound<") > 0 && h.indexOf(">Northbound<") > h.indexOf(">Southbound<"), "both directions, in pattern order");
  eq((h.match(/<ol class="v-tl r-tl"/g) || []).length, 2);
  ok(h.includes("Scheduled 24 hours"), "CTA's schedule status");
  ok(h.includes("Scheduled times · CTA live data not connected"), "where the times come from");
  ok(/Cottage Grove &amp; 55th \(NB\)<\/span><\/span><span class="v-tleta">~5 min/.test(h), "a scheduled time is marked as an estimate");
  ok(!h.includes("773.702.8181") && !h.includes("No shuttles"), "no shuttle help on a CTA route (the empty shuttle feed is not CTA's)");
  ok(h.includes("transitchicago.com") && h.includes("Data provided by Chicago Transit Authority"), "CTA's contact and credit");
  eq(routeStatusText(cta(), "cta:4", NOW), "Scheduled");
});

test("CTA route page: a CTA bus shows on its own direction, heading to its next stop", () => {
  const bus = { vehicle: { id: "cta:8123", label: "8123" }, position: { latitude: 41.797, longitude: -87.606 }, trip: { trip_id: "cta:1", route_id: "cta:4" },
    timestamp: NOW - 5, cta: true, stop_id: "cta:11" };
  const s = cta({ ctaBuses: [bus], cta: { mode: "live", loaded: true, lastOk: NOW - 5, feedTs: NOW - 5 } });
  eq(busPositions(s, "cta:4", NOW, ["cta:20", "cta:21"]).length, 0, "not on the Southbound list");
  const p = busPositions(s, "cta:4", NOW, ["cta:10", "cta:11"]);
  eq(p.map((x) => [x.next, x.prev]), [[1, 0]]);
  const h = renderRoute(s, NOW);
  ok(h.includes("1 bus live") && h.includes("v-livedot"), "a live CTA bus");
  ok(h.includes("CTA live data"), "live source line");
  eq(routeStatusText(s, "cta:4", NOW), "1 bus");
});

test("shuttle route page unchanged by the CTA slices", () => {
  const h = renderRoute(cta({ routeId: "R1", buses: fixture().buses, trips: fixture().trips }), NOW);
  ok(!h.includes("r-dir") && !h.includes("transitchicago"), "no direction headings, no CTA contact");
  ok(h.includes("Times are live predictions"));
});

test("CTA route page: a scheduled time due now reads ~Now, never the live green Now", () => {
  const s = cta({ ctaTrips: [{ trip: { trip_id: "cta:sched:4:1:2", route_id: "cta:4" }, vehicle: null, sched: true, stop_time_update: [{ stop_id: "cta:10", arrival: { time: NOW + 20 } }] }] });
  const h = renderRoute(s, NOW);
  ok(h.includes('<span class="v-tleta">~Now</span>') && !h.includes("is-now"), "muted ~Now");
});
