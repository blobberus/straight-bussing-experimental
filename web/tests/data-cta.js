// Tests for data/cta-live.js: CTA times and buses kept apart from the shuttle feed (experimental, owner 2026-11-06)
import { test, eq, ok } from './lib.js';
import { createStore } from '../js/core/store.js';
import { res, stubFetch, sleep } from './data-helpers.js';
import { parseCtaTime, parseCtaLive, demoCta, startCtaLive, CTA_LIVE_URL, FALLBACK_S } from '../js/data/cta-live.js';
import { decodeSchedule } from '../js/core/ctasched.js';
import { chicagoUnix } from '../js/core/timeactive.js';
import { initialState } from '../js/state.js';

const at = (y, m, d, h, mi) => chicagoUnix(y, m, d, h, mi);
const NOW = at(2026, 11, 6, 8, 34);   // Friday
const PATTERNS = { 'cta:55': [{ dir: 'Westbound', stops: ['cta:4', 'cta:5'] }, { dir: 'Eastbound', stops: ['cta:1', 'cta:2', 'cta:6'] }] };
const SCHED = { v: 1, services: { WK: { days: '1111100', start: '2026-11-01', end: '2026-11-30' } },
  routes: { 'cta:55': [{ dir: 'Westbound', profiles: [[0, 2]], trips: { WK: [600, 0] } },
    { dir: 'Eastbound', profiles: [[0, 3, 10]], trips: { WK: [510, 0, 30, 0] } }] } };
const STATIC = {
  staticLoaded: true,
  routes: { '1075': { short: '', long: 'North' }, 'cta:55': { short: '55', long: 'Garfield', agency: 'cta' } },
  stops: { 'cta:1': { name: 'Ellis (EB)', lat: 41.795, lon: -87.601 }, 'cta:2': { name: 'University (EB)', lat: 41.7951, lon: -87.598 },
    'cta:6': { name: 'MSI', lat: 41.7906, lon: -87.583 }, 'cta:4': { name: 'University (WB)', lat: 41.7953, lon: -87.5981 }, 'cta:5': { name: 'Ellis (WB)', lat: 41.7952, lon: -87.6011 } },
  shapes: { 'cta:55': [[[41.795, -87.601], [41.7951, -87.598], [41.7906, -87.583]]] },
  ctaPatterns: PATTERNS,
};
const store0 = (over = {}) => createStore({ ...initialState(), ...STATIC, ...over });

test('CTA_LIVE_URL ships empty: no live CTA source until the owner sets up the proxy', () => {
  eq(CTA_LIVE_URL, '');
});

test('parseCtaTime: Bus Tracker times are Chicago wall clock, with or without seconds', () => {
  eq(parseCtaTime('20261106 08:34'), NOW);
  eq(parseCtaTime('20261106 08:34:30'), NOW + 30);
  eq(parseCtaTime('20261201 09:00'), at(2026, 12, 1, 9, 0), 'standard time');
  ok(Number.isNaN(parseCtaTime('soon')) && Number.isNaN(parseCtaTime(null)));
});

test('parseCtaLive: Hyde Park routes and stops only, cta: ids, predictions grouped per bus trip, stale reports dropped', () => {
  const j = { ts: NOW, vehicles: [
    { vid: '8123', rt: '55', lat: '41.7951', lon: '-87.599', hdg: '90', tmstmp: '20261106 08:33', tatripid: '1001', des: 'Museum' },
    { vid: '9999', rt: '8', lat: '41.8', lon: '-87.6', hdg: '0', tmstmp: '20261106 08:33' },
    { vid: '7001', rt: '55', lat: '41.79', lon: '-87.6', hdg: '0', tmstmp: '20261106 08:20' },
    { vid: '7002', rt: '55', lat: 'x', lon: '-87.6' }],
    predictions: [
      { vid: '8123', rt: '55', stpid: '6', prdtm: '20261106 08:40', tatripid: '1001' },
      { vid: '8123', rt: '55', stpid: '2', prdtm: '20261106 08:36', tatripid: '1001' },
      { vid: '8123', rt: '55', stpid: '77777', prdtm: '20261106 08:50', tatripid: '1001' },
      { vid: '9999', rt: '8', stpid: '1', prdtm: '20261106 08:37' }] };
  const out = parseCtaLive(j, STATIC, NOW);
  eq(out.buses.map((b) => b.vehicle.id), ['cta:8123'], 'route 8 is not a Hyde Park route; a 14-minute-old report is a ghost; no position');
  const b = out.buses[0];
  eq([b.trip.route_id, b.trip.trip_id, b.vehicle.label, b.position.bearing, b.cta, b.timestamp], ['cta:55', 'cta:1001', '8123', 90, true, NOW - 60]);
  eq(out.trips.length, 1);
  eq(out.trips[0].stop_time_update.map((u) => [u.stop_id, u.arrival.time]), [['cta:2', NOW + 120], ['cta:6', NOW + 360]], 'sorted; unknown stop dropped');
  eq(out.trips[0].vehicle.id, 'cta:8123');
  eq(parseCtaLive({ vehicles: 'x' }, STATIC, NOW), { buses: [], trips: [], feedTs: 0 });
});

test('demoCta: a bus on each trip under way, between its last and next stop, predicting the stops ahead', () => {
  const sched = decodeSchedule(SCHED, PATTERNS);
  const d = demoCta(STATIC, sched, NOW);
  eq(d.buses.length, 1, 'the 8:30 Eastbound trip is under way at 8:34; the 9:00 one is not yet');
  const b = d.buses[0];
  ok(b.cta && b.trip.route_id === 'cta:55' && b.vehicle.id.startsWith('cta:demo-'));
  ok(b.position.longitude > -87.601 && b.position.longitude < -87.583, 'between Ellis and MSI');
  const mine = d.trips.find((t) => t.vehicle.id === b.vehicle.id);
  eq(mine.stop_time_update.map((u) => u.stop_id), ['cta:6'], 'only stops still ahead');
  ok(d.trips.length >= 2, 'the trip starting at 9:00 predicts its stops too');
});

test('startCtaLive off: scheduled times only (sched:true), no CTA bus, only the schedule file is fetched', async () => {
  const store = store0();
  const f = stubFetch((url) => (url.endsWith('cta/schedule.json') ? res(SCHED) : res(null, 404)));
  const h = startCtaLive(store, { url: '', fetch: f, now: () => NOW });
  await h.tick();
  h.stop();
  const s = store.get();
  eq(s.cta.mode, 'off');
  ok(s.ctaSchedule && s.ctaSchedule.routes['cta:55'], 'schedule decoded into the store');
  ok(s.ctaTrips.length >= 1 && s.ctaTrips.every((t) => t.sched === true), 'scheduled entries');
  eq(s.ctaBuses, []);
  eq(s.buses, [], 'the shuttle slices are never written');
  ok(f.calls.every((c) => c.url.endsWith('cta/schedule.json')), 'nothing else requested: ' + f.calls.map((c) => c.url));
});

test('startCtaLive live: the proxy answer fills the CTA slices; a failure is flagged, then the schedule takes over', async () => {
  let t = NOW, up = true;
  const proxy = 'https://example.test/v1/hydepark';
  const f = stubFetch((url) => {
    if (url.endsWith('cta/schedule.json')) return res(SCHED);
    if (url.startsWith(proxy)) return up ? res({ ts: t, vehicles: [{ vid: '8123', rt: '55', lat: 41.7951, lon: -87.599, hdg: 90, tmstmp: '20261106 08:33', tatripid: '1' }],
      predictions: [{ vid: '8123', rt: '55', stpid: '2', prdtm: '20261106 08:36', tatripid: '1' }] }) : res(null, 503);
    return res(null, 404);
  });
  const store = store0({ buses: [{ id: 'shuttle' }] });
  const h = startCtaLive(store, { url: proxy, fetch: f, now: () => t });
  await h.tick();
  let s = store.get();
  eq([s.cta.mode, s.cta.loaded, s.cta.failed, s.cta.lastOk], ['live', true, false, NOW]);
  eq(s.ctaBuses.map((b) => b.vehicle.id), ['cta:8123']);
  ok(s.ctaTrips.length === 1 && !s.ctaTrips[0].sched, 'live predictions, not schedule');
  ok(f.calls.some((c) => c.url.startsWith(proxy) && c.init.cache === 'no-store'));
  ok(!f.calls.some((c) => /lat|lon|stop|user/i.test(c.url.slice(proxy.length))), 'the request carries nothing about the rider');
  up = false; t = NOW + 30;
  await h.tick();
  s = store.get();
  ok(s.cta.failed && s.ctaBuses.length === 1, 'a short outage keeps the last answer, flagged');
  t = NOW + FALLBACK_S + 31;
  await h.tick();
  s = store.get();
  ok(s.cta.failed && s.ctaBuses.length === 0 && s.ctaTrips.every((x) => x.sched), 'after FALLBACK_S: scheduled times, labeled');
  eq(s.buses, [{ id: 'shuttle' }], 'the shuttle buses are untouched');
  h.stop();
});

test('startCtaLive demo: simulated CTA buses, never the network beyond the schedule file', async () => {
  const store = store0();
  const f = stubFetch((url) => (url.endsWith('cta/schedule.json') ? res(SCHED) : res(null, 404)));
  const h = startCtaLive(store, { demo: true, url: 'https://example.test/v1/hydepark', fetch: f, now: () => NOW });
  await h.tick();
  h.stop();
  const s = store.get();
  eq(s.cta.mode, 'demo');
  eq(s.ctaBuses.length, 1);
  ok(f.calls.every((c) => c.url.endsWith('cta/schedule.json')), 'the proxy is never asked in a demo');
  await sleep(0);
});
