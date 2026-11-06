/**
 * Tests for CTA routes on the map (experimental, owner 2026-11-06: "make the bus shapes identifiable to be cta and make
 * their stations square"): map/cta.js and the CTA paths in map/layers.js, map/map.js and map/favorites.js. Needs Leaflet
 * and css/map.css (map.test.html loads both).
 */
import { test, eq, ok, near } from './lib.js';
import { CTA_LINE_WIDTHS, CTA_STOP_MIN_Z, CTA_STOP_PANE, CTA_LINE_MIN_CONTRAST, ctaStopStyle, ctaLineColor, squarePath, markerName } from '../js/map/cta.js';
import { contrast } from '../js/core/esc.js';
import { stackOrder, lineWeight, ctaLineWeight, FOCUS_EXTRA, createNetworkLayer, createBusLayer } from '../js/map/layers.js';
import { createMap } from '../js/map/map.js';
import { P, squareLoop } from './map-fixtures.js';

const routes = { r1: { short: 'CEN', long: 'Central', color: '#FF9900' }, r2: { short: '', long: 'North', color: '#0099CC' },
  'cta:171': { short: '171', long: 'U. of Chicago/Hyde Park', color: '#747477', agency: 'cta' },
  'cta:55': { short: '55', long: 'Garfield', color: '#414145', agency: 'cta' } };
const shapes = { r1: [squareLoop()], r2: [[P(0, -2), P(6, -2)]], 'cta:171': [[P(-1, 1), P(6, 1)]], 'cta:55': [[P(2, -3), P(2, 6)]] };
const routeStops = { r1: ['A', 'B', 'C', 'D', 'A'], r2: ['E', 'F'], 'cta:171': ['cta:1', 'cta:2', 'cta:4'], 'cta:55': ['cta:3', 'cta:4'] };
const at = (name, x, y) => ({ name, lat: P(x, y)[0], lon: P(x, y)[1] });
const stops = { A: at('A st', 0, 0), B: at('B st', 4, 0), C: at('C st', 4, 4), D: at('D st', 0, 4), E: at('E st', 0, -2), F: at('F st', 6, -2),
  'cta:1': at('Ellis & 55th (EB)', -1, 1), 'cta:2': at('Woodlawn & 55th (EB)', 6, 1), 'cta:3': at('57th & Garfield (NB)', 2, -3),
  'cta:4': at('55th & Garfield', 2, 1) };
const stopRoutes = { A: ['r1'], B: ['r1'], C: ['r1'], D: ['r1'], E: ['r2'], F: ['r2'], 'cta:1': ['cta:171'], 'cta:2': ['cta:171'],
  'cta:3': ['cta:55'], 'cta:4': ['cta:171', 'cta:55'] };
const net = (extra = {}) => ({ routes, shapes, routeStops, stopRoutes, stops, hidden: [], focus: null, ...extra });
const bus = (id, rid, x, y, extra = {}) => ({ vehicle: { id, label: String(id).replace('cta:', '') }, trip: { route_id: rid },
  position: { latitude: P(x, y)[0], longitude: P(x, y)[1], bearing: 90 }, timestamp: 1000, ...extra });
const ctaBus = (n, rid, x, y, extra) => ({ ...bus('cta:' + n, rid, x, y, extra), cta: true });

function box(id) {
  const d = document.createElement('div');
  d.id = id;
  d.style.cssText = 'position:absolute;left:-2000px;top:0;width:400px;height:600px';
  document.body.appendChild(d);
  return d;
}
function bareMap(id, z = 15) {
  const host = box(id);
  host.classList.add('sb-map');   // map.css scopes overlay rules to .sb-map (createMap adds it)
  const m = window.L.map(host, { zoomControl: false, attributionControl: false }).setView(P(2, 1), z);
  for (const [n, zi] of Object.entries({ sbLines: 390, sbFocusLines: 394, sbStops: 420 })) m.createPane(n).style.zIndex = zi;
  return m;
}
const click = (el) => el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
const routePaths = (pane) => [...pane.querySelectorAll('path.sb-route')];

test('CTA helpers: thinner line widths, square stop sizes, square path, names that say CTA', () => {
  eq([13, 14, 15, 16, 17, 18].map(ctaLineWeight), [1.25, 1.5, 2, 2.5, 3, 3.5]);
  eq(CTA_LINE_WIDTHS.length, 6);
  for (const z of [13, 14, 14.5, 15, 16, 17, 18]) ok(ctaLineWeight(z) < lineWeight(z), 'a CTA line is thinner than a shuttle line at z' + z);
  eq(ctaStopStyle(14), { radius: 4, weight: 2 }); eq(ctaStopStyle(16), { radius: 4, weight: 2 }); eq(ctaStopStyle(17), { radius: 5, weight: 2 });
  eq(CTA_STOP_MIN_Z, 16, 'CTA stops (every block, both sides) show from zoom 16 unless their route is in focus');
  eq(squarePath(10, 10, 4, 0), 'M6,6H14V14H6Z', 'a plain square');
  const d = squarePath(10, 10, 4, 1);
  eq((d.match(/A/g) || []).length, 4, 'four rounded corners'); ok(/H/.test(d) && /V/.test(d) && d.endsWith('Z'), 'straight sides, closed');
  ok(squarePath(0, 0, 2, 9).includes('A1,1'), 'corner never more than half the half-side');
  eq(markerName(false, 'CEN', 'Central'), 'Route CEN bus', 'shuttle names unchanged');
  eq(markerName(false, 'CEN', 'Central', 2), 'Bus 2, Central');
  eq(markerName(true, '171', 'U. of Chicago/Hyde Park'), 'CTA bus 171, U. of Chicago/Hyde Park');
  eq(markerName(true, '55', 'Garfield', 2), 'Bus 2, CTA 55 Garfield');
  eq(markerName(true, '171', '171'), 'CTA bus 171', 'no long name: no repeat');
});

test('stackOrder: CTA lines under shuttle lines unless the rider ordered or focused them', () => {
  const ids = ['cta:171', 'r1', 'cta:55', 'r2'];
  const b = stackOrder(ids, {}).back;
  eq(b.length, 4);
  ok(Math.max(b.indexOf('cta:171'), b.indexOf('cta:55')) < Math.min(b.indexOf('r1'), b.indexOf('r2')), 'no order: every CTA line below every shuttle line ' + b);
  eq(stackOrder(ids, { order: ['r1', 'r2', 'cta:171', 'cta:55'] }).back, ['cta:55', 'cta:171', 'r2', 'r1'], 'drawOrder-style full order (shuttles first)');
  eq(stackOrder(ids, { order: ['cta:55'] }).back.at(-1), 'cta:55', 'the rider put a CTA route first: it is drawn on top');
  const f = stackOrder(ids, { focus: ['cta:171'] });
  eq(f.front, ['cta:171'], 'a focused CTA route is drawn above everything');
  ok(f.back.indexOf('cta:55') < f.back.indexOf('r1'), 'the rest keeps shuttles above CTA');
  eq(stackOrder(ids, { hidden: ['cta:55'] }).back.includes('cta:55'), false, 'a hidden CTA route is not drawn');
});

test('network: CTA lines thinner and under the shuttle lines; square stops in their own pane from zoom 16', () => {
  const m = bareMap('t-cta-net');
  const taps = [];
  const layer = createNetworkLayer(m, { onStopTap: (id) => taps.push(id) });
  ok(layer.draw(net()), 'first draw');
  const lines = routePaths(m.getPane('sbLines'));
  const cta = lines.filter((p) => p.classList.contains('sb-route-cta')), shuttle = lines.filter((p) => !p.classList.contains('sb-route-cta'));
  eq(cta.length, 2); eq(shuttle.length, 2);
  eq(cta.map((p) => p.getAttribute('stroke-width')), ['2', '2'], 'CTA lines 2 px at z15');
  eq(shuttle.map((p) => p.getAttribute('stroke-width')), ['3', '3'], 'shuttle lines 3 px at z15');
  ok(lines.indexOf(cta[1]) < lines.indexOf(shuttle[0]), 'CTA lines come first in the pane: drawn under the shuttle lines');
  eq(cta.map((p) => p.getAttribute('stroke')).sort(), ['#414145', '#747477'], 'CTA route colors');
  const pane = m.getPane(CTA_STOP_PANE);
  ok(pane && +pane.style.zIndex > 410 && +pane.style.zIndex < +m.getPane('sbStops').style.zIndex, 'CTA stop pane above names, under shuttle stops');
  eq(m.getContainer().querySelectorAll('path.sb-stop-cta').length, 0, 'z15: CTA stops not drawn');
  eq(m.getPane('sbStops').querySelectorAll('path.sb-stop').length, 6, 'z15: shuttle stops drawn');
  eq(layer.stopPoints().length, 6, 'building names avoid only the stops drawn from zoom 14');

  m.setZoom(16, { animate: false }); layer.restyle();
  const sq = [...pane.querySelectorAll('path.sb-stop-cta')];
  eq(sq.length, 4, 'z16: every CTA stop, in the CTA pane');
  const mid = sq.find((p) => p.getAttribute('d') !== 'M0 0'), d = mid.getAttribute('d');   // out of view = 'M0 0' (Leaflet)
  ok(/H/.test(d) && /V/.test(d) && !/a/.test(d), 'a square path (no circle arcs): ' + d);
  const bb = mid.getBBox();
  near(bb.width, 8, 0.01, '8 px square at z16'); near(bb.height, 8, 0.01);
  eq(sq.filter((p) => p.classList.contains('sb-stop-multi')).length, 1, 'the stop of two CTA routes gets the neutral stroke');
  ok(sq.every((p) => p.classList.contains('sb-stop')), 'same fill rule as the round stops');
  const round = [...m.getPane('sbStops').querySelectorAll('path.sb-stop')].map((p) => p.getAttribute('d')).filter((x) => x !== 'M0 0');
  ok(round.length && round.every((x) => /a/.test(x)), 'shuttle stops stay round');
  click(pane.querySelector('path.sb-halo'));
  ok(taps.length === 1 && taps[0].startsWith('cta:'), 'CTA stop tap via its 44 px halo: ' + taps[0]);
  eq([...pane.querySelectorAll('path.sb-halo')].find((p) => p.getAttribute('d') !== 'M0 0').getBBox().width, 44, 'same 44 px tap halo');
  m.setZoom(17, { animate: false }); layer.restyle();
  near([...pane.querySelectorAll('path.sb-stop-cta')].find((p) => p.getAttribute('d') !== 'M0 0').getBBox().width, 10, 0.01, '10 px square from z17');
  eq(routePaths(m.getPane('sbLines')).filter((p) => p.classList.contains('sb-route-cta'))[0].getAttribute('stroke-width'), '3', 'restyle: CTA 3 px at z17');

  m.setZoom(15, { animate: false }); layer.restyle();
  layer.draw(net({ focus: ['cta:171'] }));
  const front = routePaths(m.getPane('sbFocusLines'));
  eq(front.length, 1); eq(front[0].getAttribute('stroke-width'), String(2 + FOCUS_EXTRA), 'a focused CTA line: 2 + FOCUS_EXTRA');
  eq(pane.querySelectorAll('path.sb-stop-cta').length, 3, 'focused CTA route (its route page): its stops from zoom 14, like a shuttle route');
  eq(m.getPane('sbStops').querySelectorAll('path.sb-stop').length, 0, 'the other routes\' stops are not drawn while it is in focus');
  eq(layer.stopPoints().length, 3, 'its stops count for the building names');
  layer.draw(net({ hidden: ['cta:171', 'cta:55'] }));
  m.setZoom(16, { animate: false }); layer.restyle();
  eq(m.getContainer().querySelectorAll('path.sb-route-cta, path.sb-stop-cta').length, 0, 'hidden CTA routes: no line, no stop');
  m.remove();
});

test('CTA line colors keep 3:1 against the land in both themes; the theme switch re-colors without a rebuild', () => {
  const LIGHT = '#F5F3EE', DARK = '#202124';
  for (const c of ['#747477', '#414145', '#B71234', '#0065BD', '#99999C']) {
    ok(contrast(ctaLineColor(c, true), DARK) >= CTA_LINE_MIN_CONTRAST, c + ' on the dark land');
    ok(contrast(ctaLineColor(c, false), LIGHT) >= CTA_LINE_MIN_CONTRAST, c + ' on the light land');
  }
  eq(ctaLineColor('#414145', false), '#414145', 'already 3:1 on light: the route color itself');
  eq(ctaLineColor('#747477', true), '#747477', 'already 3:1 on dark: unchanged');
  ok(ctaLineColor('#414145', true) !== '#414145' && contrast(ctaLineColor('#414145', true), '#FFFFFF') > 2, 'key-route gray lifted on dark, still a gray, not white');
  ok(contrast('#414145', DARK) < 2, 'why: CTA key-route gray is under 2:1 on the dark land');

  const m = bareMap('t-cta-dark', 16);
  const layer = createNetworkLayer(m, { onStopTap: () => {} });
  layer.draw(net());
  const line55 = () => [...m.getContainer().querySelectorAll('path.sb-route-cta')].find((p) => p.getAttribute('stroke').toUpperCase() !== '#747477');
  const before = [...m.getContainer().querySelectorAll('path')];
  eq(line55().getAttribute('stroke').toUpperCase(), '#414145', 'light: the route color');
  layer.setDark(true);
  eq(line55().getAttribute('stroke').toUpperCase(), ctaLineColor('#414145', true), 'dark: lifted');
  const sq55 = [...m.getContainer().querySelectorAll('path.sb-stop-cta:not(.sb-stop-multi)')].map((p) => p.getAttribute('stroke').toUpperCase());
  ok(sq55.includes(ctaLineColor('#414145', true)), 'its stop outlines too');
  ok([...m.getContainer().querySelectorAll('path.sb-route:not(.sb-route-cta)')].map((p) => p.getAttribute('stroke').toUpperCase()).sort().join() === '#0099CC,#FF9900', 'shuttle lines keep their colors');
  ok([...m.getContainer().querySelectorAll('path')].every((p, i) => p === before[i]), 'no rebuild');
  layer.draw(net({ hidden: ['r2'] }));
  eq(line55().getAttribute('stroke').toUpperCase(), ctaLineColor('#414145', true), 'a redraw while dark keeps the dark colors');
  layer.setDark(false);
  eq(line55().getAttribute('stroke').toUpperCase(), '#414145', 'back to light');
  m.remove();
});

test('network: a plan dims CTA stops and lines like the rest', () => {
  const m = bareMap('t-cta-dim', 16);
  const layer = createNetworkLayer(m, { onStopTap: () => {} });
  layer.draw(net(), true);
  ok([...m.getContainer().querySelectorAll('path.sb-route-cta')].every((p) => p.getAttribute('stroke-opacity') === '0.2'), 'CTA lines at 0.2');
  ok([...m.getContainer().querySelectorAll('path.sb-stop-cta')].every((p) => p.getAttribute('stroke-opacity') === '0.4'), 'CTA stops at 0.4');
  m.remove();
});

test('bus layer: a CTA bus is a squared badge with a "CTA" tag and says CTA; shuttle badges unchanged', () => {
  const m = bareMap('t-cta-bus');
  const taps = [];
  const layer = createBusLayer(m, { onBusTap: (b) => taps.push(b) }, { reduce: () => true });
  const o = { routes, shapes, hidden: [], focus: null, nowS: 1010 };
  eq(layer.draw([bus(1, 'r1', 1, 1), ctaBus(8123, 'cta:171', 3, 1)], o), 2);
  const icons = () => [...m.getContainer().querySelectorAll('.sb-busicon')];
  const ctaIcon = () => icons().find((e) => e.querySelector('.sb-bus-cta')), shIcon = () => icons().find((e) => !e.querySelector('.sb-bus-cta'));
  const c = ctaIcon(), s = shIcon();
  ok(c && s, 'one of each');
  const badge = c.querySelector('.sb-bus'), tag = badge.querySelector('.sb-bus-cta-tag');
  eq(tag?.textContent, 'CTA', 'the tag says CTA (text, not color)');
  eq(tag.getAttribute('aria-hidden'), 'true', 'the marker name carries it for screen readers');
  ok(tag.nextElementSibling === badge.querySelector('.sb-bus-tx'), 'the tag comes before the route number');
  eq(badge.querySelector('.sb-bus-tx').textContent, '171');
  eq(c.getAttribute('aria-label'), 'CTA bus 171, U. of Chicago/Hyde Park');
  eq(c.getAttribute('title'), 'CTA bus 171, U. of Chicago/Hyde Park');
  eq(s.getAttribute('aria-label'), 'Route CEN bus');
  ok(!s.querySelector('.sb-bus-cta-tag') && !s.querySelector('.cta') && !c.querySelector('.cta'), 'no tag on a shuttle; no bare .cta class (a shell button style)');
  const cs = getComputedStyle(badge), ss = getComputedStyle(s.querySelector('.sb-bus'));
  eq(cs.borderTopLeftRadius, '3px', 'squared corners'); eq(ss.borderTopLeftRadius, '7px', 'the shuttle badge stays rounded');
  eq(getComputedStyle(tag).backgroundColor, cs.borderTopColor, 'the tag is printed in the ring color');
  ok(getComputedStyle(tag).color !== getComputedStyle(tag).backgroundColor, 'tag ink differs from its ground');
  eq(cs.height, '26px', 'same height as a shuttle badge (tap size, heading notch)');
  ok(badge.querySelector('.sb-bus-hd') && !badge.classList.contains('no-hd'), 'heading notch shown');
  click(c);
  eq(taps.at(-1), { id: 'cta:8123', rid: 'cta:171', label: '8123' }, 'a tap opens it like a shuttle bus (onBusTap)');

  layer.draw([bus(1, 'r1', 1, 1), ctaBus(8123, 'cta:171', 3, 1, { timestamp: 900 })], o);
  ok(ctaIcon().querySelector('.sb-bus').classList.contains('is-stale'), 'stale after 60 s');
  layer.draw([bus(1, 'r1', 1, 1), ctaBus(8123, 'cta:171', 3, 1)], { ...o, focus: ['r1'] });
  ok(ctaIcon().classList.contains('is-faded') && !shIcon().classList.contains('is-faded'), 'another route in focus: the CTA bus fades');
  layer.draw([bus(1, 'r1', 1, 1), ctaBus(8123, 'cta:171', 3, 1)], { ...o, focus: ['cta:171'] });
  ok(!ctaIcon().classList.contains('is-faded') && shIcon().classList.contains('is-faded'), 'its own route page: the CTA bus at full strength');
  layer.draw([bus(1, 'r1', 1, 1), ctaBus(8123, 'cta:171', 3, 1)], { ...o, selected: 'cta:8123' });
  ok(ctaIcon().querySelector('.sb-bus').classList.contains('is-picked'), 'the picked CTA bus is highlighted');
  layer.draw([bus(1, 'r1', 1, 1), ctaBus(8123, 'cta:171', 3, 1)], { ...o, hidden: ['cta:171'] });
  ok(!ctaIcon(), 'a hidden CTA route\'s bus is not drawn');

  layer.draw([bus(1, 'r1', 1, 1), ctaBus(8123, 'cta:171', 3, 1), ctaBus(8001, 'cta:171', 5, 1)], o);
  const named = icons().map((e) => e.getAttribute('aria-label')).sort();
  eq(named, ['Bus 1, CTA 171 U. of Chicago/Hyde Park', 'Bus 2, CTA 171 U. of Chicago/Hyde Park', 'Route CEN bus'], 'two CTA buses on a line are numbered like shuttles');
  ok(icons().filter((e) => e.querySelector('.sb-bus-cta .sb-bus-num')).length === 2, 'the number sits inside the CTA badge');
  ok(layer.setYou('cta:8123') && ctaIcon().querySelector('.sb-bus.is-you .sb-you-ring'), 'riding a CTA bus: the You ring');
  eq(getComputedStyle(ctaIcon().querySelector('.sb-you-ring')).borderTopLeftRadius, '8px', 'a squared You ring');
  m.remove();
});

test('bus layer: missing buses are held per feed (CTA buses never keep a shuttle on the map, or the reverse)', () => {
  const m = bareMap('t-cta-hold');
  const layer = createBusLayer(m, { onBusTap: () => {} }, { reduce: () => true });
  const o = (t) => ({ routes, shapes, hidden: [], focus: null, nowS: t });
  const count = (sel) => m.getContainer().querySelectorAll(sel).length;
  layer.draw([bus(1, 'r1', 1, 1), bus(2, 'r2', 3, -2), ctaBus(7, 'cta:171', 3, 1), ctaBus(8, 'cta:55', 2, 3)], o(1010));
  eq(count('.sb-bus'), 4);
  layer.draw([bus(1, 'r1', 1, 1), ctaBus(7, 'cta:171', 3, 1)], o(1020));
  eq(count('.sb-bus'), 4, 'one of each feed missing while others of its feed report: kept (MISSING_S)');
  layer.draw([ctaBus(7, 'cta:171', 3, 1), ctaBus(8, 'cta:55', 2, 3)], o(1030));
  eq(count('.sb-bus:not(.sb-bus-cta)'), 0, 'Passio sends no bus: the shuttles go at once, even while CTA buses report');
  eq(count('.sb-bus-cta'), 2);
  layer.draw([bus(1, 'r1', 1, 1)], o(1040));
  eq(count('.sb-bus-cta'), 0, 'CTA sends no bus: the CTA buses go at once, even while shuttles report');
  eq(count('.sb-bus'), 1);
  m.remove();
});

test('MapApi: a CTA stop\'s selection ring, picker highlight and favorite badge are square', () => {
  box('t-cta-api');
  const api = createMap('t-cta-api');
  const m = api.leaflet, el = m.getContainer();
  api.drawNetwork(net());
  const s = stops['cta:1'];
  api.setSelectedStop({ id: 'cta:1', lat: s.lat, lon: s.lon, name: s.name });
  const ring = el.querySelector('path.sb-sel');
  ok(ring.classList.contains('sb-sel-cta') && /H/.test(ring.getAttribute('d')) && !/a/.test(ring.getAttribute('d')), 'square selection ring on a CTA stop');
  ok(el.querySelector('.sb-sel-label')?.textContent === s.name, 'its name label as for any stop');
  api.setSelectedStop({ id: 'A', lat: stops.A.lat, lon: stops.A.lon });
  const r2 = el.querySelector('path.sb-sel');
  ok(!r2.classList.contains('sb-sel-cta') && /a/.test(r2.getAttribute('d')), 'a shuttle stop keeps the round ring');

  api.highlightStops([{ id: 'cta:4', lat: stops['cta:4'].lat, lon: stops['cta:4'].lon }, { id: 'B', lat: stops.B.lat, lon: stops.B.lon }], { onPick: () => {} });
  eq(el.querySelectorAll('path.sb-hl').length, 2);
  const hl = el.querySelector('path.sb-hl-cta');
  ok(hl && /H/.test(hl.getAttribute('d')), 'square picker highlight on the CTA stop');
  api.highlightStops(null);

  api.drawFavorites([{ id: 'cta:1', name: s.name, lat: s.lat, lon: s.lon }, { id: 'A', name: 'A st', lat: stops.A.lat, lon: stops.A.lon }]);
  const favs = [...el.querySelectorAll('.sb-favicon')];
  eq(favs.length, 2);
  const cf = favs.find((f) => f.querySelector('.sb-fav-cta')), sf = favs.find((f) => !f.querySelector('.sb-fav-cta'));
  eq(cf.getAttribute('aria-label'), 'Favorite CTA stop: ' + s.name);
  eq(sf.getAttribute('aria-label'), 'Favorite stop: A st');
  eq(getComputedStyle(cf.querySelector('.sb-fav')).borderTopLeftRadius, '5px', 'a CTA favorite: rounded-square star badge');
  eq(getComputedStyle(sf.querySelector('.sb-fav')).borderTopLeftRadius, '50%', 'a shuttle favorite: the round disc');
  api.setSelectedStop({ id: 'cta:1', lat: s.lat, lon: s.lon, name: s.name });
  const fr = el.querySelector('path.sb-sel');
  ok(fr.classList.contains('sb-sel-fav') && fr.classList.contains('sb-sel-cta') && /H/.test(fr.getAttribute('d')), 'a selected CTA favorite: a wide square ring');
  m.remove();
});
