// Tests for core/agency.js and core/ctasched.js (CTA routes beside the shuttles, experimental, owner 2026-11-06)
import { test, eq, ok } from "./lib.js";
import { isCta, ctaId, splitAgency, allBuses, allTrips, ctaLevel, ctaLive, ctaSourceText, CTA_IDLE } from "../js/core/agency.js";
import { decodeSchedule, servicesOn, serviceZero, tripsBetween, scheduledTrips, tripsUnderway } from "../js/core/ctasched.js";
import { chicagoUnix } from "../js/core/timeactive.js";
import { drawOrder } from "../js/core/visibility.js";
import { plan, refineWalking } from "../js/core/planner.js";

test("isCta / ctaId / splitAgency: CTA ids are the namespaced ones", () => {
  ok(isCta("cta:171") && isCta("cta:1427") && !isCta("1075") && !isCta(1075) && !isCta(null) && !isCta("xcta:1"));
  eq(ctaId("cta:X4"), "X4");
  eq(ctaId("1075"), "1075");
  eq(splitAgency(["1075", "cta:55", "5702", "cta:2"]), { shuttle: ["1075", "5702"], cta: ["cta:55", "cta:2"] });
});

test("allBuses / allTrips: shuttles then CTA, the same array while nothing changes", () => {
  const buses = [{ id: 1 }], cta = [{ id: "cta:1" }];
  eq(allBuses({ buses, ctaBuses: [] }), buses, "no CTA: the shuttle array itself");
  ok(allBuses({ buses, ctaBuses: [] }) === buses);
  const a = allBuses({ buses, ctaBuses: cta });
  eq(a.length, 2);
  ok(allBuses({ buses, ctaBuses: cta }) === a, "memoized");
  ok(allBuses({ buses, ctaBuses: [{ id: "cta:2" }] }) !== a, "a new CTA list is a new array");
  const trips = [{ t: 1 }], ct = [{ t: 2 }];
  eq(allTrips({ trips, ctaTrips: ct }).length, 2);
  eq(allTrips({}), []);
});

test("ctaLevel: off / demo / wait / err / late / fresh, apart from the shuttle feed", () => {
  const now = 1000000;
  eq(ctaLevel(CTA_IDLE, now), "off");
  eq(ctaLevel(null, now), "off");
  eq(ctaLevel({ mode: "demo" }, now), "demo");
  eq(ctaLevel({ mode: "live", loaded: false }, now), "wait");
  eq(ctaLevel({ mode: "live", loaded: true, lastOk: 0 }, now), "err");
  eq(ctaLevel({ mode: "live", loaded: true, lastOk: now - 5, failed: true }, now), "err");
  eq(ctaLevel({ mode: "live", loaded: true, lastOk: now - 61 }, now), "err", "no good answer for over 60 s");
  eq(ctaLevel({ mode: "live", loaded: true, lastOk: now - 5, feedTs: now - 200 }, now), "late");
  eq(ctaLevel({ mode: "live", loaded: true, lastOk: now - 5, feedTs: now - 20 }, now), "");
  ok(ctaLive({ mode: "demo" }, now) && !ctaLive(CTA_IDLE, now));
  eq(ctaSourceText(CTA_IDLE, now), "Scheduled times · CTA live data not connected");
  eq(ctaSourceText({ mode: "live", loaded: true, lastOk: 0 }, now), "Scheduled times · CTA live data unavailable");
});

// A made-up route: Eastbound 3 stops; weekday trips at 8:30 and 9:31 AM, a 1:10 AM trip on Saturday's service day
const PATTERNS = { "cta:55": [{ dir: "Westbound", stops: ["cta:4", "cta:5"] }, { dir: "Eastbound", stops: ["cta:1", "cta:2", "cta:6"] }] };
const SCHED = {
  v: 1,
  services: { WK: { days: "1111100", start: "2026-11-01", end: "2026-11-30", drop: ["2026-11-26"] }, SA: { days: "0000010", start: "2026-11-01", end: "2026-11-30" },
    HOL: { days: "0000000", start: "2026-11-26", end: "2026-11-26", add: ["2026-11-26"] } },
  routes: { "cta:55": [
    { dir: "Westbound", profiles: [[0, 2]], trips: { WK: [600, 0] } },
    { dir: "Eastbound", profiles: [[0, 3, 10], [0, 2, null]], trips: { WK: [510, 0, 61, 0], SA: [1510, 1], HOL: [700, 0] } },
  ] },
};
const S = decodeSchedule(SCHED, PATTERNS);
const at = (y, m, d, h, mi) => chicagoUnix(y, m, d, h, mi);

test("decodeSchedule: trips, profiles and stop lists line up; bad input is null", () => {
  ok(S && S.routes["cta:55"].length === 2);
  const east = S.routes["cta:55"][1];
  eq(east.stops, ["cta:1", "cta:2", "cta:6"]);
  eq(east.trips.WK, [[510, 0], [571, 0]], "delta-coded starts");
  eq(east.span, 10);
  eq(decodeSchedule(null, PATTERNS), null);
  eq(decodeSchedule({ services: {}, routes: { "cta:55": [{ dir: "x", profiles: [[0]], trips: {} }] } }, PATTERNS).routes, {}, "profile length must match the stops");
});

test("servicesOn: weekday pattern, the date range and holiday changes", () => {
  eq([...servicesOn(S.services, { y: 2026, m: 11, d: 6, dow: 4 })], ["WK"], "Friday Nov 6");
  eq([...servicesOn(S.services, { y: 2026, m: 11, d: 7, dow: 5 })], ["SA"], "Saturday");
  eq([...servicesOn(S.services, { y: 2026, m: 11, d: 26, dow: 3 })], ["HOL"], "Thanksgiving: weekday dropped, holiday added");
  eq([...servicesOn(S.services, { y: 2026, m: 12, d: 2, dow: 2 })], [], "after the feed ends");
});

test("tripsBetween / scheduledTrips: Chicago times, the 90-minute window, sched:true entries", () => {
  const now = at(2026, 11, 6, 8, 25);
  const trips = tripsBetween(S, now, now + 5400);
  eq(trips.map((x) => [x.dir, x.start]), [["Eastbound", at(2026, 11, 6, 8, 30)], ["Eastbound", at(2026, 11, 6, 9, 31)]]);
  eq(trips[0].times, [at(2026, 11, 6, 8, 30), at(2026, 11, 6, 8, 33), at(2026, 11, 6, 8, 40)]);
  const tu = scheduledTrips(S, now);
  eq(tu.length, 2);
  ok(tu[0].sched === true && tu[0].vehicle === null && tu[0].trip.route_id === "cta:55");
  eq(tu[0].trip.trip_id, `cta:sched:55:1:${at(2026, 11, 6, 8, 30)}`);
  eq(tu[0].stop_time_update.map((u) => u.stop_id), ["cta:1", "cta:2", "cta:6"]);
  eq(scheduledTrips(S, at(2026, 11, 6, 8, 34), { aheadS: 600 })[0].stop_time_update.map((u) => u.stop_id), ["cta:2", "cta:6"],
    "8:33 is a minute ago: kept; 8:30 is left out");
});

test("tripsBetween: a 25:10 trip runs at 1:10 AM the next morning (service day zero = noon minus 12 h)", () => {
  const sat1am = at(2026, 11, 8, 1, 10);   // Saturday Nov 7's service day, 25:10
  const trips = tripsBetween(S, sat1am - 60, sat1am + 60);
  eq(trips.length, 1);
  eq(trips[0].times, [sat1am, sat1am + 120, null]);
  eq(serviceZero({ y: 2026, m: 11, d: 1 }), at(2026, 11, 1, 12, 0) - 43200, "daylight-saving day: noon minus 12 h");
});

test("tripsUnderway: the trips between their first and last stop now (demo buses)", () => {
  eq(tripsUnderway(S, at(2026, 11, 6, 8, 35)).map((x) => x.start), [at(2026, 11, 6, 8, 30)]);
  eq(tripsUnderway(S, at(2026, 11, 6, 8, 45)), []);
});

test("drawOrder: CTA routes below the shuttles unless focused or ordered up", () => {
  const routes = { "cta:55": {}, "1075": {}, "cta:171": {}, "5702": {} };
  eq(drawOrder({ routes, routeOrder: [] }), ["1075", "5702", "cta:55", "cta:171"]);
  eq(drawOrder({ routes, routeOrder: ["cta:171"] }), ["cta:171", "1075", "5702", "cta:55"], "the rider's order wins");
  eq(drawOrder({ routes, routeOrder: [] }, ["cta:55"])[0], "cta:55", "a focused CTA route is on top");
});

// The planner with a CTA route (two directions) and scheduled CTA times
const P_NOW = 1_800_000_000;
const PSTOPS = { "cta:e1": { name: "A (EB)", lat: 41.7950, lon: -87.6100 }, "cta:e2": { name: "B (EB)", lat: 41.7950, lon: -87.6000 }, "cta:e3": { name: "C (EB)", lat: 41.7950, lon: -87.5900 },
  "cta:w1": { name: "C (WB)", lat: 41.7951, lon: -87.5900 }, "cta:w2": { name: "B (WB)", lat: 41.7951, lon: -87.6000 }, "cta:w3": { name: "A (WB)", lat: 41.7951, lon: -87.6100 } };
const PDATA = (trips) => ({ stops: PSTOPS, routes: { "cta:55": { short: "55", long: "Garfield" } },
  routeStops: { "cta:55": ["cta:w1", "cta:w2", "cta:w3", "cta:e1", "cta:e2", "cta:e3"] }, trips, buses: [],
  patterns: { "cta:55": [{ dir: "Westbound", stops: ["cta:w1", "cta:w2", "cta:w3"] }, { dir: "Eastbound", stops: ["cta:e1", "cta:e2", "cta:e3"] }] } });
const ptrip = (id, list) => ({ trip: { trip_id: id, route_id: "cta:55" }, vehicle: null, sched: true, stop_time_update: list.map(([s, m]) => ({ stop_id: s, arrival: { time: P_NOW + m * 60 } })) });
const PTRIPS = [ptrip("cta:sched:55:1:1", [["cta:e1", 8], ["cta:e2", 11], ["cta:e3", 14]]), ptrip("cta:sched:55:0:1", [["cta:w1", 6], ["cta:w2", 9], ["cta:w3", 12]])];

test("planner: a CTA scheduled trip is a timed wait labeled schedule (never live), in the right direction", () => {
  const r = plan({ from: { lat: 41.7948, lon: -87.6100 }, to: { lat: 41.7948, lon: -87.5900 }, now: P_NOW, data: PDATA(PTRIPS) });
  const leg = r.options.flatMap((o) => o.legs).find((l) => l.type === "bus");
  ok(leg, "a CTA option: " + JSON.stringify(r.options.map((o) => o.key)));
  eq([leg.rid, leg.board.id, leg.alight.id, leg.source, leg.waitLive, leg.waitTimed], ["cta:55", "cta:e1", "cta:e3", "schedule", false, true]);
  eq([leg.boardT, leg.alightT], [P_NOW + 480, P_NOW + 840], "the scheduled times");
  eq(leg.tripId, "cta:sched:55:1:1");
});

test("planner: a CTA ride never runs past the terminal into the other direction", () => {
  // from A (WB end) to B (WB, further back along Westbound): only an Eastbound ride A>B or walking makes sense
  const r = plan({ from: { lat: 41.7952, lon: -87.6100 }, to: { lat: 41.7952, lon: -87.6000 }, now: P_NOW, data: PDATA(PTRIPS) });
  for (const l of r.options.flatMap((o) => o.legs).filter((x) => x.type === "bus")) {
    const dirOf = (id) => (id.startsWith("cta:e") ? "E" : "W");
    eq(dirOf(l.board.id), dirOf(l.alight.id), `${l.board.id}>${l.alight.id} stays in one direction`);
  }
});

test("refineWalking: a scheduled CTA departure is missed like a live one when the sidewalk walk is longer", async () => {
  const r = plan({ from: { lat: 41.7948, lon: -87.6100 }, to: { lat: 41.7948, lon: -87.5900 }, now: P_NOW, data: PDATA(PTRIPS) });
  const opt = r.options.find((o) => o.legs.some((l) => l.type === "bus"));
  const slow = async (a, b) => ({ m: 1500, min: 20, coords: [[a.lat, a.lon], [b.lat, b.lon]], source: "router" });
  const out = await refineWalking(opt, { walkRoute: slow, now: P_NOW, data: PDATA(PTRIPS), from: { lat: 41.7948, lon: -87.6100 }, to: { lat: 41.7948, lon: -87.5900 } });
  ok(out === null || out.legs.filter((l) => l.type === "bus").every((l) => l.boardT >= P_NOW + 20 * 60), "never a bus that left before you get there");
});
