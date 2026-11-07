import { test, eq, ok } from './lib.js';
import { createStore } from '../js/core/store.js';
import { loadStatic, deriveStopRoutes, cleanSlice, cleanLandmarks } from '../js/data/static.js';
import { res, stubFetch } from './data-helpers.js';

const FILES = {
  'routes.json': { r1: { short: 'A', long: 'Alpha', color: '#ff0000', text_color: '#ffffff' }, r2: { short: 'B', long: 'Beta', color: '#00ff00', text_color: '#000000' } },
  'stops.json': { s1: { name: 'One', lat: 41.79, lon: -87.6 }, s2: { name: 'Two', lat: '41.80', lon: '-87.59' }, bad: { name: 'Bad', lat: 'x', lon: 1 } },
  'shapes.json': { r1: [[[41.79, -87.6], [41.8, -87.59]]], r2: [] },
  'route_stops.json': { r1: ['s1', 's2', 's1'], r2: ['s2'] },
  'stop_addresses.json': { s1: { address: '1 Main St' }, s2: { street: 'no address field' } },
  'service.json': { generated: 'x', feed: { start: '2026-10-07', end: '2026-11-07' }, routes: {
    r1: { days: { mon: { first: '07:00', last: '19:00', trips: 3, buses: [] }, sat: 'bad' }, exceptions: [{ date: '2026-11-26', type: 'removed', hours: null }, 5] },
    r2: 'bad' } },
  'landmarks.json': { v: 1, l: [['Regenstein Library', 41.792, -87.6, 1, 'library', 'Joseph Regenstein Library'], ['bad', 'x', 1, 1], ['No tier', 41.79, -87.6, 7]] },
  'corridors.json': { note: 'x', from: '2026-10-10', to: '2026-11-06', valid_until: '2026-12-21', cell_m: 25, routes: {
    r1: { shape: { n: 2, m: 1400 }, pts: [[41.795, -87.6], ['41.796', '-87.6'], ['x', 1], 'junk'] },
    r2: { shape: { n: 0, m: 0 }, pts: [] }, r3: { shape: 'x', pts: [] }, r4: { shape: { n: 5, m: 900 } } } },
};
const fileOf = (url) => url.split('data/').pop();   // 'routes.json', 'cta/routes.json'
const okFetch = (overrides = {}) => stubFetch((url) => {
  const f = fileOf(url);
  if (f in overrides) return overrides[f]();
  return res(FILES[f]);
});

test('static: loads all files, derives stopRoutes, sets staticLoaded in one patch', async () => {
  const store = createStore({ staticLoaded: false });
  let notes = 0;
  store.subscribe(() => notes++);
  const f = okFetch();
  const out = await loadStatic(store, { base: 'data/', fetch: f });
  const s = store.get();
  eq(out.failed, []);
  eq(s.staticLoaded, true);
  eq(Object.keys(s.routes), ['r1', 'r2']);
  eq(Object.keys(s.stops), ['s1', 's2'], 'invalid stop dropped');
  eq(s.stops.s2.lat, 41.8, 'string coords coerced');
  eq(s.routeStops.r1, ['s1', 's2', 's1'], 'loop kept (first==last)');
  eq(s.stopRoutes, { s1: ['r1'], s2: ['r1', 'r2'] });
  eq(s.addresses, { s1: { address: '1 Main St' } });
  eq(Object.keys(s.service.routes), ['r1'], 'bad service route dropped');
  eq(s.service.routes.r1.days.mon.first, '07:00');
  eq([s.service.routes.r1.days.sat, s.service.routes.r1.days.sun], [null, null], 'missing/bad days -> null');
  eq(s.service.routes.r1.exceptions.length, 1, 'bad exception dropped');
  ok(f.calls.every((c) => c.url.startsWith('data/')), 'uses base');
  await new Promise((r) => setTimeout(r, 0));
  eq(notes, 1, 'single store notification');
});

test('static: a required file failing leaves an empty slice, retries once, still loads', async () => {
  const store = createStore({});
  let stopCalls = 0;
  const f = okFetch({ 'stops.json': () => { stopCalls++; return res(null, 500); } });
  const out = await loadStatic(store, { fetch: f });
  const s = store.get();
  eq(stopCalls, 2, 'retried once');
  eq(out.failed, ['stops.json']);
  eq(s.stops, {});
  eq(Object.keys(s.routes).length, 2, 'other files still loaded');
  eq(s.stopRoutes.s2, ['r1', 'r2']);
  eq(s.staticLoaded, true);
});

test('static: optional stop_addresses 404 -> addresses {} without retry', async () => {
  const store = createStore({});
  let n = 0;
  const f = okFetch({ 'stop_addresses.json': () => { n++; return res(null, 404); } });
  const out = await loadStatic(store, { fetch: f });
  eq(n, 1);
  eq(out.failed, ['stop_addresses.json']);
  eq(store.get().addresses, {});
  eq(Object.keys(store.get().stops).length, 2);
});

test('static: optional service.json 404 -> service {} without retry, never blocks', async () => {
  const store = createStore({});
  let n = 0;
  const f = okFetch({ 'service.json': () => { n++; return res(null, 404); } });
  const out = await loadStatic(store, { fetch: f });
  eq(n, 1);
  eq(out.failed, ['service.json']);
  eq(store.get().service, {});
  eq(store.get().staticLoaded, true);
  eq(Object.keys(store.get().routes).length, 2);
});

test('static: bad JSON, thrown fetch and non-object bodies never reject', async () => {
  const store = createStore({});
  const f = okFetch({
    'shapes.json': () => res(() => { throw new SyntaxError('bad json'); }),
    'routes.json': () => { throw new TypeError('Failed to fetch'); },
    'route_stops.json': () => res([1, 2, 3]),
  });
  const out = await loadStatic(store, { fetch: f });
  eq(out.failed.sort(), ['route_stops.json', 'routes.json', 'shapes.json']);
  const s = store.get();
  eq(s.shapes, {}); eq(s.routes, {}); eq(s.routeStops, {}); eq(s.stopRoutes, {});
  eq(Object.keys(s.stops).length, 2);
  eq(s.staticLoaded, true);
});

test('static: everything failing still sets staticLoaded with empty slices', async () => {
  const store = createStore({});
  const out = await loadStatic(store, { fetch: async () => { throw new TypeError('offline'); } });
  eq(out.failed.length, 8);
  const s = store.get();
  eq([s.routes, s.stops, s.shapes, s.routeStops, s.stopRoutes, s.addresses, s.service], [{}, {}, {}, {}, {}, {}, {}]);
  eq(s.landmarks, [], 'map labels: an empty list');
  eq(s.corridors, {}, 'learned corridors: none (every route keeps the E27b rule)');
  eq(s.staticLoaded, true);
});

test('static: landmarks (map labels) load as a list, bad rows dropped', async () => {
  const store = createStore({});
  await loadStatic(store, { base: 'data/', fetch: okFetch() });
  eq(store.get().landmarks, [{ name: 'Regenstein Library', lat: 41.792, lon: -87.6, tier: 1, kind: 'library', osm: 'Joseph Regenstein Library', until: null }]);
  eq(cleanLandmarks(null), []); eq(cleanLandmarks({ l: 'x' }), []);
  eq(cleanLandmarks({ l: [['A', '41.8', '-87.6', '2']] })[0], { name: 'A', lat: 41.8, lon: -87.6, tier: 2, kind: '', osm: 'A', until: null });
  eq(cleanLandmarks({ l: [['G', 41.8, -87.6, 1, 'dorm', 'G', 15.5]] })[0].until, 15.5, 'a group name hides from that zoom');
  // easter eggs (owner 2026-10-14): nicknames by row index in the file, kept when an earlier bad row drops
  const eg = cleanLandmarks({ l: [['bad', 'x', 1, 1], ['Reg', 41.8, -87.6, 1], ['Cobb', 41.79, -87.6, 2]], eggs: [[1, ' The Reg '], [2, ''], ['x', 'no'], [9, 'gone']], egg_zoom: 17.5 });
  eq(eg.map((x) => [x.name, x.egg, x.eggZ]), [['Reg', 'The Reg', 17.5], ['Cobb', undefined, undefined]]);
  eq(cleanLandmarks({ l: [['Reg', 41.8, -87.6, 1]], eggs: [[0, 'The Reg']] })[0].egg, undefined, 'no egg_zoom: no nicknames');
  eq(cleanLandmarks({ l: [['Reg', 41.8, -87.6, 1]], eggs: 'x', egg_zoom: 17 })[0].egg, undefined);
});

test('static: corridors.json (streets the buses really drive, RouteKnower E27c) keeps only routes the app can check', async () => {
  const store = createStore({});
  await loadStatic(store, { base: 'data/', fetch: okFetch() });
  const c = store.get().corridors;
  eq(c.valid_until, '2026-12-21');
  eq(c.routes, { r1: { shape: { n: 2, m: 1400 }, pts: [[41.795, -87.6], [41.796, -87.6]] } },
    'bad points dropped; a route without a usable line signature or points is dropped (it keeps the E27b rule)');
  eq(cleanSlice('corridors', { routes: 'x' }).routes, {});
});

test('static: deriveStopRoutes / cleanSlice edge cases', () => {
  eq(deriveStopRoutes({ a: ['1', '2', '1'], b: ['2'], c: null }), { 1: ['a'], 2: ['a', 'b'] });
  eq(deriveStopRoutes(undefined), {});
  eq(cleanSlice('stops', null), {});
  eq(cleanSlice('routeStops', { a: ['1', null, 2] }), { a: ['1', '2'] });
  eq(cleanSlice('routes', { a: { short: 5 } }).a.short, '5');
  // Passio's own ids for a route (DC-009): strings, empties dropped; junk = no list
  eq(cleanSlice('routes', { a: { alias_ids: [38734, '', null, '38809'] } }).a.alias_ids, ['38734', '38809']);
  eq('alias_ids' in cleanSlice('routes', { a: { alias_ids: 'x' } }).a, false);
});

test('static: real web/data files load and cross-reference', async () => {
  const store = createStore({});
  const out = await loadStatic(store, { base: '../data/' });
  const s = store.get();
  eq(out.failed, []);
  ok(Object.keys(s.routes).length > 0, 'routes');
  ok(Object.keys(s.stops).length > 0, 'stops');
  ok(Object.keys(s.stopRoutes).length > 0, 'stopRoutes');
  ok(Object.keys(s.service.routes || {}).length > 0, 'service.json routes');
  for (const rid of Object.keys(s.service.routes)) ok(s.routes[rid], 'service route exists: ' + rid);
  for (const [rid, ids] of Object.entries(s.routeStops)) for (const id of ids) ok(s.stopRoutes[id].includes(rid), 'stopRoutes covers ' + id);
});

const CTA = {
  'cta/routes.json': { 'cta:171': { short: '171', long: 'U. of Chicago/Hyde Park', color: '#747477', text_color: '#FFFFFF', agency: 'cta' },
    r1: { short: 'X', long: 'not namespaced: dropped' }, 'cta:9': { short: '9', long: 'no stops: dropped' } },
  'cta/stops.json': { 'cta:1': { name: 'Ellis (EB)', lat: 41.795, lon: -87.601 }, 'cta:2': { name: 'University (EB)', lat: 41.795, lon: -87.598 }, s1: { name: 'hijack', lat: 0, lon: 0 } },
  'cta/shapes.json': { 'cta:171': [[[41.795, -87.601], [41.795, -87.598]]] },
  'cta/route_stops.json': { 'cta:171': ['cta:1', 'cta:2'], r2: ['s1'] },
  'cta/service.json': { feed: { start: '2026-11-01', end: '2026-11-30' }, routes: { 'cta:171': { days: { mon: { first: '06:00', last: '18:00', trips: 9, buses: [] } }, exceptions: [] }, r1: { days: {}, exceptions: [] } } },
  'cta/patterns.json': { 'cta:171': [{ dir: 'Southbound', stops: ['cta:2', 'cta:1'] }, { dir: 'Northbound', stops: ['cta:1', 'cta:2'] }], r1: [{ dir: 'x', stops: ['s1', 's2'] }] },
};

test('static: CTA files merge into the same slices with cta: ids only; a shuttle id in a CTA file is dropped', async () => {
  const store = createStore({});
  const f = stubFetch((url) => { const k = fileOf(url); return res(k in CTA ? CTA[k] : FILES[k]); });
  const out = await loadStatic(store, { fetch: f });
  const s = store.get();
  eq(out.failed, []);
  eq(out.ctaFailed, []);
  eq(Object.keys(s.routes), ['r1', 'r2', 'cta:171'], 'shuttles first, then CTA; the CTA file cannot replace r1');
  eq(s.routes.r1.long, 'Alpha');
  eq(s.routes['cta:171'].agency, 'cta');
  eq(s.stops.s1.name, 'One', 'a CTA file cannot replace a shuttle stop');
  eq(s.routeStops['cta:171'], ['cta:1', 'cta:2']);
  eq(s.routeStops.r2, ['s2']);
  eq(s.stopRoutes['cta:1'], ['cta:171']);
  eq(Object.keys(s.service.routes), ['r1', 'cta:171']);
  eq(s.service.routes.r1.days.mon.first, '07:00', "the shuttle's hours stay");
  eq(s.service.ctaFeed, { start: '2026-11-01', end: '2026-11-30' });
  eq(s.ctaPatterns, { 'cta:171': [{ dir: 'Southbound', stops: ['cta:2', 'cta:1'] }, { dir: 'Northbound', stops: ['cta:1', 'cta:2'] }] });
});

test('static: CTA files missing -> no CTA routes, shuttles unaffected, listed apart in ctaFailed', async () => {
  const store = createStore({});
  const out = await loadStatic(store, { fetch: okFetch() });
  eq(out.failed, []);
  eq(out.ctaFailed.length, 6);
  eq(Object.keys(store.get().routes), ['r1', 'r2']);
  eq(store.get().ctaPatterns, {});
});
