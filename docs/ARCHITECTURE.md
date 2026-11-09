# Straight Bussing v2: architecture contract

v2 is the live web app on `main` (merged 2026-10-08; v1 is tag `v1-final`; `v2-rewrite` is kept level with `main`): small ES modules with clear seams, tested. The iPhone app is a native SwiftUI port in `ios/` (StraightBussingKit mirrors `core/*`; `ios/README.md` has the web parity matrix) and follows the web wording; `conversion to appstore.md` is the plan. **Every agent codes against this file. If you must change a signature, change it here in the same edit and say so in your report.**

## Hard constraints
- Static site, **no build step, no Node**. Native ES modules (`<script type="module">`), relative imports with `.js` extension. Leaflet 1.9.4 (`L`) and maplibre-gl 4.7.1 + `@maplibre/maplibre-gl-leaflet` 0.1.4 are CDN **globals** loaded by classic `<script>` tags before `js/main.js`.
- Plain modern JS (ES2022), no TypeScript, no frameworks. Each file < 400 lines. JSDoc on every export. No `eval`, no inline event handlers, no `innerHTML` with unescaped dynamic text (use `esc()`).
- All times are **unix seconds (number)** unless the name ends `Ms`. Minutes are floats until display. Coordinates `{lat, lon}`; polylines `[[lat, lon], ...]`.
- Privacy: no accounts/tracking. Location stays on device. Only (a) typed place text (or its spelling fix) -> photon.komoot.io, when the on-device place index has < 5 matches or the user taps "Search for ... instead", (b) walking-leg endpoints rounded to 4 dp -> routing.openstreetmap.de (fallback valhalla1.openstreetmap.de) leave the device (iOS: Apple MapKit; plus its daily schedule check on blobberus.github.io, public files only). Plain requests for public data: the Passio feeds, OpenFreeMap tiles for the area on screen, unpkg.com, GitHub Pages. `About` (ui/views/about.js) and `privacy.html` must say so, in the same words as the iOS About.
- Safety: stale/failed data always visible; every derived time labeled estimate + source; app never claims to be official; show official phone 773.702.8181 and https://safety-security.uchicago.edu/Transportation in About and in the empty/error states. Avoid UChicago names/logos/"UGo" in branding.
- localStorage always in try/catch via `core/storage.js`.
- Accessibility: 44 px targets, labels, focus-visible, reduced motion, light/dark, high-contrast, state never by color alone.
- Design: follow `docs/DESIGN.md` (Apple Maps / Citymapper feel). `.claude/skills/taste-skill/SKILL.md` is third-party reference only.

## Directory layout and OWNERSHIP (never edit files you do not own; ask via your final report)
```
web/index.html            [D1]
web/sw.js manifest.webmanifest icons/    [B]
web/css/tokens.css base.css sheet.css components.css   [D1]
web/css/map.css           [C]   map overlays only
web/css/views.css         [D2]
web/js/main.js            [D1]  wiring + boot
web/js/state.js           [B]   the app store (shape below)
web/js/core/*.js          [A]   pure logic, no DOM: geo.js time.js esc.js storage.js events.js store.js arrivals.js planner.js walk.js predict.js
web/js/data/static.js live.js geocode.js   [B]
web/js/map/map.js style.js layers.js geometry.js   [C]
web/js/ui/sheet.js router.js actions.js components.js theme.js   [D1]
web/js/ui/views/nearby.js stop.js routes.js route.js alerts.js about.js pick.js directions.js   [D2]
web/tests/*.html + tests/lib.js   [A: core/data tests] [C: map tests] [D1/D2: ui tests] [lead: e2e.*]  (each owns own file names)
tools/run_browser_tests.py   [A]
tools/* (python), data/, .github/workflows/collect.yml, docs/DATA.md   [E1]
tools/model_*.py backtest.py estimate_speed.py refresh_model.py docs/ALGORITHMS.md docs/BACKTEST.md   [E2]
docs/ARCHITECTURE.md      [lead only]
```
The v1 files (`web/app.js style.css planner.js predict.js walk.js theme.js mapstyle.js`) were deleted at integration; read them at tag `v1-final` if you need the original logic.

## Shared primitives (A owns, everyone imports)
```js
// core/esc.js
export function esc(s): string                 // HTML-escape any value
export function safeColor(c): '#RRGGBB'        // validates, default '#555555'
export function textOn(hex): '#111114'|'#ffffff'   // by luminance
export function lum(hex): number
// core/time.js
export const nowS = () => Date.now()/1000
export function clock(unixS): string           // '4:12 PM' in America/Chicago (device locale's 12/24 h)
export function shortDate(unixS, withYear=false): string   // 'Oct 12' / 'Oct 12, 2026', Chicago calendar
export function sameDay(a, b): boolean         // same Chicago calendar day
export function minsUntil(unixS, from=nowS()): number   // floor, can be <=0
export function ago(unixS): string             // '8s ago'
// core/geo.js
export function hav(a,b): meters               // {lat,lon} each
export function walkMin(meters): number        // meters/80
export function nearestStops(stops, point, {max, maxM, routeStops?}): [{id,name,lat,lon,d}]
export function bearing(a,b): degrees
// core/storage.js
export function load(key, fallback), save(key, value)   // JSON, try/catch, prefix 'sb:'
export function useMemoryOverlay(on), memoryOverlay()   // demo mode (?demo=1): reads see saved prefs, writes/removes stay in memory for the page (nothing stored)
// core/events.js
export const bus = { on(name, fn)->off, emit(name, payload) }   // events: 'sheet:inset' {px, detent}, 'toast' {text}
// core/store.js
export function createStore(initial): { get(), set(patch), subscribe(fn)->off }   // shallow merge; subscribers called once per microtask with (state, changedKeys:Set)
```

## App state (state.js, B owns; `export const store`)
```js
{
  // static (data/static.js fills once)
  routes: {rid:{short,long,color,text_color}}, stops:{id:{name,lat,lon}}, shapes:{rid:[polyline,...]},
  routeStops:{rid:[stopId,...]}  /* first==last means loop */, stopRoutes:{stopId:[rid]}, addresses:{stopId:{address}},
  staticLoaded:false,
  // live (data/live.js fills every 10 s)
  buses:[{vehicle:{id,label}, position:{latitude,longitude,bearing,speed}, trip:{trip_id,route_id}, timestamp, stop_id, current_stop_sequence}],   // OPERATING vehicles only (core/operating.js), minus buses off their route (core/offroute.js: drawn line or learned corridor); both applied in data/live.js
  trips:[{trip:{trip_id,route_id}, vehicle:{id,label}, stop_time_update:[{stop_id, arrival:{time}, departure:{time}}]}],   // minus the trip updates of buses core/offroute.js hides
  away:[bus],   // the buses core/offroute.js hides (off their route): still tracked, never counted as running; the route page counts them, the map removes their markers at once
  alerts:[{header_text, description_text, active_period, informed_entity}],
  feedTs:0, lastOk:0, failed:false, liveLoaded:false,
  // user/prefs (persisted via storage.js where noted)
  user:null /* {lat,lon} */, locState:'unknown' /* unknown|asking|granted|denied|off */, locErr:null /* {code: 1 denied | 2 unavailable | 3 timeout, at: ms} of the last failed try; Settings > Location and Current trip show it (core/lochelp.js has the per-device steps) */,
  hiddenRoutes:[] /* persisted */, theme:'auto' /* persisted: auto|light|dark */,
  // nav (ui/router.js writes)
  view:'nearby', prevView:null, stopId:null, routeId:null,
  routeFilter:null /* {ids:[rid], label:'Station name'} | null */,
  // CTA (experimental 2026-11-06, section "CTA routes beside the shuttles"): CTA routes / stops / shapes / hours are IN the
  // slices above with "cta:" ids; these hold what is CTA's alone
  ctaPatterns:{} /* {rid:[{dir, stops:[stopId]}]} per direction */, ctaSchedule:null /* core/ctasched.js decodeSchedule */,
  ctaBuses:[], ctaTrips:[] /* CTA vehicles; CTA predictions or scheduled times (sched:true) */, cta:{mode:'off'|'live'|'demo', lastOk, failed, feedTs, loaded},
}
```
View-local state (picker query, directions fields) lives in that view module, not the store.

## Data layer (B)
```js
// data/static.js
export async function loadStatic(store, {base?, fetch?}?): Promise<{failed:string[]}>   // never rejects   // fetch data/routes.json stops.json shapes.json route_stops.json (+ stop_addresses.json optional); derive stopRoutes; set staticLoaded
// data/live.js
export function startLive(store, {intervalMs=10000, fetch?, keepAlive?, ...}): {stop(), pollNow(), failures(), delay()}   // polls the 3 Passio JSON feeds (BASE https://passio3.com/chicago/passioTransit/gtfs/realtime/<name>.json?_=ts, cache:'no-store'), sets live fields; failure keeps last data and sets failed:true; pause when document.hidden (unless keepAlive() is true: bus alerts with notifications allowed), poll on visible; fetch = the demo feed in demo mode
// data/demo.js (demo mode only, 2026-10-10; port of the iOS Kit DemoFeed.swift)
export function demoRoutes(state, nowS): {rids, scheduled}   // routes scheduled now (service.json); none scheduled -> every route (scheduled:false)
export function demoFeeds(state, nowS, {epoch, segments?, cache?}): {vehiclePositions, tripUpdates, serviceAlerts}   // Passio-shaped GTFS-rt JSON: per route its scheduled peak (busCount, 1..3) evenly spaced, moving along the road shape (map/geometry.js alongShape) on segments.json times (else 18 km/h), trip updates for the next 14 stops, no service alerts; deterministic in (nowS - epoch)
export function demoFetch(store, {now?, epoch?, segments?}): fetchLike   // answers the 3 feed URLs from demoFeeds after static data loads; never touches the network (no mixing with live data); other URLs 404
// data/geocode.js
export function searchPlaces(q, {signal}): Promise<{items:[{label, sub, lat, lon}], error?:string}>   // never throws (error: 'aborted'|'timeout'|'network'|'http <status>'|'bad response'); <3 chars -> {items:[]} with no request; in-memory cache; 400 ms debounce helper debounce(fn, ms) exported too (.cancel(), .flush())
// Photon gets only the typed text + fixed constants (never the user's location): bias lat 41.7886 lon -87.5987 (UChicago), zoom=10, location_bias_scale=0.2, Illinois bbox -91.52,36.97,-87.49,42.51, limit=15, lang=en.
// Client side: keep Illinois only (state Illinois/IL; no state -> point inside the bbox; non-US dropped), re-rank by distance tier from campus (<=3 km, <=20 km, <=80 km, rest of IL) blended with Photon rank, name match and place type; exact city/town name first; merge duplicates; max 5.
// sub = 'street, city, IL' (Chicago townships shown as Chicago). Also exported: inIllinois, rankPlaces, photonUrl, featureToPlace, HOME, IL_BBOX, PHOTON, clearPlaceCache.
// 2026-10-08: searchPlaces asks the LOCAL index first (data/places.js over web/data/places.json: named places within a 30-minute walk of the
// 82 campus stops, from OpenStreetMap via tools/build_places.py, ODbL): punctuation/space-insensitive ("chickfila"), prefixes, 1 typo,
// categories (coffee, grocery, apartments), whole-word name matches first, then nearest stop. Items carry {local:true, walk, stop, score}
// and sub "Kind, address · N min walk to <stop>" (one middle dot per line, docs/DESIGN.md "Copy"). Photon is called only when the local index has < 5 matches; mergePlaces() puts local
// first and drops Photon duplicates (within 150 m, one name contains the other); Photon results > 3 km away end with "N km from campus".
// data/places.js: norm(s), scorePlace, searchLocal(q,{limit}), loadPlaces(fetch?) (never throws), setPlaces(data|null) for tests.
```
`sw.js`: network-first for same-origin GET with `cache:'no-cache'`, cache only `r.ok && r.status===200`, never cache cross-origin, never `?demo` requests; precache the whole shell: index.html, privacy.html, support.html, manifest, every file under js/ css/ icons/ data/ (`tools/test_precache.py` walks the import graph from index.html, including the dynamic view imports, and fails on a missing entry; `pages.yml` runs it before deploying); cache name constant `sb-v2-<n>` (bump it whenever a shell file changes); serve offline fallback. Also keep the daily GTFS refresh workflow `pages.yml` working (it copies `web/`).

## Core logic (A)
```js
// core/operating.js (2026-10-08): owner rule "a bus that is not operating is not displayed" (map, route station list, counts, alerts, planner)
export const STALE_S = 300
export function isOperating(bus, {routes, service, trips, feedTs, nowS, staticLoaded}): boolean   // fresh (<= 5 min older than the FEED), known route, and route scheduled now OR trip has a live prediction >= now-60
export function operatingBuses(buses, ctx): bus[]   // data/live.js filters store.buses with it (opts.now injectable for tests)
// 2026-10-10 silent service (rider safety): a fresh feed with no vehicle while routes are scheduled is NOT "no shuttles running"
export function scheduledRoutes(state, nowS, {hidden?, among?}?): rid[]   // scheduled now (service.json; no data = not counted), data order
export function silentService(state, nowS): boolean   // liveLoaded, no operating bus, not liveUnknown, >= 1 route (visible or not) scheduled now
export function scheduledNoLive(state, rid, nowS): boolean   // scheduled now, no operating bus on it (callers check liveUnknown first)
export function noLiveStatus(state, rid, nowS): string|null  // 'Scheduled until 4:29 AM, no live location'
export function silentText(state, rids, nowS, phone?): string   // plain text (escape it): names <= 3 routes + scheduled end, else counts; [] = hidden only
// core/offroute.js (2026-11-07 E27c, 2026-11-06 E27b, first version 2026-11-04, owner; ported from the live repo): buses off their route are hidden, still tracked (section "Buses that do not follow their route")
export const BLOCK_M = 250, CONFIRM_S = 45, FAST_M = 500, NEAR_M = 120, NEAR_S = 120, HOURS_PAD_S = 1800, GAP_S = 600, DETOUR_MAX_M = 3000, SHAPE_TOL = 0.01, DETOUR_RE
export function offRouteStep(tracks, buses, {shapes, corridors, service, alerts, routes, nowS, feedTs}): {tracks, hidden: vehicleId[]}   // pure; tracks = {} at start ({rid, since, last, n, fs, fn, ff} per bus), kept by the caller between polls (data/live.js), never modified
export function dropHidden(buses, trips, hidden): {buses, trips}   // trip updates matched by vehicle id only (shared trip ids)
export function awayBuses(buses, hidden): bus[]; awayCount(away, rid): number; awayText(n): string   // store.away; "1 bus is away from the route and hidden from the map."
export function closestOnLine(lines, lat, lon): {d, lat, lon}|null; inListedHours(service, rid, t, padS?): boolean|null; detourAlert(alerts, routes, rid, t): boolean
export function shapeSig(lines): {n, m}; corridorFor(corridors, shapes, rid, t): [lat, lon][]|null; nearestPoint(pts, lat, lon): number; offDistance(lines, pts, lat, lon): number|null   // store.corridors = web/data/corridors.json (data/static.js cleanCorridors)
```
```js
// core/arrivals.js  (pure, takes state slices)
export function arrivalsFor({trips}, stopId, {routeId, hidden=[], nowS}): [{rid, t, bus, tripId}]   // sorted, t > now-30
export function staleLevel({lastOk, failed, feedTs}, nowS): ''|'late'|'old'|'err'      // err: never ok / >60 s since lastOk / failed; old: feed>300 s; late: >120 s
export function runningCount({buses}, rid): number
export function activeAlerts({alerts}, nowS): alert[]
// core/predict.js
export const predict: { ready: Promise<void>, rideMinutes(rid, fromStopId, toStopId, whenTs?) -> {min:number|null, source:'schedule'|'learned', conf:0..1, p10?, p90?} }   // loads data/segments.json (+ data/learned.json if present, 404 ok); never throws
// core/walk.js
export async function walkRoute(from, to): Promise<{m, min, coords:[[lat,lon]], source:'router'|'estimate'}>   // FOSSGIS OSRM foot primary, Valhalla fallback, 3 s timeout each, straight*1.2 estimate fallback, cache by 4dp, <=6 concurrent
// core/planner.js
export function plan({from, to, now, data:{stops,routes,routeStops,trips,buses}, predict?, walkMins?}): {options:[Option], walkOnly:{m,min}}   // pass predict explicitly (no implicit fallback)
export async function refineWalking(option, {walkRoute, now, data, from, to, predict?}): Promise<Option|null>   // replaces walk-leg coords/min with router results, recomputes totals/arrive/walkMin/walkM; a router walk is never shorter than the straight line; if the bus would be missed it re-plans (same route, replanned:true) or resolves null (drop it)
// Option = {key, total:minFloat, totalMin:int, arrive:unixS, t0:unixS, walkMin:minFloat, walkM:int, meets:string[], legs:[WalkLeg|BusLeg]}   // total/arrive include every walk (to the boarding stop, transfers, to the destination); walkMin/walkM = sums over the walk legs
// WalkLeg = {type:'walk', from:{lat,lon,name}, to:{lat,lon,name}, m, min, coords?:[[lat,lon]], source?:'router'|'estimate'}
// BusLeg  = {type:'bus', rid, board:{id,name,lat,lon}, alight:{id,name,lat,lon}, path:[{lat,lon}], stopsPassed, wait, waitLive, ride, source:'live'|'learned'|'schedule'|'estimate', conf, boardT, alightT, tripId}   // tripId: live trip update's trip_id, null for a headway guess
```
Planner rules (port from v1, keep behaviors): walk 80 m/min x1.2 detour estimate (WALK_M_PER_MIN, WALK_DETOUR in core/geo.js), max walk 800 m each end, widened to 1600 m (MAX_WALK_FAR) when no option exists within 800 m; every walk costs m/80 min however short (only walks under 1 m get no step); wait counts from when you reach the stop (t0 + walk), and for the second bus from after the transfer walk; direct + one transfer (transfer walk <= 150 m), loop routes wrap, ride time prefers same-trip live prediction (tripUpdates at alight stop minus at board stop), then `predict.rideMinutes`, then distance/18 km/h; wait = live next arrival at board stop after you arrive, else headway estimate; discard options absurdly longer than walking; direct trips contribute, per route, the best (board, alight) pair for EACH criterion below; ranked by `core/rank.js`; max 4 options (`PLANNER.MAX_OPTS`); every number is an estimate.

Ranking (`core/rank.js`, owner rule 2026-10-08): criteria in priority order **1. least walking** (sum of walk-leg minutes), **2. earliest arrival**, **3. shortest wait** (sum of bus-leg waits). An option *meets* a criterion when within a tolerance of the best (walk 0.5 min, arrival 1 min, wait 1 min). Sort: highest-priority criterion met (none = last), then more criteria met, then walk, arrive, wait. Options carry `meets:[ids]`; Directions re-ranks after `refineWalking` and shows `criteriaText(meets)` as a small line on each card ("Least walking, earliest arrival") when there are 2+ options.
```js
// core/rank.js
export const CRITERIA   // [{id:'walk'|'arrive'|'wait', label, tol}]
export function walkTotals(legs): {walkMin, walkM}
export function optionStats(option): {walk:min, arrive:unixS, wait:min}
export function rankOptions(options): Option[]   // copies with meets, best first
export function criteriaText(meets): string
export function pickOptions(cands, {t0, walkOnlyMin, max=4, xferGainMin=2}): Option[]   // filter + dedupe + rank + cap (used by plan)
```

## Map layer (C)
```js
// map/map.js
export function createMap(elId): MapApi
// MapApi (all methods idempotent, cheap to call every poll):
setTheme(isDark)                 // swaps OpenFreeMap style via map/style.js (positron/dark patched for legible street names + house numbers; OSM raster fallback if maplibre missing)
setBottomInset(px)               // visible-map padding from the sheet; fits/flies respect it
drawNetwork({routes, shapes, routeStops, stopRoutes, stops, hidden:[], focus:[]|null, dark})  // casing+color route lines (dim non-focused to .25), stops at zoom>=14 with 44px tap halo
drawBuses(buses, {routes, shapes, hidden, focus, nowS})   // rounded-square badge in route color, heading triangle, pulse ring, stale (>60 s) dimmed; on its route line and moved along it (map/track.js, below); recreate marker only if route changes
setSelectedStop(stop|null)       // {id,lat,lon}
setUser(pos|null)                // blue dot
setHeading(deg|null, spread?)    // heading cone on the dot (2026-10-14): accent wedge, deg clockwise from north, spread = width (default 60, 20..160);
                                 // fed by ui/compass.js straight from main.js (never the store), DOM written only on a change; null hides it
highlightStops(items|null, {onPick})   // items [{id,lat,lon}] ring highlights; null clears
drawFavorites(stops|null)        // [{id,name?,lat,lon}] yellow star badges (map/favorites.js; owner 2026-11-05: yellow, not the old #A35400 brown: tokens `--fav-mark` #FFCC00 / #FFD60A, `--fav-ink` star #1C1C1E, `--fav-edge` 1 px dark edge on light; the sheet's favorite stars use the same tokens), pane z422 (above stops, below highlights/selection/buses), all zooms (smaller <z14), taps -> onStopTap; selected favorite gets a wider unfilled ring; faded while a plan is drawn
drawPlan(option|null, {routes, shapes, routeStops})  // bus legs follow road shapes (geometry.alongShape); walk legs dashed along leg.coords else straight; start/end pins
fitTo(points|bounds, {maxZoom})  flyTo({lat,lon}, zoom)
onStopTap(fn) onBusTap(fn) onUserMove(fn)
// map/geometry.js (pure, unit-tested)
export function alongShape(shapeLines, routeStopsList, board, alight, fallbackLatLngs): latlngs
// 2026-10-10: a slice > 2.5 x the stop path + 500 m takes the shortest plausible pass pair, else is KEPT (North drives 5 km
// between stops 600 m apart); the straight fallback is only for stops > 200 m off the shape or a backwards ride on a
// non-loop. iOS: Kit Geometry.swift is a faithful port (golden test against this file's output).
```
Layer groups must never be rebuilt when nothing changed (diff by a cheap signature) so polling doesn't flicker.
During a zoom (a flight, a zoom animation, a pinch) a network redraw is held and drawn once at zoomend, and a fit / fly asked for during a zoom animation starts at its end; a flight cut by a drag still ends with zoomend + moveend (map.js `syncView`, "Lines stay on the roads through zooms").

## UI shell (D1) and views (D2)
```js
// ui/router.js
export function registerView(id, def)   // def = { title(state)->string, parent?:viewId, detent?:'peek'|'half'|'full', tab?:'nearby'|'routes'|'myroutes', render(state)->htmlString, mount?(rootEl, ctx), unmount?(), refresh?(), meta?(state)->text, onStopTap?(id, ctx)->bool, replaceSelf?:bool }
export function navigate(view, params={})   // sets store.view/prevView/stopId/routeId, adjusts detent; a sub view pushes the current location (a view already on the stack pops back to it); a replaceSelf view (the route page) opened from itself replaces the current entry instead (line replaces line, owner 2026-11-02)
export function back()
// ui/actions.js
export function registerAction(name, fn)    // fn(dataset, event, ctx); markup uses data-action="name" data-id="..." (event delegation on the sheet content)
// ctx passed to render/mount/actions: { store, map /*MapApi*/, navigate, back, setDetent(d), toast(text), now: nowS, locate(): Promise<boolean> /* asks geolocation, sets store.user/locState/locErr, never throws */, stopLocation() /* Settings > Stop sharing */ }
// Views import core/* and data/geocode.js directly (planner, walk, predict, arrivals, geocode). Each view file calls registerView(...) and registerAction(...) at import time; main.js imports every view file.
// Held tap (2026-10-10): runAction / navigate on a name or view not registered yet (slow network: the search bar, gear and tabs work before the view modules load) return false and hold that tap (one slot, actions.js holdTap; router.js imports it, never the reverse); registerAction / registerView runs it once, next tick, if under PENDING_MS (20 s) old. Any newer action, navigate or back that runs drops it; a newer held tap replaces it.
// ui/components.js (pure HTML-string builders, all escape inputs)
export const routeChip(rid, routes), etaBlock(unixS, {stale}), arrivalRow(a, state), stopRow(...), emptyState(title, body), skeleton(n), pill(kind, text), segmented(items), estTag(source)
// ui/sheet.js: createSheet({sheetEl, contentEl, headEl}) -> {setDetent(d), getDetent(), onChange(fn)}  TWO resting states (owner 2026-10-12, 'copy Google Maps', no midway stop): peek (grab + title line, --v-peek 76px) and full; while held the sheet follows the finger anywhere, on release the finger's last motion decides (up = full, down = peek; a stopped finger uses its last 2 px move; no move = tap: grab toggles, a collapsed header expands); 'half' requests keep the current state; the whole header strip drags: touch events with a non-passive touchmove (iOS cannot turn it into a page pan), mouse / pen pointer events on the window (no pointer capture, no text selection); grabbing a settling sheet stops it under the finger; settle starts at the finger's speed (settleMs); content inset follows data-rest after the settle; keyboard (arrows/Home/End/Enter), >=768 px = left panel; emits bus 'sheet:inset' {px, detent} on every settle (Directions re-frames the selected option when it comes to rest collapsed: `directions.js onSheetRest`, spec J3, iOS 2c80933)
//   grabber (#grab, a div): role="slider" "Resize panel", aria-valuenow 0..2 + aria-valuetext DETENT_TEXT (Collapsed / Half / Expanded); arrows / Page Up / Page Down step, Home = Collapsed, End = Expanded, Enter / Space cycle (2026-10-10, iOS adjustable action)
// ui/theme.js: initTheme(store) -> applies data-theme, matchMedia, mount(el) segmented Auto/Light/Dark, onChange(fn(isDark))
```
Rendering loop (D1 `main.js`): on store change -> current view `render(state)` -> set `content.innerHTML` only if string differs from last (preserve scrollTop; never rebuild while a text input inside content has focus). Views with `mount` render once on entry and then **own their DOM**: they subscribe to the store and patch regions in place; main.js never rebuilds them (that would replace a button between pointerdown and click) and calls `refresh()` every 15 s so countdowns tick.

Views (D2) and required behavior (all ported from v1, improved):
- **Layout (v2.4, Google-Maps-style)**: a floating search bar at the top (`#topbar` > `#searchBar`, action `dir:open` with `data-focus="to"`; hidden in Directions via `#app[data-view="directions"]`) with the Settings gear (`#settingsBtn`) at its right end; under it the map credit, status pill, context chip (`#ctxbar`) and locate button (`--chip-top`); a bottom navigation bar `#tabs.bottomnav` (Current trip / Routes / My Routes, `--nav-h`) with the sheet resting on it (`.sheet { bottom: var(--nav-h) }`). The full detent stops below the search bar and any visible chips (`--v-full` overridden on `#app` with `:has()`); sheet height probes live in `#app` so those overrides apply. The map's bottom inset = visible sheet + navigation height.
- **nearby** (tab label and title **Current trip**; ids stay `nearby`): order and regions per "2026-10-11 (owner decisions)" below (one-line alert row, trip in progress, the next bus, "Use my location", station search + "Type an address or place" / "Routes to station…", the rest, quiet no-trip hint); destination search is the top search bar, not in the sheet; with a real location each arrival row adds "Leave now / Leave in N min, est." and marks buses you cannot walk to in time (`pt-miss`, text + strike, never color alone); with location -> 3 nearest stops (up to 3 arrivals at the nearest, 1 at the others); without -> "Use my location" + "Arriving soon"; never dead-ends; location denied is a first-class state.
- **stop**: arrivals list (route chip, route name, Live dot, ETA numeral, "Now"), route chips serving it, address line from `addresses`, "Updated Ns ago", Directions-from-here / to-here buttons.
- **routes**: first control "Edit map order" (`routes:order-edit`); then custom-route / journey bar, filter chip, Show all / Show running / Hide all (Show running, owner 2026-10-17: only the routes operating now stay visible, a live bus or scheduled now with no live location, `core/custom.js showRunning`; none operating = nothing changes and the in-page toast "No lines are operating at this time.", or "No lines are reporting a live location right now." when routes are scheduled without a live location, or "Live data is unavailable, so running lines can't be shown." with the feed unknown; aria-disabled when only running routes show); Running / Not running / Hidden groups; per-route eye toggle (persisted `hiddenRoutes`) honored on map, arrivals, Nearby; filter chip "Routes to <station> x".
- **pick** (Routes to station…, parent/tab `nearby`): dialog asks **Use current location / Select a station / Type an address or place**; NOTHING is highlighted until the user chooses; then nearest stops (<=1.5 km) are highlighted on the map and listed; tapping a station sets `routeFilter` and shows only routes that serve it on list+map; works with no location permission via the other two options.
- **route**: stop timeline with next ETA per stop, buses running, map focus on that route.
- **alerts** (sub view of Current trip, no tab since v2.1): active alerts, opened from the Current trip banner or the My Routes row; phone numbers in alert text are call links. When no bus reports (feed down, silent feed, nothing running) Current trip, stop, Routes, route detail and Directions also show the operator's alerts in full (`operatorAlertsHTML`, "From the shuttle operator") next to the official links; **about**: unofficial notice, official phone/link, privacy statements (Photon, walking router hosts, network requests), links to privacy.html and support.html, theme control, data credits/attribution, version.
- **directions**: Start/Destination fields (station autocomplete + Photon places, "My location" default if granted), swap, up to 3 option cards (total min, arrive clock, summary chips), tap card -> `map.drawPlan`, step list with `Bus arrives at <stop> <clock>`, wait, ride, source tags, walking legs on sidewalks (via `refineWalking`, async, shows "sidewalk route"/"estimate"), note "Bus times are estimates from schedules and live predictions. They will get more accurate as we collect more ride data.", walk-only fallback, no-service empty state. Start (2026-10-12, owner; iOS parity) sets the journey and navigates to `nearby` (Current trip) at the half detent, where the trip in progress leads; focus moves to its `.tp-title`, the plan stays drawn, and Directions shows the trip bar when you come back. Like Google Maps (owner 2026-10-12): the search bar itself turns into the Start / Destination card at the top (`#dirbar` in `#topbar`, FLIP from the bar's rect read by `barRects` before the switch); the sheet holds suggestions and options (the Directions view renders the fields in the sheet only in the landscape panel, `useBar()`); `--dirbar-h` (measured) moves `--chip-top` / `--v-max` / `--v-full` below the card in Directions; focusing a field expands the sheet; collapsing it blurs the field (main.js `sheet.onChange`, every view); leaving Directions shrinks the card back into the bar in the same place. Map taps (stop, bus) keep the sheet as it is: collapsed, the header names the stop with its next bus (stop view `meta`).

## Tests
No Node: browser test pages run in headless Edge. `web/tests/e2e.test.html` loads the real `index.html` in an iframe with `e2e-stubs.js` (geolocation, live feed, service worker, history) and `e2e-expose.js` (store, place search, walk router) injected, and drives the main flows. `web/tests/lib.js` exports `test(name, fn)`, `eq`, `ok`, `near`, and writes a JSON summary to `<pre id="result">` and `document.title = "TESTS pass=N fail=M"`. `tools/run_browser_tests.py [page...]` serves `web/` on a free port, runs `msedge --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --virtual-time-budget=30000 --dump-dom`, parses the title, exits non-zero on failure. Edge path: `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`. Screenshots: add `--hide-scrollbars --window-size=393,852 --virtual-time-budget=12000 --screenshot=<abs path OUTSIDE repo>`; pick the theme with `localStorage['sb:theme'] = '"dark"'` (or Auto + the OS setting) rather than `--blink-settings` (headless does not paint vector map tiles; UI and overlays do paint). Python checks: `tools/test_precache.py` (offline shell) and the data / collector tests `tools/test_*.py`, each `python tools/test_x.py`.

## Acceptance checklist (lead verifies at integration)
Boot with no console errors; nearby list populated from live data; stale pill logic; sheet drag/detents; theme Auto/Light/Dark switch updates map style + markers; Routes to station flow (all 3 modes, no location needed); route toggles; directions with sidewalk walking and road-following bus legs and clock times; offline shell; all unit tests green; Lighthouse-style a11y spot checks; no file > 400 lines; no leftover v1 globals.

## v2.1 features (My Routes, custom routes, journeys, route hours) — contract
Lead already landed: new state fields (state.js), `core/visibility.js`, `core/custom.js`, the
`myroutes` tab id (router TABS = nearby, routes, myroutes; index.html tab button), main.js map sync via
`mapVisibility`, empty per-feature CSS files, stubs (`ui/views/myroutes.js`, `core/schedule.js`,
`data/service.json`) and their sw.js PRECACHE entries (cache `sb-v2-3`). Code against what is below.

### New state (state.js)
```js
service: {}                 // data/service.json, {} when missing (static)
landmarks: []               // data/landmarks.json map labels [{name, lat, lon, tier, kind, osm}], [] when missing (static, 2026-10-13)
routeOrder: [rid]           // persisted. Map draw priority, first = drawn on top. May be partial/empty.
customRoutes: [{id, name, rids:[rid], highlight:[rid]}]   // persisted. My Routes sets.
activeCustom: id|null       // persisted. Applied custom route (its complement is in hiddenRoutes).
prevHidden: [rid]           // persisted. hiddenRoutes before the custom route was applied.
favStops: [stopId]          // persisted. Favorite stations.
journey: null|{rids:[rid], label:string, kind:'plan'|'station'}   // NOT persisted. "Only show relevant routes".
```

### core/visibility.js (lead; everyone uses it, never re-derive visibility by hand)
```js
effectiveHidden(state): rid[]      // journey ? every route not in journey.rids : hiddenRoutes
isVisible(state, rid): boolean
activeCustomRoute(state): custom|null
mapFocus(state): rid[]|null        // route view [routeId] > (journey: null) > routeFilter.ids > active custom highlight > null
drawOrder(state, focus?): rid[]    // focus first, then routeOrder, then data order; top-most first
mapVisibility(state): {hidden, focus, order}   // main.js passes these to drawNetwork / drawBuses
```
Lists (Nearby, stop, arrivals, route list) MUST pass `effectiveHidden(state)` wherever they used `state.hiddenRoutes`.

### core/custom.js (lead) — every function returns a store PATCH
`createCustom(state,{name,rids})->{patch,id}`, `saveVisibleAsCustom(state,name)->{patch,id}` (applied),
`updateCustom(state,id,{name?,rids?,highlight?})`, `toggleHighlight(state,id,rid)`, `deleteCustom(state,id)`,
`applyCustom(state,id)` (hiddenRoutes := complement, remembers prevHidden, clears routeFilter),
`clearCustom(state)` (restores prevHidden), `matchesCurrent(state,c)`, `visibleRids(state)`, `hiddenFor(state,rids)`,
`moveInOrder(state,rid,-1|1)` (routeOrder), `toggleFav(state,stopId)`, `cleanName(s)`.

### Map (C) additions
`drawNetwork({..., order})`: lines are stacked by `order` (index 0 on top); focused routes always above
unfocused. Include `order` in `networkSig`. When focus has 1-3 routes, draw small direction-of-travel
chevrons along each focused route (GTFS shape point order = travel direction), spaced in screen px,
recomputed on zoom, honoring reduced motion (static), never intercepting taps.

### data/service.json (built by tools/build_gtfs.py) and core/schedule.js
```js
{ generated:'ISO', feed:{start:'YYYY-MM-DD', end:'YYYY-MM-DD'},
  routes: { rid: {
    days: { mon|tue|wed|thu|fri|sat|sun: null | { first:'HH:MM', last:'HH:MM' /* may be >= 24:00 */, trips:int,
            buses:[24 ints] /* scheduled vehicles in service per local hour = max concurrent trips */ } },
    exceptions: [{ date:'YYYY-MM-DD', type:'removed'|'added', days?:dayKey }],   // calendar_dates in feed window
  } } }
```
```js
// core/schedule.js (pure; Chicago local time; never throws; null/[] when no data)
routeService(service, rid): object|null
dayKey(unixS): 'mon'..'sun'                         // America/Chicago
hoursOn(service, rid, unixS): {first, last, label:'7:00 AM to 11:30 PM', exception?:'removed'|'added'}|null   // that date, exceptions applied
weekSummary(service, rid): [{days:'Mon-Fri', label:'7:00 AM to 11:30 PM'}|{days:'Sat', label:'No service'}]   // no dash characters in visible text   // groups equal days
busesByHour(service, rid, dayKey): [{hour, buses}]  // only hours with service
upcomingChanges(service, rid, unixS, horizonDays=30): [{date, label:'Thu, Nov 26', text:'No service'|'Extra service'}]
serviceHoursAt(service, rid, unixS): {hours, dayKey, yesterday}|null   // the service day's hours (after midnight: yesterday's while in its tail; 2026-10-11)
isScheduledNow(service, rid, unixS): boolean|null
scheduledUntil(service, rid, unixS): 'HH:MM'|null   // end of the window running now (may be >= 24:00; clock12 formats it)
```

### Ownership for v2.1 (in addition to the table above; never edit files you do not own)
| Agent | Owns |
|---|---|
| SHELL | index.html, main.js, ui/router.js, ui/components.js, ui/sheet.js, ui/actions.js, css/tokens.css base.css sheet.css components.css, ui/views/alerts.js, ui/views/about.js, tests/ui-shell-*, tests/e2e* |
| MAP | map/*.js (incl. map/favorites.js), css/map.css, tests/map-* |
| ROUTE | tools/build_gtfs.py, web/data/service.json, data/static.js, core/schedule.js, ui/views/route.js, css/route.css, tests/data-static.js, tests/route-* + route.test.html |
| ROUTES | ui/views/routes.js, css/routes.css, tests/routes-* + routes.test.html |
| MYROUTES | ui/views/myroutes.js, ui/views/myroutes-swipe.js (swipe-left action tray: Details / Edit / Delete; a full swipe never runs an action), ui/views/stop.js, css/myroutes.css, tests/myroutes-* + myroutes.test.html |
| JOURNEY | ui/views/directions.js, ui/views/pick.js, ui/views/nearby.js, ui/views/tripinfo.js (trip-timing helpers, not a view), css/journey.css, tests/journey-* + journey.test.html |
| MONITOR | monitoring.md, tools/monitor.py |
| lead | state.js, core/visibility.js, core/custom.js, sw.js, docs/ARCHITECTURE.md, css/views.css (frozen: override in your own css file) |
New view files must be added to main.js VIEW_IDS and sw.js PRECACHE: ask the lead in your report.

### Settings + bus-near notifications (v2.1b)
State (state.js, persisted): `notify: {stopId|null, rids:[] /* empty = any visible route */, twoStops, oneStop, minutes /* 0 = off, else alert at <= N min */, liveActivity /* iPhone app only */, inApp}`; `cleanNotify`, `NOTIFY_DEFAULTS`.
```js
// core/notify.js (SETTINGS; pure, shared later by the iPhone app's native layer)
stopsAway(state, stopId, rid?): [{rid, tripId, vehicleId, stopsAway:int, etaS:unixS|null, nextStopId, nextStopName}]  // from buses + trips + routeStops; loops wrap
dueAlerts(state, prevFired:Set<string>, nowS): {alerts:[{key, kind:'twoStops'|'oneStop'|'minutes', title, body}], fired:Set}   // dedup per trip+kind
liveStatus(state, nowS): {title, minutes, nextStop, stopsAway}|null   // what a lock-screen Live Activity would show
dueAlerts(state, fired, nowS, {tripOn, polling})   // 2026-10-13: nothing while tripOn; data down -> ONE {kind:'delayed'} per outage
tripAlerts(p, state, fired, nowS, {polling}): {alerts:[{key, kind:'board2'|'board1'|'boardMin'|'off2'|'off1'|'delayed', title, body}], fired}
tripAlertsOn(p, state): boolean   // a started trip (not arrived) with notify.trip on
```

### Map labels: building and place names (2026-10-13, owner: "the buildings on the maps should also have their names like Google maps. Not every building, but highly trafficked ones and prominent off campus locations relevant to the bus coverage", "UChicago dorm buildings")
Curated in `tools/landmarks.json` (label, tier, kind, optional `until`; order = priority): the buildings the stops are named after, every UChicago dorm, libraries, dining commons, the medical campus, the busiest academic buildings, and the off-campus places the shuttles serve (Harper Court, Hyde Park Shopping Center, the groceries, the Metra and Green Line stations, the Museum of Science and Industry, the Obama Center, Gleacher Center ...). `tools/build_landmarks.py` resolves each to its OpenStreetMap feature (never a typed-in coordinate: the exact OSM name in places.json, or an explicit OSM object) and checks it (within 800 m of a stop, no dashes, no duplicates; `tools/test_landmarks.py`) into `web/data/landmarks.json` (`l = [label, lat, lon, tier, kind, osm, until?]`, ~7 KB, precached). `data/static.js cleanLandmarks` loads it (optional) as `store.landmarks`; `MapApi.setLandmarks` hands it to `map/landmarks.js`.
`map/landmarks.js` draws them in the Leaflet pane `sbLabels` (z 410: above the route lines 390-402, below stops 420, buses and the trip markers; basemap text would sit under every Leaflet overlay, so the colored lines cut through its letters). After each move / zoom and each time the basemap has placed its own names (`basemap.onIdle`), labels are placed greedily in priority order (`placeLabels`, pure): centered on the building, else one of 8 sides at 4 px, else at 14 px (never farther: a name stays by its building); a spot must fit the view and cover no placed label and no stop circle, and preferably no basemap street or place name (`basemap.textAt`, MapLibre queryRenderedFeatures; only tier 1 may settle on basemap text); no spot = left out until you zoom in. Tier 1 from map zoom 14.5 (the app opens at 15), 2 from 16, 3 from 17 (2026-10-14, owner: the detailed names a little closer in); `until` hides a group name ("Max Palevsky Commons") once its buildings' names show. Text only, bold, light #2c4a66 / dark #bcd0e2 with a halo and a faint plate, `aria-hidden`, `pointer-events: none` (taps reach stops), hidden while a zoom animates. The basemap's own campus names (`sb_poi_campus`) now start at map zoom 18 and skip any name a landmark shows. The raster fallback has OSM's own names. iOS: the same file and placement rules in MapScreen (ios/README.md "Map labels").
2026-10-14 (owner): Burton-Judson Courts, International House and Vue53 (kind `housing`, off-campus apartments) are tier 1; Burton-Judson now comes before Granville-Grossman Commons, whose label 100 m away took its spot at zoom 14.5 to 15.5 (it showed in 30 of 55 test views, now 39; Granville-Grossman's name now starts at 15.75 there instead of 15).
Easter eggs (2026-10-14, owner: custom names "that pop up on the map if zoomed in very close"): `easter-eggs.json` at the repo root, `"address": "nickname"` (or `"Place name, address"` when places share one) plus `zoom` (17.5). The build (`tools/build_landmarks.py`, also run by every Pages deploy, keeping the committed file on failure) resolves each address in places.json, gives every label of that place (its OSM name: Max Palevsky's group name and its Central building) the nickname, and adds a tier 3 label for a place that had none (Chipotle on 53rd); output `eggs = [[index in l, nickname]]`, `egg_zoom`. A bad egg is skipped with a warning, never the labels. `cleanLandmarks` attaches `egg` / `eggZ`; `labelText(x, zoom)` draws the nickname from that zoom on, the name below it. Nothing goes into place search (places.json is untouched), so search speed cannot change; the swap is one comparison per label per refresh.
2026-10-15 (owner edits the file on github.com): a bare address shared by several places means the one already labeled (`find_place(..., labeled)`: 1330 E 53rd St = Vue53, not its garage; 1116 E 59th St = Harper Library, not Harper Cafe); with two labeled, the build still asks for "Place name, address". The **Map names** workflow (`.github/workflows/landmarks.yml`, on a push that changes easter-eggs.json, tools/landmarks.json or the build) rebuilds web/data/landmarks.json, commits it to main when a name changed (`build_landmarks.py --differs` ignores the build time; GITHUB_TOKEN, so no other workflow starts) and lists every nickname used and skipped in its summary: the iPhone app bundles the committed copy. Tests no longer fix the count of tier 3 names or nicknames.
Hidden stops (2026-10-15, owner: Aba at 302 N Green St in Fulton Market, the stop "inaccessible and invisible and not searchable in the system"): tools/landmarks.json `hidden_stops` count only for the build's 800 m checks; nothing of them is written (not in stops.json, route_stops.json, places.json or landmarks.json, tested), so the map, search, planner, `core/coverage.js` (Directions still refuses Fulton Market as a destination), iOS and the collector never see them. Aba itself is a curated tier 3 `ref` label (node/6256520187) with an `address`, which `ref_places` adds to the easter-egg places. The build's console output no longer crashes on an emoji nickname on Windows.
Easter-egg places may sit on basemap text (2026-10-15, owner: the Fulton Market nickname "disappears after appearing for a second"): labels are placed on `moveend`, then again when the vector basemap goes `idle` with its street and place names (`textAt`); a tier 2 or 3 name with no spot clear of them was dropped, and in Fulton Market there is none. `placeLabels` now lets a candidate with `textOk` (any label with an `egg`, its own name and its nickname) take the best spot clear of labels and stops, like tier 1; it still prefers a clear one. iOS has no street-name check (MapKit does not say where it draws them), so it never had this.
A nickname for a place inside a labeled building (within 15 m of its label, e.g. a cafe whose address is the building's) goes on that label instead of being skipped (2026-10-15: 5500 S University Avenue, Fairgrounds Coffee's address, nicknames Campus North).

### Settings > Credits (2026-10-16, owner: "At the very bottom of the settings menu, create a button that will expand a list of Credits")
The last item of Settings: a `Credits` row (`.st-credbtn`, `aria-expanded` / `aria-controls`, 44 px, chevron turns
down) expands `#st-credits` in place (`data-st="credits"` in settings.js onClick, focus stays, nothing stored:
collapsed on every open). Content = `CREDITS` in `ui/views/settings.js`, groups App / Maps / Search / Bus data, each
line `[text]` or `[text, url]` parts (text through `esc()`, links `target="_blank" rel="noopener"`, https):
App made by blobberus; OpenFreeMap tiles and style (OpenMapTiles schema); OpenStreetMap contributors (ODbL) for map
data, buildings and place names; the OpenStreetMap tile servers as the backup map; Leaflet (BSD-2-Clause), MapLibre
GL JS (BSD-3-Clause), MapLibre GL Leaflet (ISC); OSRM and Valhalla on FOSSGIS servers for walks; the on-device place
list from OpenStreetMap through the Overpass API (tools/build_places.py); Photon by komoot; Passio's public
GTFS-Realtime feeds and GTFS schedule; the collection (the same feeds every 10 s; "Data research is currently in
progress": no link to the data repo for now, owner 2026-10-16). Never a UChicago, University, UGo or administration name (owner; tested).
Same facts as About's shorter credits. iOS: SettingsView `creditsSection` (a DisclosureGroup in the last section,
its own list: Apple Maps for the map and walks instead of the web map stack).

### Lines by Time (2026-10-18, owner: "Add a clock symbol next to the settings button ... Select a time to check when certain lines will be active")
- Entry: `#timeBtn` (clock, 44 px, `data-action="time:open"`, `aria-expanded` follows the menu) left of the gear in the
  search bar. The menu is the Settings card (`ui/settings-overlay.js`, now with opts `title`, `kind` (data-kind on the
  root), `start` (a head button, here Cancel) and `end` (label + action, here Set time; default Done = close)),
  `overlayKind()` says which menu is open; the gear and the clock swap one for the other. Back / Escape / scrim close it.
- Content `ui/views/timepick.js` (loaded through main.js VIEW_IDS, optional; registers `time:open` only): Date (month +
  day wheels, no year; the day wheel follows the month, February 29 days) above Time (hour, minute, AM / PM), wheels from
  `ui/wheel.js` (spinbuttons: arrows, Page Up / Down, Home / End, a tap on a row, swipe with scroll snap; a column's own
  animation never changes its value). Under the clock the owner's sentence (`TIME_DESC`), then a live result (count +
  chips, `aria-live`), a note when a trip is in progress (Set time ends the journey so the lines can show), the
  disclaimer (`TIME_DISCLAIMER`: timetable estimate, holidays / breaks / events / detours / weather / service changes,
  scheduled night lines that send no bus, unofficial) and last `OFFICIAL_HTML` (phone + official transportation page).
  Defaults: the time already applied, else now (Chicago).
- Logic `core/timeactive.js` (pure): `pickedUnix` (the year = the next time that month / day comes, today included;
  Feb 29 in other years = Feb 28; `chicagoUnix` handles DST), `linesActiveAt(service, routes, at)` =
  `core/schedule.js isScheduledNow` per route (spans, the previous day's after-midnight tail, calendar exceptions), plus
  `outsideFeed` + a note when the date is outside `service.feed` (weekly pattern, no holidays). Kit: `TimeActive`.
- Applying (`core/custom.js applyTimeView`): `store.timeView = {at, name: "Lines active at Sat Oct 24, 9:30 PM", rids,
  before: {hiddenRoutes, activeCustom, prevHidden}}` (never persisted, not in My Routes; state.js saves `before` while it
  is on), `hiddenRoutes` = everything else, `activeCustom` null, journey and station filter ended. The context bar shows
  "Lines active at <time>" + Clear (`time:clear` = `clearTimeView`, which restores `before`, an applied custom route
  included); the Routes list's bar says "Showing <name>" + Clear. Deselecting (or adding) a line: main.js runs
  `settleTimeView` on every hiddenRoutes change, which drops the name and keeps the lines (then "Make this a custom
  route" is offered, as for any hand-made selection). Show all / Hide all / Show running / applying or saving a custom
  route end it. No line scheduled: `TIME_NONE` in the menu and as a toast, nothing changes.
- Tests: `tests/core-timeactive.js` (core.test.html), `tests/timepick.test.html`, e2e "lines by time".

### Beta feedback (2026-10-13, owner)
`ui/feedback.js`: `FEEDBACK_URL` (the only place the Google Form address appears), `feedbackLinkHTML()` (a real `<a target="_blank" rel="noopener">`, never window.open after an await), the welcome popup (native `<dialog>` like ui/confirm.js: Cancel focused first, Escape / outside tap close, 350 ms double-tap guard) once per browser session (`sessionStorage`; blocked storage = once per page load), opened by main.js after the first painted render (`welcomeAfterPaint`). Settings starts with "Beta feedback" (`views/settings.js feedbackHTML`). Browser tests set the session flag before booting the app (e2e.js, e2e-demo.js).
- 2026-11-02 (owner: "Make the feedback request notification a little more noticable (using different colors etc).
  Emphasize how it would be very helpful. Would it be possible to make this request only occur every once in a while
  and not every time the user reloads the site?" and "In the settings menu, the beta feedback should also be more
  prominent"): one look for the popup and the Settings card: the accent tint `--accent-bg` (tokens.css: light #d9e7f8,
  dark #223042; never the green live color), `FEEDBACK_ICON` (speech bubble, white on an `--accent-fill` disc,
  aria-hidden), the bold ask `FEEDBACK_LEAD` "Your feedback would be very helpful.". Popup: the owner's title in a band
  running edge to edge under the rounded top, then `WELCOME_BODY` and `WELCOME_NOTE`, Cancel / Go to Feedback (with the
  opens-elsewhere arrow). Settings: "Beta feedback" stays first; a tinted card with the icon + ask, `FEEDBACK_LINE`,
  Give feedback as the card's primary button, the privacy note.
- How often: never twice in one visit (`sessionStorage` `sb-welcome-seen`, still the tests' seam), at most once every
  `WELCOME_EVERY_DAYS` (7) days, and not for `WELCOME_AFTER_FEEDBACK_DAYS` (30) days after the rider opened the form
  (Go to Feedback, or Give feedback in Settings: `noteFeedbackOpened`). `localStorage` `sb-welcome-log` =
  `{shown, feedback}` (ms; two dates, on the device only; privacy.html "Your settings" and About say so); `welcomeDue`
  is pure (a date far in the future, from a changed clock, counts by its distance). Storage blocked: once per session,
  or per page load. Tests: tests/feedback-welcome.js (wording, frequency, contrast, Settings card), feedback-app.js
  (real app: a new visit within the week shows nothing, a week later it asks). sw sb-v2-81.
- 2026-11-04, experimental (owner: "Remove the give feedback notification when the user logs onto the app. Keep the one
  overlayed on the map"; the live repo did the same in fe88ed78, re-implemented here by hand, never merged): **the welcome
  popup is gone** (showWelcome, maybeShowWelcome, welcomeAfterPaint, welcomeDue, the session flag `sb-welcome-seen`, the
  `.v-welcome*` CSS, every write to `sb-welcome-log`). Kept: `FEEDBACK_URL`, `feedbackLinkHTML`, Settings > Give
  feedback, the words (renamed `FEEDBACK_BODY`, `FEEDBACK_IN_SETTINGS`, `FEEDBACK_NOTE` moved into ui/feedback.js).
  New: the given-feedback memory `localStorage` `sb-feedback-done` = `{how: "gave" | "silenced", at}` (`feedbackDone`,
  `markFeedbackDone`, `noteFeedbackOpened`; "gave" wins; a form date in the old `sb-welcome-log` still counts as gave;
  blocked storage = this page load; every change emits `feedback:done` on the bus).
- 2026-11-04, experimental (glass spec Q7 = yes, owner): **the map feedback button** `ui/feedback-button.js` (from the
  live repo's ec63088d, adapted): `#feedbackBtn` inside `#topbar`, a 44 tinted glass circle 8 under Settings (glass spec
  4, 8.5: `--glass-tint-fill` = tintBg at 85% with the glass filter, speech bubble in tint, badge dot; solid tintBg while
  a chip shows so at most 6 surfaces blur, and wherever glass is solid), hidden at the full detent. Ping: two ring pulses
  on the dot 20 s after start, then every 3 min, at most 4 a visit; waits during a trip, with the sheet expanded, an
  overlay or dialog open, a field focused or the page hidden; none under reduced motion. Tap: the Settings sheet's shell
  (kind "feedback", title "Beta feedback", zooms out of the button, the app's sheet stays where it was): the tinted card,
  Send feedback (the form, new tab), "Once you give feedback, the feedback button on the map disappears.", then the quiet
  "I already gave feedback". Either choice (or Settings > Give feedback) removes the button at once, in other tabs
  (`storage` event) and on later visits; focus goes to Settings. Test seam: `sessionStorage` `sb-feedback-btn-off` = "1"
  (e2e.js, e2e-demo.js). Tests: feedback-shared.js (link, memory, Settings card, privacy wording, nothing of the popup in
  any shipped file), feedback-button.js (rules, schedule, panel, CSS in the glass layout, real app incl. the blur budget
  with the button on), feedback-app.js (the real app shows no popup, the button appears). privacy.html effective
  November 4, 2026; About says the same. sw sb-v2-87.

### You on the trip map + trip alerts (2026-10-13, owner: "the Current Trip map should show the user's location in the current trip's location (especially for bus routes). Make this sync to the notification center's get off in X stops")
ONE evaluation of the followed trip per data change, `core/tripprogress.js tripNow(state, nowS)` (memo: same journey,
buses, trips, user, stops, routeStops, feed fields and `now` within `TRIP.MEMO_S` 10 s), feeds the Current trip card
and timeline (ui/views/tripprogress.js), the map (ui/tripmap.js) and the alerts (ui/notifier.js): they can never show
different stop counts. One wording, `core/tripyou.js`: `offText(stopsLeft, alight)` "Get off here: X" / "Get off at the
next stop: X" / "Get off in N stops: X" (card, alert title, Settings line), `offShort` for the map label, `legStatus(leg)`
(before boarding "Bus 101 is 2 stops away" / "is approaching X" / "is at X"; on board offText).
```js
// core/tripyou.js (pure; iOS Kit TripYou.swift ports it 1:1)
YOU = {FAR_M:300, GPS_ACC_M:100, NEAR_BUS_STOPS:3}
tripYou(p, state): null | {phase, active, lat, lon /* null = unknown, no marker */, source:'bus'|'gps'|'stop'|null, onBus, far,
  vehicleId, label, busLat, busLon, stopsAway, stopsLeft, board, alight, target:{id, name, lat, lon, role:'board'|'alight'|'dest'}|null,
  frame:[[lat, lon]...], text}
// on the bus: the bus position (onBus), unless your accurate GPS is > FAR_M (+ accuracy) from it: your GPS, far:true
// ("Your location is not near Bus 101. Stop counts follow the bus." on the card); walking: your GPS; waiting: GPS, else
// the boarding stop (source 'stop', drawn dashed "You (est.)"); arrived: GPS; target = boarding / alighting stop /
// journey.dest (planJourney writes it)
```
Map (`MapApi.setTrip(you)`, `MapApi.inView(points)` -> true/false, null when the sheet covers the map): on the bus an
accent ring + "You" pill on the bus marker itself (it glides with the bus) and the GPS dot steps back (`.sb-you-onbus`);
a marker of its own when the bus is not drawn or for the boarding-stop guess; labels "Board here" and the get-off
count `offShort`, under their stops (the destination pin and the You pill sit above their points). `ui/tripmap.js startTripMap(store, map)`: follow camera
on at Start and via the locate button during a trip (`recenter`), off when the rider drags or zooms; frames
`you.frame` on a phase / leg change or when a framed point leaves the view (not within 2 s of the last fit), waits
while the sheet covers the map and frames on the next `sheet:inset`.
Alerts: `notify.trip` (default true, Settings > Bus alerts "Trip alerts"); the 2 stops / 1 stop / minutes / in-app choices
time station and trip alerts alike and show without a station. Keys: board kinds per (trip, leg, followed vehicle),
off kinds per (trip, leg) (a trip id roll never repeats them). Station alerts pause while `tripAlertsOn` (Settings
status "Paused during your trip: alerts follow your trip's bus."). Live data down by the feed's own evidence (a failed
poll, or a fresh poll of a feed older than 5 min; never data that only aged while polling paused): one "Live data delayed" alert per outage (requirement conversion to appstore.md section 7).
System notifications end with " Unofficial."; Start asks for notification permission once (`Notification.permission`
'default', from the tap). Polling stays on in a background tab when a station or a trip with trip alerts is armed and
notifications are allowed (`startNotifier().background()`).
Web: `ui/notifier.js` (SETTINGS) watches the store while the page is open and delivers ONE alert per trip + kind (2026-10-10, `deliveryFor({front, perm, inApp})`): the in-app banner (bus 'toast') while the page is visible and focused, a silent browser Notification (service-worker `showNotification` fallback) while it is in the background and the user allowed them; a notification that cannot show falls back to the banner; the "In-app alerts while open" switch turns the banner off. `startNotifier(...).background()` (station set + permission granted) makes main.js keep polling in a background tab (`startLive` keepAlive). Settings wording follows iOS (permission lines "Alerts show as a banner while you use the app, and as a notification while it is open in the background." / "Notifications are off" + why; footer "Alerts work only while Straight Bussing is open; ..."); it never claims to work once the page is closed. Settings is a modal overlay (`ui/settings-overlay.js`, SETTINGS) opened and toggled by the top-right gear (action `settings:open`): it lifts the sheet to "full" and covers the WHOLE sheet (grab, title, tabs: owner wants nothing of Plan Trip to look like part of Settings), a scrim (`.sto-scrim`) dims what is still visible behind it and closes Settings on tap, the sheet header and content are inert; "Done" top right; also covers the bottom navigation (`#tabs` inert, `navBottom` in `overlayBox`); closes on Escape / navigation / the sheet leaving full, traps focus and restores the previous detent. View id `settings` is a compatibility shim only.
| SETTINGS | ui/views/settings.js, ui/settings-overlay.js, ui/notifier.js, core/notify.js, css/settings.css, tests/settings-* + settings.test.html |
| IPHONE | `conversion to appstore.md`, docs/IOS.md, docs/APPSTORE.md |

### Heading cone on the location dot (2026-10-14, owner: "the tracking dot should have a direction based on the user's heading")
`ui/compass.js createCompass({onHeading})` (main.js owns it; tests `tests/map-compass.js` in map.test.html). Sources, best
first: the compass (iOS Safari `deviceorientation` + `webkitCompassHeading`, Chrome / Android `deviceorientationabsolute`
= 360 - alpha; a relative alpha is ignored), + the screen angle in landscape; else the GPS course (`coords.heading`) while
moving >= 1 m/s; else no cone (the plain dot). iOS 13+ shows the compass only after `DeviceOrientationEvent.requestPermission()`
inside a tap (Safari's "Motion & Orientation Access" prompt). One tap shows at most ONE system prompt (2026-11-02, owner:
"There are two requests for locations when the user decides to press share location/use my location ... If this is not
absolutely needed and can be completed with one notification to the user, do so"): main.js `askCompass()` calls
`compass.request()` synchronously from `locate()` (every tap that asks for the location) and the locate button only
when `mayAskCompass(store.locState)` (location already `granted`, so no location prompt can show in the same tap);
never at launch (`locate({auto: true})`), at most one request in flight, never again once readings come. So the first
share / locate tap shows the location prompt alone; a blocked or switched-off location (Settings > Stop sharing) never
reaches it. Since 2026-11-04 (owner: "The build no longer shows the user heading. Allow the app to display user
heading."; riders rarely tapped the locate button a second time, so the cone never appeared) the FIRST TAP ANYWHERE
once location works asks too: main.js `askCompassOnTap`, a capture-phase document click listener, once per page load
(`compass.request()` resolves granted / denied / error / skipped; an error, i.e. not counted as a tap, lets the next
tap try again). That tap's only system prompt is the motion one; iOS keeps the answer for the session. Without the compass the cone still follows the GPS
course while moving. Android / Chrome need no prompt for the sensors. Test: `tests/e2e-locprompt.js` (e2e.test.html). On while location sharing is on
(`start` after a fix, `stop` in `stopLocation`), listener off while the page is hidden. Readings never enter the store:
coalesced to one per animation frame, passed on only on a turn >= 2 deg or a width change, straight to
`MapApi.setHeading(deg, spread)`. Width = 2 x the compass's stated error, 40..120 deg (60 when the source gives no
accuracy; a negative accuracy means no heading, as in CoreLocation, whose values iOS Safari passes on). The map turns the cone the short way round (`geometry.unwrapDeg`,
0.15 s, none with reduced motion); the cone hides with the dot (on the bus, no location). Nothing is stored or sent
(privacy.html "The way you face"). iOS: ios/README.md "Heading cone".

### Alerts that name a route by Passio's own id (2026-10-16, DC-009, rider safety)
Passio's service alerts can name a route by its internal id, which is the GTFS `shape_id` of that route's trips (the
North alert of 2026-10-14 named 38734; North is route 1075). `tools/build_gtfs.py` `route_aliases` adds each route's
shape ids to `routes.json` as `alias_ids` (left out: a shape two routes share, or one equal to a route id), and
`data/static.js` keeps them as a clean string list. `core/arrivals.js` `alertRouteIds(alert, routes)` is the one mapping
from an alert to routes: an informed route id that is a route, else the one route listing it as an alias (two: neither),
unknown ids dropped. Users: `views/route.js` renderService (Schedule changes), `views/alerts.js` operatorAlerts with a
route (only alerts tied to no known route, so an unmatched one is never lost on route pages) and the Alerts list chips.
iOS: Kit `Route.aliasIds` (StaticLoader decodes `alias_ids` leniently: a bad list never costs the route),
`Arrivals.alertRouteIds`; App RouteDetailView.routeAlerts, AlertsView chips, OperatorAlerts / NoBusHelp `untiedOnly`.

### Destinations farther than 800 m from a stop: a note, then the trips (2026-10-15, owner)
First "If a search query for destination doesn't have a proper stop or address within range, say: Sorry, ...", then
the same day "Change the 800m+ distance restriction to telling the user about the constraint, but still giving a method
to reach the location. Under the notification, state: Straight Bussing recommends changing to another mode of
transportation after arriving at the closest destination. Then proceed to give the trip methods underneath like before."
`core/coverage.js` `covered(state, point)`: a stop, or within `COVER_M` = 800 m (straight line) of a stop some route
serves (`routeStops`); always true before the schedule loads or for a point without coordinates. Directions: search
and planning are as before (every place is suggested; the planner's 1600 m end walk, else walk the whole way). When the
destination (set any way: search, Swap, My location) is not covered, the results start with a `role="status"` note
(`coverNoteHTML`, `.v-note.v-cover`): `COVER_TEXT` ("Sorry, Straight Bussing only covers locations within 800 m of the
campus shuttle routes.", the owner's sentence without "UGo", his choice) and under it `COVER_ADVICE`, then the trip
options (after the trip bar and the stale warning). The start never gets the note. Current trip's and Routes to
station's place searches are unchanged. About a third of places.json (638 of 1,921) is outside. iOS: Kit
`Coverage.swift` (`text`, `advice`), DirectionsView `coverNote`.

### Custom routes interaction (2026-10-08)
Tap a custom route row = show it on the map / stop showing (`mr:toggle`, no navigation). Swipe left (or the row's "More" button,
`mr:swipe`) = action tray Details (`mr:details`, no apply) / Edit / Delete. Every delete goes through `ui/confirm.js`
`confirmDialog({title, body, confirmLabel, danger})` -> Promise<boolean> (native `<dialog role="alertdialog">`, Cancel focused,
Escape / backdrop cancel; settles from the button itself, not the async close event).

Saved routes always listed (2026-10-17, owner: "Hidden routes in the my routes folder should still display if they are
not running"): a custom route's detail lists every saved route (the list never filtered by running or visibility;
checked in the real app with demo buses and a 15-route set, 2 hidden). Each row now says why there is no bus:
`savedRouteStatus` = live buses / Scheduled, no live location / `restingText` ("Not running now · Scheduled from
4:00 PM today" from `core/schedule.js` `nextStartToday`, "No more service today", "Not running today"), plus
"Hidden on map" (or "Not on this trip" in a journey) when hidden; a hidden route shows no arrival time. Never a live
time without a bus. core/visibility.js still keeps hidden routes off the map and the arrivals. Also fixed: "2 buss
running". iOS: Kit `Schedule.nextStartToday` / `Schedule.restingText`, `CustomRouteLine`.

### 2026-10-09: stutter fixes, map credit, self-update
- Sheet geometry: the sheet element is always `--v-max` tall (offset and content padding use `--v-max`); `--v-full` depends only on
  the status pill (`--pill-h`, measured by a ResizeObserver in main.js). The context chip never changes the detent; it fades out at
  the full detent. Selecting / clearing a custom route moves nothing (0 layout shift at half and full).
- Map credit (`js/map/credits.js`, replaces Leaflet's attribution control): "OpenFreeMap · OpenMapTiles · OpenStreetMap" as links,
  no copyright sign; plain small text (no bubble, no (i) button: owner request 2026-10-09) at the bottom-left above the sheet
  (positioned by `setBottomInset`), shown at load and faded out for good after 5 s (held while hovered / focused), hidden at the full
  detent. Settings > About keeps the full credits (OpenStreetMap ODbL, OpenMapTiles, OpenFreeMap) so they stay findable, which the
  OSMF Attribution Guidelines ask for once the on-map credit disappears. `fitTo` uses `flyToBounds`.
- My Routes: rows are a fixed 64 px with a fixed-size check circle (`aria-pressed`); `ui/views/myroutes-patch.js` morphs only what
  changed (keyed rows, keeps drag styles, waits while a pointer is down or a tray animates); tap threshold 10 px in the row's own CSS
  px; only the tray's Details button opens 'customroute' (saving a new route returns to the list).
- `ui/update.js`: registers sw.js, checks for a new version when the app returns to the foreground, reloads in the background when a
  new worker takes control (an installed app could otherwise run old code for days).
- `tools/run_browser_tests.py` retries a page once, alone, when headless Edge's virtual-time mode stalls it (runner timeout with no
  results); the output says "(retried once after a runner timeout)". Pages with failing tests are never retried.

### 2026-10-09 (later): search speed + spelling, trip progress, tap outside
- Place search: `searchPlaces(q, {signal, exact, fetch, placesFetch})` -> `{items, error?, assumed?: {from, to, big}}`; Photon gets
  `assumed.to`; `exact` = as typed, Photon always (3+ letters), up to 8 results; cache keyed by query + exact. `localPlaces(q, {exact})`
  (sync, null until loaded). data/places.js: `findLocal(q, {limit, exact})` -> `{items, assumed?}`, `placesReady()`, `preloadPlaces()`;
  data/spell.js (weighted Damerau-Levenshtein corrections); ui/views/placesearch.js: `createPlaceSearch(onChange, {ms=250})` with
  on-device results on every keystroke and only Photon debounced; note "Showing results for X" + "Search for … instead" when the
  correction is big (actions dir:exact / nearby:exact / pick:exact). places.json v2 (p[8] other names); tools/place_aliases.json (72
  campus nicknames keyed by OSM id).
- Trip progress: `planJourney(o, toLabel)` -> `{rids, label, kind:'plan', to, t0, legs}`; core/tripprogress.js `tripProgress(journey,
  state, nowS)` (phases walk-to-stop / waiting / on-bus / arrived, followed vehicle, per-stop state + live ETA, missed-bus detection);
  ui/views/tripprogress.js `tripProgressHTML(state, now, {actionsHTML})`, rendered by nearby.js entryHTML when a trip is active.
- Map: `onMapTap(fn)` fires for taps on empty map (not layers, credits or controls; never after a drag); main.js lowers the sheet to peek.

### 2026-10-09 (evening): map view stays put, scrolling context bar
- Camera rule: only choosing a route moves the map (Routes list / route chips `route` + `route:open` -> `fitTo` its shape; a custom
  route; a trip plan; Routes to station; the locate button; a chosen place). Opening a stop (map tap, list row, `stop:open`) selects
  it without flying; a bus tap opens its route WITHOUT fitting (main.js `openRoute(rid, false)`). iOS `AppModel.push(.stop)` likewise.
- Context bar (`ui/contextbar.js`): text that does not fit scrolls Apple Music style (`startMarquee(el, {reduced})`, Web Animations
  on `.ctx-run`): rests `MARQUEE.restMs` (3.5 s) at the start, glides at `MARQUEE.pxPerS` (32) until an aria-hidden copy sits where
  the text began, loops; re-measured on draw and resize (ResizeObserver); mouse hover pauses; still (ellipsis) with reduced motion.

### 2026-10-10: empty live feed during scheduled service (rider safety)
Collected data showed the Passio feed fresh but empty from about midnight to 4:30 AM while service.json has the night routes
(North / South / East) in service until ~4:29 AM: the buses run without GPS, or service ends early; we cannot tell which. Wording
(web `core/operating.js` + iOS Kit `Operating`, same text):
- **Scheduled, silent** (`silentService`): pill (warn) "No shuttles are reporting live locations"; Current trip / Directions empty state
  "No live locations right now" + `silentText` ("The schedule shows the North and East routes in service until 4:29 AM and the South
  route until 4:25 AM, but no bus is sending its location, so we can't confirm they're running. Call 773.702.8181 before you rely on
  them.") + official link; stop cards "No live times right now"; stop view names only that stop's visible scheduled routes; Routes
  group "Scheduled, no live location" with rows "Scheduled until 4:29 AM, no live location" (also per route while other buses run);
  route detail status the same + one explaining line; My Routes rows and editor group likewise.
- **Nothing scheduled now** (fresh feed, no bus): "No shuttles running right now" (the honest case, unchanged).
- **Feed outage** (`liveUnknown`): unchanged ("Live times unavailable", "Live status unknown"); it wins over the rules above.
Hidden routes still prevent the "no shuttles" claim but are not named ("Some hidden routes are scheduled now, ..."). `renderRoutes`,
`listHTML`, `groupRoutes` (now `{running, scheduled, idle, hidden}`) and `renderEditor` take an optional `now` (tests).

### 2026-10-10: web parity with the iPhone app (ios/README.md "iOS has, web missing")
- **Routes list**: a "Not running" row adds today's scheduled hours (`routes.js idleText`: "Not running · Today 7:00 AM to
  11:30 PM", `hoursOn` label, nothing added on a no-service day), like iOS RouteRow.
- **Status pill** (`ui/pill.js`, out of main.js): `pillState(s, now, {bootS, graceS})` -> `{kind, icon, msg, retry, alert}` with icon
  `feed` (error) / `delay` (late, old) / `silent` (scheduled, no live locations) / `idle` (no shuttles); `createPill(els)`
  renders it into `#pill` (`#pillIcon` slot, aria-hidden) and keeps `--pill-h`. Words unchanged.
- **Bus alerts**: one delivery per alert (Settings section above).
- **Directions**: live updates re-plan through `core/throttle.js` `createThrottle(run, {everyMs, gate, now, later})` at most every
  `DIR_REFRESH_S` (8 s, iOS dirRefreshS) with one trailing run (the newest data is never dropped); skipped while the feed fails,
  deferred while a new-endpoint plan still refines; the picked card is kept by key and the map never moves. `directions.js`
  exports `liveReplan` and `deps.wallMs` / `deps.later` (test clock).
- **Demo mode** (`core/demo.js` DEMO = `?demo=1` exactly; nothing else turns it on, nothing is stored): main.js starts
  `ui/demo.js startDemo(store, startLive)` = `startLive(store, {intervalMs: 5000, fetch: demoFetch(store)})`; no banner since
  2026-10-11 (the status pill says "Simulated buses", see below); no notifier, no service worker registration; sw.js never caches
  `?demo` requests; storage writes stay in memory; Settings says "Bus alerts are off in demo mode: the buses are simulated."
  Tests: `tests/demo.test.html` (real app at index.html?demo=1, no stubs), `tests/data-demo.js`.
- **Accessibility**: the grabber is a slider (ui/sheet.js above); route detail stop buttons carry one label "Name, next bus in
  N min" / ", no prediction" (+ ", a bus is heading here, seen N min ago"), everything else in the row is aria-hidden.
- **Map**: `css/map.css` `--sb-accent` = `var(--accent-fill)` (light) / `var(--accent)` (dark), no separate map blue.

### 2026-10-11: web bug sweep (rider safety, offline shell, flaky tests)
- **No bus reports** (feed down, silent feed, nothing running): Current trip, stop, Routes, route detail (alerts not tied
  to a route) and Directions add `ui/views/alerts.js operatorAlertsHTML(state, now, {rid?, max=2})` ("From the shuttle
  operator", the alert in full, then "All N service alerts") before the official links. The live feed's standing alert
  gives a number to call when buses do not show. `alertBodyHTML(text)`: escaped text with phone numbers as `tel:` links
  (Alerts view too). The status pill offers **See alert** (`#pillAlert`, action `alerts:open`; `pillState().alert`) on
  the silent / no-shuttles pills when an alert is active, like iOS; never on a feed error (Retry).
- **Service day after midnight**: `core/schedule.js serviceHoursAt(service, rid, unixS)` -> `{hours, dayKey, yesterday}`
  (iOS Kit Schedule.serviceHoursAt). Route detail reads "Friday service 6:30 AM to 12:25 AM · Scheduled now" in a
  route's after-midnight tail (never "Today No service · Scheduled now"); the buses-by-hour chart follows that day.
- **Trip following** (`core/tripprogress.js`, ported back from the iOS sweep): the trip id alone never lends another
  vehicle's predictions to the planned vehicle; a planned vehicle on a new trip id past the boarding time (loops roll
  the id) is the bus you ride; the missed-bus note never promises a next bus that is not there and also shows on the
  walk to the stop. A stop's "Directions to here" / "From here" end a started trip (they used to re-target it).
- Routes to station rows: `pick.js walkShort(d)` "2 min walk (119 m) · North, East" (one middle dot).
- Demo mode: Settings shows no "Allow notifications" (alerts are off). A map that cannot load logs `console.warn`.
- Map: `patchStyle` drops the dark style's `fill-pattern: wood-pattern` (missing from the OpenFreeMap sprite; console
  warning, no woods) so the palette's wood color paints.
- Offline shell: PRECACHE gains privacy.html and support.html; `tools/test_precache.py` (also in `pages.yml`) keeps the
  list complete. Verified: with the server down, a profile that ran the app once serves /, privacy.html and
  support.html from the cache and boots the app.
- Tests: `ui/contextbar.js mountContextBar(el, store, {reduced?, frame?, cancelFrame?})` (frame scheduler seam; the
  marquee test measures on a timer because headless Edge can withhold animation frames for seconds); the e2e camera
  check ends earlier glides instead of waiting for them; `tools/run_browser_tests.py` fails tiles.openfreemap.org
  requests at once (PAC proxy; virtual time stands still while a fetch is pending, and slow tiles stalled e2e pages
  until the runner timeout). `map.test.html` keeps the network for its live style check.
- **Chicago time on every device**: `core/time.js clock()` formats in America/Chicago (the locale's 12 / 24 hour
  choice stays), `shortDate` / `sameDay` give the Chicago date and "today" for alert windows (Alerts, Settings) and
  About, so a phone elsewhere never shows "Arrive 4:37 AM" next to "6 AM to 11 PM" (`tests/zone.test.html` runs as a
  Los Angeles device via `zone-sim.js`; iOS Kit `TimeFmt.clock` / `LiveText.alertWindow` same). `map/geometry.js
  alongShape` drops repeated shape points first: a zero-length or one-point shape line never wins the line pick and
  sends a ride to the straight fallback (Kit Geometry.swift same). sw `sb-v2-34`.

### 2026-10-11 (owner decisions): demo pill, the next bus at the half detent, operator phone
Same spec for the iPhone app (another agent ports it to `ios/`). sw `sb-v2-36`.
- **Demo mode without a banner**: `#demobar`, `html.is-demo`, `--demo-h` and `--z-demo` are gone. The status pill is the one
  quiet, honest indicator: `ui/pill.js pillState(s, now, {bootS, graceS, demo})` -> `{..., demo:true, kind:'info', icon:'demo'
  (flask), msg: core/demo.js DEMO_PILL "Simulated buses"}` on every screen (a feed error or delay still wins); `createPill(els,
  {demo})` adds `.pilltap` (`data-action="demo:info"`, info mark; its `::after` makes the whole 44 px pill the target).
  `ui/demo.js` registers `demo:info`: `confirmDialog({title: "Simulated buses", body: DEMO_BODY + " Nothing you change in the
  demo is saved.", confirmLabel: "Show live buses", cancelLabel: "Keep demo"})` (ui/confirm.js gained `cancelLabel`, default
  "Cancel"); yes -> `demoDeps.go(exitDemoHref(location))` (reload without `?demo=1`). The simulated feed has no service
  alerts (owner, 2026-10-11: the pill is the one demo indicator; iOS DemoFeed matches). Demo state is still never stored.
- **Current trip order** (`ui/views/nearby.js`, regions `nearby-alert|trip|next|loc|alt|results`, patched from one table):
  1. the alert row, ONE line (`alerts.js alertBanner`: icon, "Service alert: <first title>" cut with an ellipsis, chevron; the
  full title is in its label); 2. the trip in progress (`entryHTML`: timeline + Trip steps + "Routes to station…", as before),
  '' with no trip; 3. **the next bus** (`nextHTML`): with location or a typed place, the nearest stop (`.pt-next` card: the
  name, never cut, with "N min walk" on its right, then up to 3 arrivals in 52 px rows with the live / schedule labels and
  "Leave in N min, est." as before), followed by why + who to call when no bus reports; without either, the Favorites card;
  4. "Use my location" (the one primary action) only without location; 5. "Search stations" + `altHTML` ("Type an address
  or place" and, with no trip, "Routes to station…", link-style secondary actions); 6. the rest (`bodyHTML`: favorites when
  a nearest stop leads, "Also nearby", the walking-estimate note, or "Arriving soon") and `NO_TRIP_HINT` as a quiet last
  line ("No trip in progress" is no longer a card). Checked in a 393 x 852 phone (`tests/e2e-current.js`): alert row + stop +
  3 arrivals end above the bottom navigation at the half detent; at 320 px the walk drops under the name. The row builders
  moved to `ui/views/nearby-cards.js` (guidedRow, pickArrivals, favoritesHTML, soonest; nearby.js re-exports them).
- **No-bus calls** (`alerts.js`): `operatorPhone(state, now, {rid})` -> `{text, tel}|null`, the first phone number in the
  active alerts (title, then description), exactly as written, never 773.702.8181, never hardcoded. `callsHTML(state, now,
  {rid, primary})`: with a number, "Call bus route help: <number>" (primary style unless the screen already has its one
  primary action: Current trip's "Use my location", a stop's "Directions to here"), then "Safety or urgent: 773.702.8181"
  (secondary) and "Official transportation page"; without one, the usual official line (773.702.8181 stays the call).
  `noBusHelpHTML` = `operatorAlertsHTML` + `callsHTML` replaces `operatorAlertsHTML + OFFICIAL_HTML` on Current trip, stop,
  route detail and Directions; Routes puts the calls with the alert and then drops its bottom official line (since 2026-10-17, owner: Routes keeps
  the alert at the top and moves the calls and the official page to the bottom, under every route, as its one bottom block). The operator's
  text stays verbatim (including "UGo"). `core/operating.js silentText` still names 773.702.8181 (shared with iOS; unchanged).
- Unchanged by decision: walking times carry no "est." label.

## Buses ride their route line (2026-10-18, owner: "the bus location should update smoothly without exiting the borders of the roads and the station lines they follow")
- `map/track.js` (pure, tests `web/tests/map-track.js`): a fix within `ON_M` (40 m) of its route's shape (`store.shapes[rid]`, the
  drawn line) is drawn on the line; `follow(prep, from, at, pt, {bearing, dt})` returns the new place and the way there through
  the line's own points (`walk`). The pass that continues from where the badge is wins (out-and-back streets and loops pass one
  point twice), within `SPEED_MPS` (22 m/s) x the time since the last report + `SLACK_M` (400 m); a step back up to `BACK_M`
  (30 m) is jitter and stays on the line; a new badge takes the closest pass, the one heading the feed's way when two tie (+25 m
  for a pass running the other way). Off the line (a detour, the garage) the fix is drawn as is. On 2026-10-14's polls 87% of
  fixes were within 40 m of their line (median 3.8 m); most of the rest are over 100 m off (buses away from their route).
- `map/layers.js createBusLayer`: no CSS glide on the badge any more; a requestAnimationFrame loop moves it along the path:
  a normal poll at constant speed over `GLIDE_MS` (9 s), a catch-up (over 350 m along the line, or after more than 30 s without a
  report: a reload, a feed gap) eased in 0.9 to 2.6 s (`moveTiming`); off the line a straight glide up to 150 m, longer = a jump.
  The heading triangle turns with the street (`headingAt`, short way round); a new badge with no feed bearing takes the line's
  direction. Frames pause while Leaflet animates a zoom (`zoomstart` / `zoomend`); prefers-reduced-motion moves at once.
  `createBusLayer(map, cb, {clock, frame, reduce})` takes a manual clock and frame queue in tests; `shown(id)` = the drawn spot.
- When bus data drops out: `data/live.js` keeps the last bus list for ONE poll that answers with no bus at all while buses
  reported in the last `EMPTY_HOLD_S` (30 s) (Passio sends odd empty lists, DC-015); the next empty answer is believed, so
  "No shuttles are reporting live locations" is at most one poll late. On the map a bus missing from a poll while others still
  report keeps its badge for `MISSING_S` (45 s) and then continues along its line; a poll with no bus at all clears the map at
  once (the map never shows buses while the pill says none report); a route the rider hides goes at once.
- iOS: Kit `BusTrack.swift` (the same rules and numbers, `BusTrackTests` incl. a golden file the web JS computed on real reports) and App `Model/BusMotion.swift` (steps the badge along the path; `missingS` = MISSING_S); Kit `LiveState.emptyHoldS` = EMPTY_HOLD_S (`LiveHoldTests`); ios/README.md parity matrix.

## Buses that do not follow their route (2026-11-04, owner: "If buses are not following their routes for a long period of time (measure this by the bus operation data and their listed hours), remove them from the map. Do this for both the experimental and nonexperimental build.")
- Measured first (RouteKnower.md E27, `experiments/routeknower/E27-scripts/`): 25 days of archived raw polls (Oct 10 to Nov 3,
  1.54 M fresh reports, 4,355 bus-hours), each day's route lines and listed hours, the logged arrivals and alerts. Inside the
  listed hours buses are within 300 m of their line 95.9% of the time. Buses that really serve riders can be far off it for a
  long time: the Downtown Campus Connector 2.5 km off Lake Shore Drive for up to 32 min (Oct 22, every DCC bus), the
  Apostolic bus on its 8 AM run to the 57th Street Metra station (920 m, 23 to 30 min, every weekday, along another line). The
  buses that do not operate are mostly at the operator's garage (41.82, -87.64; 105 of the 109 runs the rule hides).
- `core/offroute.js` (pure; tests `web/tests/core-offroute.js`): OFF the route = farther than `OFF_M` (300 m) from its route's
  line (store.shapes) AND from every other route's line. The clock starts at the first such report (the bus's own report time,
  never the phone's) and restarts within 300 m of any line, on a route change, or after `GAP_S` (10 min) without a report.
  HIDDEN at `HIDE_IN_S` (15 min) inside the route's listed hours padded `HOURS_PAD_S` (30 min) at both ends (service.json via
  core/schedule.js isScheduledNow; no schedule data counts as inside), at `HIDE_OUT_S` (5 min) outside them. Never hidden
  while the closest points of its line have spread `FOLLOW_M` (1.5 km) since the clock started (following its route on
  another street), while it is `RETURN_M` (1 km) or more closer to its line than its farthest point (heading back: leaving the
  garage), nor inside the listed hours while an operator alert is active that names its route (any text, alias ids too) or
  names no route and matches `DETOUR_RE` (detour, reroute, closed, blocked, construction, ...; the standing "UGo Bus Route
  Assistance" alert does not match). Back within 300 m of a line = shown at the next poll.
- Applied in `data/live.js` after core/operating.js: `offRouteStep` once per vehicle poll on the operating buses (the clocks
  live in the poll loop, `offTracks`), then `dropHidden` takes the hidden buses out of store.buses AND their trip updates out
  of store.trips (by vehicle id), so the map, "Where the buses are", arrivals, counts, bus alerts, the planner and the trip
  view agree; Passio kept predicting the Nov 2 garage-bound buses (DC-022: 830 prediction rows). Silent-service trip updates
  with no bus are untouched. Before static data loads nothing is hidden; after a reload the clocks start again (a missed hide
  for up to 15 min, never a wrong one). Demo buses ride their lines and are never hidden.
- Numbers (25 days): 835 bus-min hidden, 33 a day; 643 of them buses going to the garage after service, 131 never serving,
  21.5 leaving the garage, 39.1 two parked breaks between trips (a Red Line bus at the garage, a DCC bus parked 1 km off at
  Museum Campus); 0.5 bus-min within 2 min of a logged arrival; no moving detour or Metra run hidden. DC-022 (Nov 2): Central
  hidden from 00:11 (its hours had ended), North from 00:23, East from 00:27.
- iOS: Kit `OffRoute.swift` (same rules and numbers), applied in `LiveState.applying` (`offTracks`, `offHidden`), `OffRouteTests`
  incl. the web's answers on real polls (`Fixtures/offroute_golden.json` = `web/tests/fixtures/offroute_golden.json`, made by
  `experiments/routeknower/E27-scripts/make_golden.py`, answers from `web/tests/offroute-golden.html` in headless Edge).
- Ported from the live repo the same day (owner: both builds): the same files and numbers; sw `sb-v2-91` here.
- **Replaced 2026-11-07 by the live repo's E27b + E27c rule** (ported in one commit; the live repo's docs/ARCHITECTURE.md
  "Buses that do not follow their route" and RouteKnower E27b / E27c have the measurements). Owner 2026-11-06: "If a bus is
  off it's route for more than a block, make the bus disappear from the map ... still continue to track the bus";
  2026-11-07: "the buses that are not driving on their designated routes are still showing sometimes (for example, the
  downtown connector still shows even if its not on its route)" (this site still ran the rule above: 15 min, other-line
  and following exemptions). Now: distance to the drawn line or the learned corridor `web/data/corridors.json` (streets
  the buses drove in service on most days, 80 to 400 m off the drawn line: the Downtown Campus Connector at Union
  Station; a route whose line changed, or the file after valid_until, keeps the line only); hidden when FAR > 250 m for
  45 s, FAST > 500 m on 2 reports in a row, or NEAR (routes with a usable corridor) > 120 m for 2 min; an operator
  detour alert exempts inside the listed hours (+-30 min) and within 3 km only. Hidden buses stay in store.away
  (data/live.js), the map removes them at once (main.js `away` ids, map/layers.js), the route page says "1 bus is away
  from the route and hidden from the map." and its scheduled note "No bus is on this route right now, ..."
  (ui/views/route.js `noLiveNote`, css `.r-away`). CTA buses are never checked: they live in store.ctaBuses (core/agency.js
  keeps every Passio rule Passio-only) and corridors.json lists Passio routes only. Tests: core-offroute.js + the real-poll
  golden file (11 cases) as in the live repo, data-static.js (corridors.json), map-track.js (away), route-view.js (away
  line). Refresh corridors.json with the live repo's `experiments/routeknower/E27-scripts/corridor.py --write` (copied here).
  The iPhone app here is paused (docs/redesign/GLASS-IOS-PAUSED.md).

## Minutes to every station on the Current trip (2026-10-20, owner: "the distance in minutes away is shown on the right side of the station name")
- Passio splits one bus's predictions over its trip updates (the trip it is on, often 1 to 4 stops left, and its next trip), so
  the timeline only had times up to the end of the bus's current trip. `core/tripprogress.js vehicleTimes` merges every update
  that names the followed VEHICLE on the route (never another bus's: trip ids are shared) and `etasAlong` matches them in time order.
- `stopTimes(leg, now, ride)` gives every upcoming stop a time: Passio's live time, else an estimate (`est:true`) scaled between
  the live times around it, added from the last one, counted back from the first, from the bus's position (also while the bus is
  still before the first listed stop: from its next stop; 2026-10-20, Central had no Passio predictions at all), or (no live bus) from
  the plan's boarding time; `ride` = scheduled minutes between stops (`core/predict.js rideMinutes`, data/segments.json), else the
  plan's average per stop, added segment by segment along the list (a loop past the bus's own stop counts the full lap). Never
  earlier than now or the stop before. The view (`ui/views/tripprogress.js`) shows "N min" (live)
  or "~N min est." right of each station name; passed stops say "Passed". iOS: Kit `TripFollow.vehicleTimes` and
  `TripStopTimes.swift` (`TripFollow.stopTimes`), `TripText.stopTimes` / `stopEta` / `stopSay`, App `TripTimelineView`
  (ride minutes from `SchedulePredictor`); tests `TripStopTimesTests`.


## Tap a line on the map; a closed route shows its hours first (2026-10-27, owner: "If a user click on a line that is displayed on the actual map, the uppermost line on the layers ... should open as if the user clicked the specific route", "if a specific route that is running is closed, display the hours and service menu first")
- **Line taps.** Route lines stay non-interactive Leaflet layers (stop halos, buses, favorites and controls keep winning
  their own taps). `map.js`'s map click asks the network layer `lineAt(containerPoint)`: every drawn route polyline is
  projected to container pixels (only those whose bounds come near the tap) and `map/geometry.js lineAt` returns the
  TOPMOST line within `LINE_TAP_PX` (14 px) plus half its drawn width (the casing), in the network's own draw order
  (`stackOrder`: routeOrder, focused routes above dimmed ones), even where a lower line passes closer. Hidden routes are
  not drawn, so never tapped. A hit fires `MapApi.onLineTap(rid)` instead of `onMapTap`; with no listener, or while a
  trip plan is drawn (the network is a dim backdrop then), the tap stays an empty-map tap.
- `main.js` opens the route like a Routes list tap (`openRoute`: route detail at its detent, map framed on the shape),
  unless `core/visibility.js lineTapOpens(state)` says no: Directions, Routes to station, and the Current trip view while
  a trip is in progress keep a map tap as "lower the sheet". A pointer shortcut only: the Routes list stays the
  accessible path (no hover cursor on desktop).
- **Closed route.** `ui/views/route.js routeClosed(state, rid, now)` = no bus of the route running and the schedule does
  not say it runs now (a scheduled route whose buses send no location is open; so is a bus running outside the
  timetable). Then "Hours & service" renders right after the status line and notes, and the stop timeline follows under
  a visible "Stops" heading (`.r-stops-h`); otherwise the order is unchanged. The render is a pure function of state and
  time, so the order flips once at the service boundary. Tests: `web/tests/map-linetap.js` (map.test.html),
  `route-view.js`. sw `sb-v2-68`.
- 2026-10-29 (owner: on a closed route the operator's route assistance numbers must not come first): closed = status, Today line, Hours & service (week, changes, scheduled buses by hour), then the no-bus help (operator alert, Call bus route help, Safety or urgent 773.702.8181), then Stops. Open routes keep the help right after the status. route.js renderRoute; tests route-view.js; sw sb-v2-70.

## Anonymous usage statistics (2026-10-27, owner: "track when a distinct user logs on (time of day), track how long they use it, track what locations they use it most often from", anonymously; visit start and distinct users "should collect regardless")
Website only; on since 2026-10-29 (`USAGE_URL` in web/js/data/usage.js = the owner's Apps Script web app; empty = off).
Owner steps, columns and privacy rules: **`docs/USAGE-STATS.md`**.
- `data/usage.js` (USAGE): `startUsage(store, {ver})` after the first render (main.js; never in demo mode, from
  automated browsers or off https). Rows: `start` always (Chicago day / weekday / time to the minute, app kind, version,
  first visit), `end` = seconds on screen this visit (store `usage.dur`, default on, off by default with Global
  Privacy Control / Do Not Track), `place` = nearest stop name within 400 m or "Away from stops", once per visit (store
  `usage.zone`, default off). Each row: `id` (random 128-bit, localStorage `sb:usageId`, `resetId()` for a new one)
  and `sid` (random per visit; a new visit after 30 min in the background). No coordinates, IP, user agent or
  identity. Sender (2026-10-29): `fetch` text/plain POST (no preflight) with `credentials: "omit"` (no cookies, so no
  browser login rides along), redirect followed; Google's reply ("ok" / "dropped" / "error") is readable (the 302 and the
  echo both allow any origin). keepalive for rows sent while the page goes away; one beacon only if fetch throws (result
  "failed"). The start row's outcome: `lastSend()` + bus `usage:sent`, shown in Settings (`usageStatusText`: "This visit was
  counted at ..."). Never throws.
- A reload in the same tab (by hand, or ui/update.js reloading after an update) continues the visit: sessionStorage
  `VISIT_KEY` holds it and `begin()` resumes it when it was active under 30 min ago (no second start row; owner
  2026-10-30: double counted visitors). The receiver also refuses a repeated Visit number and cleans old repeats.
- Two-minute rule (owner 2026-10-30): a start less than `QUICK_REPEAT_S` (120 s) after this browser's last start row
  (localStorage `sb:usageLastStart`, any tab) continues that visit; the receiver also folds a number's start within 2 min
  of its previous one (alias for later rows) and cleans old ones at each summary refresh.
- State: `usage: {dur, zone}` persisted (`cleanUsage`, KEYS.usage).
- Settings > Usage statistics (only when configured): `USAGE_ALWAYS` (what is always counted; "Your identity is never
  collected"), switches `usageDur` / `usageZone`, button "Get a new anonymous number". The location note adds
  `LOC_ZONE_NOTE` while the nearest stop is shared. About adds `ABOUT_USAGE` and drops "no tracking". privacy.html
  describes it (always / unless you turn it off / only if you turn it on; the iPhone app collects nothing).
- Receiver `tools/usage/Code.gs` (Apps Script web app, tabs starts / ends / places, format checks, no formulas);
  report `tools/usage_report.py` (+ test_usage_report.py). Tests: tests/usage.test.html. sw cache bumped.

## Bug check 2026-10-29 (owner: "Run a full bug check and optimization on the app and data collection methods")
- data/live.js: `parseTrips` drops non-object `stop_time_update` entries (one null used to drop the whole poll), and any
  error inside a poll sets `failed` + `liveLoaded` and counts as a failed poll (stale-data honesty: never "loading" forever).
- data/usage.js: a page loaded in the background (restored or pre-opened tab) starts its visit when first shown.
- sw.js: offline, a page opened with a query string (About's `support.html?contact=1...`) gets that precached page
  before the app shell; tests/data-pwa.js runs the real fetch handler against a fake cache.
- index.html: `<link rel="modulepreload">` for the 74 first-render modules (main.js as `js/main.js?v=5`), so they load in
  parallel instead of 8 import levels deep (2.97 s -> 2.48 s at 150 ms per request over HTTP/1.1); a test keeps the list
  equal to the real first-render graph: a new static import in the boot path must be added there.
- tests/core-dst.js pins clocks, service days, night tails, Lines by Time and usage times on Nov 1 2026 / Mar 14 2027.
- Collector and tools: docs/DATA-COLLECTION-LOG.md DC-019. sw cache sb-v2-72.
- iOS: `BusMotion.startTicking` no longer runs two animation loops after a quick background and back (a generation
  counter, so each loop clears only its own handle); `LiveActivityController` sends updates and the final end in order
  (a `lastSend` chain), so the Lock Screen never shows older numbers than the app sent last; Kit `DSTTests` pin Nov 1
  2026 / Mar 14 2027 (with tools/test_dst.py and tests/core-dst.js). CI 40840132902.

## Numbered buses; a picked bus's own times (2026-10-30, owner: "if there are multiple buses on a line, name them with a number so that if a user clicks on a particular bus it will show their arrival times at each station instead of the closest one while that bus is clicked")
- core/busnum.js (pure; iOS Kit mirrors it): `busNumbers(store.buses)` names a route's buses 1, 2, ... only when it
  shows 2 or more, in vehicle id order (numeric when both ids are numbers, else text), so names stay put while the same
  buses run; `busKey` (vehicle id, else label), `busName` ("Bus 2" / "Bus <fleet label>" / "This bus"),
  `selectedBus(state)` (store.busId, only on that route's page and while the bus is shown), `busArrival` (one vehicle
  id's own prediction at a stop, never another bus's).
- Map (map/layers.js createBusLayer): a white disc with the number at the top right of the bus badge, updated in place
  (no rebuild, the motion of map/track.js continues); name/aria-label "Bus 2, <route name>"; the picked bus gets the
  `is-picked` ring. main.js passes `selected` with drawBuses (BUS_KEYS has busId).
- A bus tap opens its route with that bus picked (main.js onBusTap -> openRoute + store.busId); in the route page
  "Where the buses are" rows are buttons (`route:bus`, again = unpick, 44 px, aria-pressed). Picked: "Showing Bus 2's
  times" + "Show the next bus at each stop" (`route:allbuses`); every station's time is that bus's own (busArrival), none
  where it has no prediction; pills / rail markers say "Bus 2". main.js clears busId when the route page closes or the
  bus is no longer shown. State: `busId` (nav, not persisted). Tests: core-busnum.js, route-busnum.js, map-layers.js,
  e2e.js (a bus tap picks it, back clears it).
- 2026-10-30 (later): a picked bus left out of a feed poll keeps its pick for `PICK_HOLD_S` (45 s, like the map's badge, MISSING_S); leaving the route page still lets go at once (`busnum.pickCheck`, main.js). sw sb-v2-75.
- Arrivals name the numbered bus (2026-11-06, owner: "When showing which bus is about to arrive at station, it should
  state which bus number displayed on the route is about to arrive if there is more than 1 bus"; ported from the live
  repo). One source, core/busnum.js: an arrival is tied to its bus by the trip update's vehicle id (else the label) and
  named "Bus 2" only when that bus is numbered on the arrival's own route (`arrivalBusName`); a Directions leg only with
  a live boarding time (`legBusName`); no vehicle, a bus the map does not show, another route's bus, a schedule or
  estimated time, a scheduled CTA time (`sched`): no number. One bus on the line: unchanged. Where: arrival rows ("Live ·
  Bus 2", "Live · Bus 2, leave in 3 min, est.", spoken too), the stop's collapsed header, Favorites, Arriving soon, My
  Routes, the route page timeline ("Bus 2" under each time when no bus is picked), Directions ("Leave in 10 min for Bus
  2, ...", "Bus 2 arrives at X"), the trip in progress (vehicle `num`, core/tripyou.js busName) and the trip and station
  alerts. Stable numbers: data/live.js keeps `store.busNums` per poll (`numberStep`: a shuttle left out of a poll keeps
  its place 45 s, like its badge); `routeNumbers(state)` adds the CTA routes from store.ctaBuses (2 or more CTA buses on
  a CTA route: Bus 1, Bus 2 in vehicle id order); the map badges (main.js `numbers: numberMap(s)`) and the trip
  (core/tripprogress.js followState carries busNums) read the same numbers. A bus that leaves for good or joins
  renumbers the line in vehicle id order. Tests: core-busnum.js (incl. CTA), data-live.js, map-layers.js,
  route-busnum.js, arrive-busnum.js, trip-view.js.

## Arriving In, trips with no bus, walk first (2026-10-30, owner: "the time that is shown when the menu is minimized ... should show the time until the next bus will arrive at their stop. Call it Arriving In: ... rather show the current walking time or the duration of the next step if the user's trip has no bus", "if the distance is very close, it is ok to just suggest the user to walk on their first travel option")
- Current trip header (main.js shows the view's meta at every detent, so also minimized): while a plan journey is on,
  nearby.js metaNearby / peekNearby return ui/views/tripprogress.js `tripMetaText`, from the same `tripNow` as the card:
  waiting = "Arriving In: 4 min" (bus at your boarding stop), on the bus = to the stop where you get off; "Arriving In:
  Now" under a minute; "~4 min" while live data is delayed (etaText, as the card); a planned time without live data
  = "Arriving In: ~4 min est." (never "Now"); no time = "No live bus time yet"; walking to the stop / after the last bus
  / a trip with no bus = "Walk 6 min" (walking minutes left: from your location to the stop or destination when known,
  else the plan's); off the last bus with no walk = "Arrived". No trip: the nearest stop's next bus, as before.
- Walk first: core/rank.js `walkFirst` (WALK_FIRST_MIN 10), applied by core/planner.js plan and again in Directions
  after the sidewalk refine: with at least one bus option, when walking the whole way takes 10 min or less or arrives
  no later than the best bus, a walk option {key:'walk', walkOnly:true, legs:[walk]} leads (selected first, "Close
  enough to walk", walking time, arrival, distance, its step and Start); bus options keep their ranked order; max 4 in
  all; the "Walking the whole way" footnote is dropped then. No bus option = the no-route screen and its help, unchanged.
- Trips with no bus: planJourney accepts the walk option (rids [], one walk leg, dest); it hides no route; the trip bar
  says "Walking the whole way, no bus"; Current trip shows "Trip to X", "Walk N min to X", "No bus needed: it is close
  enough to walk.", End trip, Trip steps (core/tripprogress.js `walkTrip` / `walkLeft`); no notification prompt.
- Tests: tests/trip-arriving.js (8), core-rank.js walk first (3), views-flows.js walk option. sw sb-v2-74.

## Trip start time (2026-11-09, ported from the live repo; owner: "when deciding a destination, the user should have an optional trip start time. This trip start time should schedule the arrivals based on the scheduled arrival time (this should have a larger disclaimer ...)")
The live repo's docs/ARCHITECTURE.md "Trip start time" is the full contract (the control, the wheels, the modes, the
rules, the disclaimer's words, data, tests). What differs here:
- CTA legs at a chosen time: Directions passes CTA's published schedule around the start time (`core/ctasched.js
  scheduledTrips(state.ctaSchedule, t0, {aheadS: AHEAD_S})`) as the plan's `trips` and no live buses; the planner keeps
  only sched:true trips in timetable mode, so a CTA leg boards a scheduled CTA trip (never a live CTA prediction) and
  reads "Scheduled bus at X" / "from the timetable" like a shuttle leg (`waitSched`, source 'timetable').
- This build has no long-way-around rule (live 2026-11-06), so the core test of the 53rd's timetable uses Ellis & 53rd St.
  to Logan Center at noon (12:04 to 12:12 PM) instead of Regenstein to Vue53; there is no shared golden file here (the
  live repo's planner answers differ by that rule).
- Files: tools/build_gtfs.py `build_timetable` (web/data/timetable.json; pages.yml rebuilds it), data/timetable.js,
  core/timetable.js, core/planner.js `plan({timetable})`, ui/views/directions.js `whenHTML` / `ttNoteHTML`,
  ui/views/leavepick.js, tripinfo.js "Scheduled bus at"; css views.css `.v-dwhen*`, settings.css `.wh-col--day`,
  journey.css `.v-ttnote`; tests core-timetable.js (incl. a CTA case), data-timetable.js, views-tripstart.js,
  e2e-tripstart.js, tools/test_timetable.py; sw sb-v2-118. iPhone: docs/redesign/GLASS-IOS-PAUSED.md.

## Line replaces line: Back after a line opened from a line (2026-11-02, owner: "Pressing back after selecting a specific line to view should not shift to the previous line but rather go to the previous menu view entirely")
- `ui/router.js navigate`: a view registered with `replaceSelf: true` (only `route`, ui/views/route.js) that is opened
  while the same view shows another id (a map line tap via main.js onLineTap, a bus tap via onBusTap) does not push the
  current entry: the new route page takes its place, so a route page never sits directly on another one in the back
  stack. Back then returns to the menu the first route page came from (My Routes / a custom route with its params and
  detent, the Routes list, a stop, Alerts, Current trip, search results). Route > stop > route keeps every step (the
  stop sits between them); a route already on the stack still pops back to it (no loops). The browser's back, Escape
  and the header Back all call `back()` (main.js keeps one history entry while in a sub view), so they agree.
- iOS: `AppModel.showPage` (used by `push` and `busTapped`) replaces a `.route` on top of the path with the new one.
- Tests: tests/ui-shell-router.js (4: My Routes > Central > 53rd > Back, from any menu, route > stop > route, stop >
  stop still stacks), tests/e2e-backnav.js in e2e.test.html (3, the real app with real map line taps: My Routes >
  Central > 53rd Street Express > Back or browser back = the custom route page, unchanged; Routes list > line > map tap
  on another line > Back = Routes list; a single line > Back and browser back). sw `sb-v2-80`.

## Redesign: layout and shell contracts (2026-11-03, docs/DESIGN-SPEC.md; owner brief "Straight Bussing New Version.txt")
The navigation structure is unchanged (search bar with clock and gear, three sections in the bottom bar, sheet with two
resting states, back stack, Settings and Lines by Time overlays); what changed in the shell and the contracts views use:
- **Tokens** (`css/tokens.css`): the spec's token table under its CSS names; the old names stay as aliases. Root = body
  size (`html { font-size: 106.25% }`, `-apple-system-body` on iPhone Safari); every type role is `calc(1rem * n / 17)`.
  `js/ui/frame.js initTextSize` sets `html[data-text]` = `default` (< 20 px root), `large` (20 to 27), `ax` (28+);
  stylesheets stack rows, buttons, option lines and the sheet header's trailing slot at `ax`.
- **Icons**: `js/ui/icons.js` is the one set (`svg(name, size, {cls, stroke})`, `pair(name)` for outline / filled);
  `index.html` inlines the same SVGs for the static chrome; `components.js icon()` maps the old names onto it.
- **Sheet** (`css/sheet.css`, `js/ui/sheet.js`): opaque `bgSheet`, no backdrop blur; `--v-peek` is set on `#app` from the
  measured header height (first measurement without a slide), so the collapsed sheet grows with text; `.is-scrolled`
  shows the header hairline. Header markup: `.titletext` holds `#title` and `#subtitle`; `#titleRight` is the
  trailing slot.
- **View header contract** (main.js `renderHeader`): `def.title(state, o)`, `def.subtitle(state, o)` and
  `def.metaHTML(state, o)` (trusted markup built with esc(); else the plain-text `def.meta`), with `o = {detent}`; the
  header re-renders on every store change, on a sheet state change and on the bus event `sheet:header` (a view's own
  state changed, e.g. Directions selected another option). Header actions (`[data-action]` in `#titleRight`) are bound
  like the content's. Users: nearby (badge + ETA + live dot; during a trip the next step over "Trip to X" with Arriving
  In when collapsed, "Current trip" when expanded), stop (next arrival), route (`routeStatusText`), directions (selected
  total), routes (`routesMetaHTML`: Edit map order), myroutes (`myRoutesMetaHTML`: New).
- **Status** (`js/ui/pill.js`): `#pill[data-form]` = `chip` (simulated buses: 32 pt capsule, whole chip is the button)
  or `banner` (every feed state: full width, opaque warn / danger background, first sentence Semibold via
  `setPillText`). `--pill-h` and the expanded state below the banner work as before; the locate button moves under a
  banner. The banner's action (Retry or See alert, never both) is the FIRST child, a fixed 84 x 44 `.pillslot` on the
  leading edge (owner 2026-11-03, spec 10.3): after a Retry tap `pill.js` keeps the banner's height and content until
  `RETRY_HOLD_MS` (2.5 s) after the last tap; if the feed answers meanwhile it says `BACK_MSG` ("Live data is back.")
  with a check and Retry absorbs taps (`aria-disabled`), so the trip chip (whose Show all ends the trip) never slides
  under a tapping finger. Repeated taps join the running poll (`data/live.js pollNow`). Tests: `ui-shell-pill.js`
  (slot order, the hold) and the e2e "Retry tapped again and again during a trip".
- **Trip chip** (`js/ui/contextbar.js`): badges (up to 3, then "+N"), "Trip to X" / "Routes to X" / the Lines by Time
  name / the custom route's name, Show all / Clear; only the label truncates; no marquee.
- **Toast** (`css/base.css`): 12 above the collapsed sheet, 12 above the bottom bar when expanded, hidden while an
  overlay (Settings, Lines by Time) is open.
- **Map** (`js/map/layers.js`): `lineWeight` by the spec table, `FOCUS_EXTRA` 2, `CASING_EXTRA` 3, `casingClass(color)`
  (" sb-cl" / " sb-cd" flip the casing under 3:1 per theme), `stopStyle(z)`, `routeLabel` = the badge's chipText (never
  truncated), `notchRadius(w, h, deg)`; dimmed lines are drawn without casing. `js/map/landmarks.js` takes an `avoid()`
  callback (the location dot). `css/map.css` reads `--sb-accent` (tintFill) and `--sb-tint` (tint).
- Performance rules kept: the sheet's `--drag` stays non-inherited, `will-change` only while dragging, content insets
  change after a settle, bus markers update in place on requestAnimationFrame; at most four blurred elements.
Deviations from the spec: `docs/redesign/NOTES-web.md`; screens: `docs/redesign/after/web/`. sw `sb-v2-85`.

## Glass redesign: shell contracts (2026-11-04, docs/DESIGN-SPEC-GLASS.md, a delta on DESIGN-SPEC.md)
Apple Maps' iOS 26 layout in Liquid Glass; functions, words and states unchanged. What moved and the contracts views
and tests rely on:
- **Glass** (`css/tokens.css` glass tokens, `.glass` in `css/base.css`): only the control layer over the map (tab bar,
  search circle, Settings circle, lower-right group, simulated-buses chip, trip chip, the collapsed card's plate, the
  feedback circle as the one tinted glass).
  `#app.is-moving` (ui/sheet.js, while the sheet drags and settles) and `.glass--moves` make moving glass solid;
  `html.glass-lite` (ui/frame.js `initGlassLite`, a slow device) and Increase Contrast / Reduce Transparency make all
  glass solid. Budget: at most 6 blurred surfaces on at most 22% of the screen at rest (e2e "glass budget").
- **Top rows** (fixed, `css/base.css`): `#pill` = Row A (banner form, topmost, Retry / See alert slot leading, 2.5 s
  hold) or Row B leading (chip form); `#topbar` = the Settings circle (Row B trailing); `#ctxbar` beside Settings or
  under the chip. `--banner-h` (from `--pill-h`), `--row-b-top`, `--ctx-top` on `#app`.
- **Bottom row** `#bottomrow`: `<nav id="tabs" class="tabcap">` (the three sections, `.tab-pill` moved by `--tab-i`,
  written by main.js) and `#searchBar` (the search circle, `dir:open` + `data-focus="to"`). `--nav-h` = the space it
  takes from the bottom (`--bottom-inset` + 56). Hidden while a sheet text field has focus on touch screens and under
  Settings / Lines by Time.
- **Sheet** (`css/sheet.css`, `js/ui/sheet.js`): bottom at the screen's bottom, `--v-max` tall; collapsed visible
  height `--v-peek-vis` (card + 8 + the bottom row; the peek probe measures it), expanded `--v-full`. `.sheet-bg`
  holds `.sheet-glass` (the card's plate, header height, inset 12) and `.sheet-solid` (the opaque sheet); while
  dragging, `paintP()` writes opacity / transform on `.sheet-solid`, `#content` and `#mapctl` from the progress p
  (opaque by p .35, the group gone by p .30); at rest css drives them from `data-detent`. `--card-k` (card width /
  sheet width) on `#app`. The sheet element takes no taps while collapsed except its header and `#mapctl`.
- **Lower-right group** `#mapctl` (inside `#sheet`, `bottom: calc(100% + 8px)`): `#timeBtn` over `#locateBtn`; rides
  with the sheet's transform, hidden when expanded. The map's bottom inset adds its height while collapsed
  (`MapApi.setBottomInset(px, controls)`), the credit does not.
- **Directions**: the Start / Destination card is the first child of the view, sticky; `#dirbar`, the search bar morph
  and `barRects` / `useBar` are gone.
- **Settings / Lines by Time** (`ui/settings-overlay.js`): a sheet of its own (top = safe + 10, bottom 0), zooming out
  of its opener (`zoomOrigin`), swipe down on the header closes (`SWIPE_CLOSE_PX`), Done = checkmark named "Done",
  Cancel = cross named "Cancel"; it no longer moves the app's sheet; the app behind is inert.
- **Confirm dialogs** grow out of their button (`ui/confirm.js zoomFrom`). Buttons and segmented controls are capsules.
- **Compact status banner** (owner 2026-11-04: "Reduce the size of the reconnecting notification."; `ui/pill.js`,
  `css/base.css`): one 44 pt line in the footnote role, a CSS grid of [action slot 84 x 44] [icon] [`.pillmore`]. The
  slot keeps the owner's Retry rule (leading, fixed, 2.5 s hold). `pillState().short` is the line ("Live data lost. Times
  may be off.", "No live data. Don't rely on times.", "Last update 1:23 PM. Times approximate."; it always says the times
  can't be relied on), `msg` the full sentence in `#pillText` (always in the live region for screen readers, visually
  hidden until open). `.pillmore` (name "Details", `aria-expanded`, `aria-controls="pillText"`) opens the sentence and
  `.pillcall` "Call 773.702.8181" (`tel:`) under the line; the line never moves, the banner only grows downward (Row B
  follows `--pill-h`), so fast taps on it never land on the trip chip. Open stays open across state changes; a banner
  that comes back starts closed. The demo chip has no Details.
- **Feedback circle** `#feedbackBtn` inside `#topbar` under Settings (see "Beta feedback" above).
- **Trip chip at the full detent** (owner 2026-11-04: "When the menu is expanded, the current trip showing at the top of
  the screen should still show (same way as the settings button)"): `#ctxbar` no longer hides when expanded; beside
  Settings it needs no room; in Row C (with the simulated-buses chip) `--v-full` shrinks by 36 + 8 so the expanded
  sheet starts 8 below it (sheet.css). Peek never moves for it.
- **Current trip with no trip** (owner 2026-11-04: "if a current trip is not selected, don't display nearby routes, rather,
  just show that no current trip is selected. Keep the favorites and search station bar. Also keep the alerts."; spec 18
  D6): `views/nearby.js` renders the alert row, `noTripHTML()` ("No current trip selected", `NO_TRIP_HINT`, a
  Search for a destination button = `dir:open`), the station search with its links, and the favorites; `nextHTML`,
  `locHTML` and the Arriving soon / Also nearby lists run only during a trip (or for a typed place, the search's own
  result); `metaNearby` / `metaNearbyHTML` are empty and the collapsed subtitle is `NO_TRIP_TITLE`. Tests run the nearby
  list with a trip (`views-fixtures.js onTrip`).
- **Basemap roads** (owner 2026-11-04: "Do not make the main streets yellow. The highways being yellow is ok."): only
  motorways (and motorway bridges) are yellow-orange; main streets white / gray (`map/style.js PALETTE`); a test checks
  no other road layer has a yellow or orange hue.
Deviations from the glass spec: `docs/redesign/NOTES-glass-web.md`; screens: `docs/redesign/glass/web/`. sw `sb-v2-93`.

## Faded buses, trip-only lines, thinner lines without outlines (2026-11-04, owner: "The buses on faded routes should also be faded. If on a trip, only the lines on the particular trip should be displayed.", "Remove the outlines for the lines but make the lines themselves thinner. All these changes should go onto the experimental build.")
Ported by hand from the live app (straight-bussing commit d0e20d0e on its branch `fade-buses`; the live
docs/ARCHITECTURE.md has the full section).
- core/visibility.js (same file as live): `tripRoutes(state)` (the trip in progress: its bus legs' routes, [] for a walk),
  `mapHidden(state)` (on a trip every route but the trip's, a walk none; else effectiveHidden; `mapVisibility().hidden`),
  `busFaded(rid, focus, plan)` (other routes in focus, or a drawn plan that does not ride it). A display rule only:
  nothing saved changes; the lines come back when the trip ends. A route page opened during a trip still draws its
  route. The Directions preview is not a trip (every line stays, dimmed).
- map/layers.js: a bus on a faded route is faded (`dress`: `.is-faded`, scale .8, opacity .42, z offset 300, no tap; the
  bus you ride never); hidden routes' buses never (unless in focus). No casing (casingClass, CASING_EXTRA, CASING_BASE,
  the `sb-cl` / `sb-cd` css are gone); map/map.js passes the plan's routes to the bus layer and draws plan legs
  (`sb-plan-bus`) and walking dots without casings. Thinner at every zoom: LINE_WIDTHS z13 2, z14 2.25, z15 3, z16 4,
  z17 5, z18 6 (was 3, 3.5, 4.5, 5.5, 6.5, 8), focused lines + FOCUS_EXTRA; `lineTapWidth` keeps the old tap reach.
  (The live app only thins lines zoomed out, 30% up to z15, and keeps focused lines at full width.)
- Tests: core-custom.js, map-layers.js, map-direction.js, map-trip.js, map-style.js (the route edge test removed), e2e.js
  (preview fades the other buses; a started trip draws only its lines and buses; all back after End trip). sw `sb-v2-90`.
- iPhone: paused; what to port is in docs/redesign/GLASS-IOS-PAUSED.md.

## Add to Home Screen prompt (2026-11-09, owner 2026-11-07/09: "If the app/website is not opened from the home screen, create a popup that clearly shows how the user could add the app to their home screen. This notification should be closable but make the top of the notification clearly say: Add this website as a home screen app!. The instructions should use the actual apple safari or chrome symbols to make it as intuitive as possible. if there is a way that you could do it for the user where they just press a button, do so. If the app is opened from the home screen, do not show this notification.")
Website only (the iPhone app is a native app). Same code as the live repository (port of its 2026-11-09 commits). Modules: `core/install.js` (the shared check, browser detection, the
show rules, the memory), `core/installsteps.js` (the words and steps), `ui/install-prompt.js` (the card), main.js (the
install event, start, the Settings action), `views/settings.js a2hsRowHTML`, css/base.css `.a2hs*`.
- **Installed = never.** One check, `isInstalled(installEnv())`: `navigator.standalone` (iPhone / iPad Home Screen apps)
  or a display mode only an installed web app has (standalone, fullscreen, minimal-ui, window-controls-overlay). In the
  installed app main.js never loads the popup and Settings has no row. `core/lochelp.js locEnv` and `data/usage.js
  appKind` use the same check (the usage rows keep app = "home-screen" / "browser"; the install choice is not reported).
- **When it shows by itself** (`autoBlocker`, pure): not installed, not in demo mode, not under the tests' seam
  (sessionStorage `sb-a2hs-off` = "1", set by every real-app test page), a browser that can install (`installPlatform`
  is not "none", or the browser offered its own install), never after an install from this browser or "Don't show
  again", and at most once every 14 days counted from the later of the last show and the last close (`RESHOW_DAYS`;
  a rider who leaves it open is not asked again on a reload either). Timing, rider safety first: `SHOW_AFTER_MS` 4 s
  after the live feed first answered (store liveLoaded or failed: the next bus is on screen first), `MAX_WAIT_MS` 12 s
  at the latest; a due card waits (`RETRY_MS` 5 s, `waitReason`) during a trip (journey.kind "plan"), with the sheet
  expanded, Settings / Lines by Time or a dialog open, a focused text field, a hidden page, or while the feedback button
  pings. The feedback button in turn never pings while the card is open (`pingBlocker` "install card open",
  `#a2hs[data-state="open"]`). A trip started while it is up: it closes quietly (no close remembered).
- **The card** (`#a2hs`, inserted after `#ctxbar`, so the focus order is the top rows, the card, the sheet): a non-modal
  `role="dialog"` (aria-modal false, labelled by its heading, described by the why line); no focus taken when it shows by
  itself. Under Row B (or under the trip chip), in the leading column so the Settings and feedback circles keep theirs
  (width min(360, screen - 24 - 44 - 8)); its height stops 8 above the collapsed sheet (the next bus) and scrolls; it
  moves down with Row B when the status banner shows, so a stale-feed warning is never covered; hidden while the sheet is
  expanded; inert under Settings. Solid in the glass family (glass spec 5.1: content is solid; 12.1 has no blur budget for
  a card this size): `--glass-solid` with the glass rim, edge and shadow, `--r-glass`, `--z-chip`; text label / label-2
  (contrast tested >= 4.5:1). Entrance: 220 ms rise and fade (reduced motion: none).
- **Words** (`core/installsteps.js`): heading `INSTALL_TITLE` "Add this website as a home screen app!" (exactly the
  owner's), then one line on why: iPhone "It opens full screen like an app, one tap from your Home Screen. There, bus
  alerts can also arrive as notifications (iOS 16.4 or later) while the app is open or was just used."; Android "It
  opens full screen like an app, one tap from your home screen."; computers "It opens in its own window like an app, one
  click away." Close = a 44 button named "Close" (a 32 fill circle with a cross; Escape inside the card does the same);
  last a small "Don't show again". Toasts: "Add to Home Screen stays in Settings." (Close), "It won't show again. Add to
  Home Screen stays in Settings.", "Added. Open Straight Bussing from your Home Screen." / "Installed. Open Straight
  Bussing from your apps."
- **One button where the browser can install for the rider.** Chrome, Edge and Samsung Internet (Android and computers)
  fire `beforeinstallprompt`: main.js prevents it (no mini-infobar) and keeps it from its first module run; the card
  then shows ONE primary button, "Add to Home Screen" on phones, "Install app" on computers, whose tap calls `prompt()`
  synchronously; accepted (or `appinstalled` from the address bar or menu, recorded by main.js even before the card
  exists) = installed for good, dismissed = a close. The steps fold away under "Other ways to add it". An offer that
  comes while the steps show swaps in the button. iPhone and iPad have no programmatic install: always steps.
- **Steps with the browsers' own glyphs** for the browser in hand (`installPlatform`, user agent read on the device only),
  numbered, each glyph inline at text size in a key-like chip with alternative text (`INSTALL_ICONS`: "Share button",
  "More button", "Add to Home Screen", "Menu button", "Install button", "App available button"); the other browsers fold
  away under "Other phones and browsers". Glyphs are Lucide lookalikes in ui/icons.js (`share` = square and arrow up,
  `square-plus`, `ellipsis`, `ellipsis-vertical`, `monitor-down`, `menu`, and a drawn `apps-plus` for Edge): Apple's SF
  Symbols license does not allow them on the web; Lucide (ISC) is already in Settings > Credits and About.
  - iPhone / iPad Safari: "Tap Share. Don't see it? Tap More next to the address bar first, then Share." / "Scroll down
    and tap Add to Home Screen. Not in the list? Tap "View More" first." / "If you see "Open as Web App", leave it on.
    Then tap Add." This covers iOS 26 and later in the default compact tab layout (Share sits behind the More button at
    the end of the address bar), the Bottom / Top layouts and iOS 17 and 18 (Share in the bottom toolbar on iPhone, at
    the top on iPad), the share sheet's "View More", and iOS 26's "Open as Web App" switch (on by default; earlier
    versions have none). Apple's guide lists iOS 27 as current; no change to this flow was found for it.
  - Chrome on iPhone: Share at the right end of the address bar, Add to Home Screen, Add. Other iPhone browsers: their
    menu, Share, Add to Home Screen, else Safari. In-app browsers (Instagram, the Google app, a web view): open in
    Safari first.
  - Android: Chrome's menu (three upright dots), "Add to Home screen" or "Install app" (the words differ between
    versions), "Install"; Samsung Internet's menu, "Add page to", "Home screen"; Firefox's menu; in-app: open in Chrome.
  - Computers: Chrome's install icon at the right end of the address bar, or the menu, "Cast, save, and share", "Install
    page as app"; Edge's "App available", or the menu, "Apps", "Install this site as an app"; Safari on a Mac (macOS
    Sonoma or later): Share or File, "Add to Dock". Firefox on a computer cannot install: no card (unless an install
    event comes).
  - Sources (checked 2026-11-09): MacRumors "iOS 26: Add Web App or Bookmark to iPhone Home Screen" (three dots right of
    the address bar, Share, Add to Home Screen, Open as Web App, Add); iPhone Life "How to Add a Website to Your Home
    Screen" (tested on iOS 26.4: More, Share, maybe View More, Add to Home Screen); Apple Support "Turn a website into an
    app in Safari on iPhone" and "Bookmark a website in Safari on iPhone"; Google Chrome Help "Create shortcuts for
    websites" (iPhone) and "Use web apps" (Android, computer); Microsoft Learn "Use Progressive Web Apps in Microsoft
    Edge"; Samsung Internet guides (menu, Add page to, Home screen). To confirm on a real iPhone (owner QA).
- **Memory** (`core/install.js`, core/storage.js, so demo writes stay in memory): localStorage `sb:a2hs` =
  `{shownAt, closedAt, never, installedAt}` (ms); blocked storage = this page load only. privacy.html "Your settings"
  (effective November 9, 2026) lists it and says the browser / device is read on the device only and nothing is sent.
- **Settings > Add to Home Screen**: a quiet row right above About ("Open it full screen like an app: the steps for this
  browser"), only outside the installed app and demo mode; action `install:open` (main.js) closes Settings and opens the
  card with focus on its heading (Close returns focus to the Settings circle). So a closed card is never a dead end.
- Tests: core.test.html core-install.js (the check, the user agents, the rules, the memory) and core-installsteps.js
  (words, glyphs, steps per browser); install.test.html install-prompt.js (the card: words, glyphs, button, waits,
  Close / Escape / Don't show again / installs, 14 days) and install-app.js (the real app: the install event kept and
  remembered, demo untouched, the Settings row, the Home Screen app, an iPhone Safari first visit with placement,
  contrast and no blur, the stale banner, the expanded sheet, Close and 14 days, Don't show again, the one-tap button,
  trip / demo / seam, privacy.html). Ported from the live repository (sw there `sb-v2-147`); here sw `sb-v2-119`. Not yet seen on a real iPhone or Android phone.

## Route search on the Routes list (2026-11-04, owner: "You should be able to search routes from the routes menu which will bring them to the top. Allow keywords and smart search such as allowing 53rdst -> 53rd Street or 53rd St -> 53rd Street etc.")
Hand-ported from the live repo (same core files; its docs/ARCHITECTURE.md "Route search" has the full contract).
- `core/routesearch.js` (pure): `buildRouteIndex` / `routeIndexFor(state, ids)`, `searchRoutes(index, q)` -> `[{id,
  score, stop?}]` best first, `splitByHits`, `matchText`, `routeWords`, `canon`. Text = `core/text.js norm` (the
  place search's; data/places.js imports `norm` and `near1` from there) + letters split from digits with the ordinal
  dropped ("53rdst" = "53rd st" = "53 st"), number words, abbreviations both ways (st, ave, ctr, dt, sth, n / s / e /
  w, ...), keywords = short name, long-name words, stop names; one typo on 4+ letter words. Ranking: exact 100 > start
  of a name 90 > all words 80+ > abbreviations 70+ > one stop's words 60+ (names the stop) > typos 50+ / 45+.
- `ui/views/routes.js`: region `[data-region="routes-search"]` between the custom-route bar and the body (Edit map
  order stays the sheet header's action, `routesMetaHTML`), drawn once and never rebuilt while typing. Body with a
  query: "N routes match" (a grouped card, "Stops at <stop>" on stop matches), or the "No routes match" empty-state
  card + Clear search, then the "Other routes" divider, the bulk capsules and the usual groups. Clear button
  (`circle-x-fill`, label2) "Clear route search", Escape clears, aria-live count, focus opens the sheet; display
  order only, nothing stored. css `.rt-search`, `.rt-qx`, `.rt-qdiv`, `.rt-qnone`, `.rt-why`.
- Tests: tests/core-routesearch.js, tests/routes-search.js; golden `web/tests/routesearch-golden.json`
  (`python tools/gen_routesearch_golden.py`). iPhone: noted in docs/redesign/GLASS-IOS-PAUSED.md. sw `sb-v2-94`.
- Active routes first (2026-11-05, owner: "should still show results if they are inactive (the top results, unless the
  name is clearly specified, should priortize active routes--make it clearly show which ones are active by graying them
  out in results)"): every route stays findable; `rankByActive(hits, active)` keeps a route the query names (score >=
  `NAMED_MIN` 88.5) on top, then the matches operating now (`operatingIds`, the Show running rule), then the rest;
  null while live status is unknown (no reorder, no gray). A match that does not operate now is `.v-routerow.is-idle`
  (gray chip, label2 name) and says "Not running now · Scheduled from 4:00 PM today" / "... No more service today"
  (`notRunningText` over myroutes.js `restingText`); hidden keeps its fade and eye, hidden + not running shows both.
  Golden `active` cases. sw `sb-v2-95`.
- Results first (2026-11-05, owner: "Routes that come up in searching for my routes should appear right under the
  search bar above the phone numbers and other information."): with text in the field `listHTML` starts with "N routes
  match" + the matches (or the "No routes match" card + Clear search); the station filter chip, the feed notice (No
  live locations / No shuttles running / Live bus status unavailable), "From the shuttle operator", the "Other routes"
  divider, the bulk capsules, the groups and the calls / official page follow. Nothing is removed (rider safety: the
  alerts and both numbers stay on the page, below the matches). With a station filter the heading names it ("1 route
  matches at Main") and an empty result says "Only routes to Main are searched. Clear the station filter to search
  every route." Empty field: the old order. Tests: tests/routes-search.js (the two "matches ... lead" cases). sw
  `sb-v2-97`.

## Route colors on the dark map (2026-11-06, owner: "Outline or change coloring of the dark shuttles to make them more noticable.")
The same change as the live repo (its docs/ARCHITECTURE.md has the full numbers): `core/routecolor.js` is the live
file unchanged. On the dark map a shuttle color under 3:1 against the land (#202124) is lifted in OKLab, hue and chroma
kept, to 3:1 against the land and the street fill (#3A3B40) with AA badge text: Downtown Campus Connector #509446,
Regents Express #7A80C5, Apostolic #487FFF, Friend Center/Metra #BE743D, Move In Charter #BD6F6A (badge text dark
#111114); the other ten and the light map keep the published colors; no outline. Here `map/cta.js lineColorFor(rid,
color, dark)` picks per route: shuttles `mapColor`, CTA `ctaLineColor`, whose dark branch is now the same
`liftForDark` against the land only (CTA lines stay quieter than the shuttles: key-route gray #414145 -> #6C6C70, still
darker than the regular #747477; CTA red #B71234 -> #CB2D43, blue #0065BD -> #0E6BC4); its light branch is unchanged.
Lines, one-route stop outlines, chevrons and planned legs use `lineColorFor`; shuttle bus badges `mapColor` (CTA badges
keep the route color); `MapApi.setTheme` recolors in place (network, buses) and redraws a drawn plan. Tests:
core-routecolor.js + fixtures/routecolor_golden.json (the live copies), map-layers.js "dark map", map-style.js, map-cta.js.
iOS: not here (paused); docs/redesign/GLASS-IOS-PAUSED.md.

## Lines stay on the roads through zooms (2026-11-06, owner: "When switching line views while zoomed in, the map sometimes glitches the routes to not be matched to the roads. Fix this.")
- **Cause (Leaflet 1.9.4, measured in headless Edge).** Every line-view switch frames the map with a 0.6 s flight
  (`fitTo` = flyToBounds, `flyTo`). A flight cut short by `map._stop()` ends with no `zoomend`: Leaflet's drag handler
  calls `_stop()` when a finger or the mouse drags the map during the flight (setView and a new flight call it too).
  The SVG renderers reproject their paths only on `zoomend` / `viewreset` but move their viewBox to the new zoom at
  `moveend`, so the route lines, stops, chevrons and the plan stayed drawn at the scale of the zoom the flight started
  from (zoomed in at 17 and cut at 15.6: 1,000 to 8,200 px off the roads) until the next zoom. The same cut left
  maplibre-gl-leaflet in its zooming state (basemap sync paused), the bus layer's glides paused (no badge moved) and
  `sb-zooming` on the map (building names hidden). Second, a network redraw during a flight or a wheel / double-tap zoom
  animation (Back, Hide all, a custom route or Lines by Time cleared) projected the new lines at that frame's zoom
  inside renderers still framed on the start: 700 to 5,000 px off for the rest of the animation. And a fit asked for
  during a zoom animation ran on top of it (the animation's end jumps the view back mid-flight; a non-animated fit
  was dropped).
- **Fix (map/map.js).** `syncView(map)` (installed first by `createMap`) wraps `map._stop`: a zoom that started and
  is cut (not a CSS zoom animation, which ends by itself) gets `zoomend` then `moveend` at the view where it stopped,
  the way Leaflet ends a finished flight, so every layer settles there. `drawNetwork` (and the plan's dimming redraw)
  goes through `drawNet`: while `midZoom()` (a zoom started and has already moved the view) the latest network is held
  and drawn once at `zoomend`, against the final view; the lines drawn before stay, on the roads; `NET_HOLD_MS`
  (1.5 s) caps the hold (a long pinch). A redraw at the first frame of a flight (opening a route: navigate, then fit)
  is not held. `fitTo` / `flyTo` asked for during a zoom animation start when it has ended (`afterZoomAnim`, the
  latest request wins). Line taps (`lineAt`) project the drawn lines at tap time, so they use the final geometry.
- **Measured** (scratch matrix: open a route, Back, another route, line tap, custom route on / off, Hide all,
  Show all, Show running, Lines by Time on / off, Directions preview, trip start / end; each during a flight, cut by a
  drag, and during a wheel zoom, from zoom 17): after settling, every path within 1.4 px of the basemap (rounding;
  before, the eight cut cases were 990 to 8,200 px off); during flights within 2 px of the map, during zoom
  animations within 2.1 px of the basemap. Sheet drags never move the map.
- Experimental build: ported from the live site (a6f1153f) as is; the CTA lines are drawn by the same network
  layer, so their redraws are held the same way.
- iOS: the lines are MapKit `MapPolyline` content drawn by MapKit with the camera (and `lineHit` converts at tap time),
  so the app has no equivalent; unchanged.
- Tests: `web/tests/map-viewsync.js` (map.test.html): a fit cut by a synthetic drag ends with zoomend then moveend,
  the held switch is drawn there, every path (lines, stops, chevrons) projected at the final zoom and drawn within
  1.5 px of `latLngToContainerPoint`, a line tap names the line; switches during a flight are held and drawn once at
  the end; the NET_HOLD_MS cap; buses glide again after a cut flight. Flights are stepped with Leaflet's own
  `_moveStart` / `_move` (headless virtual time starves requestAnimationFrame). sw `sb-v2-114`.

## CTA routes beside the shuttles (2026-11-06, experimental only; owner: "implemenent the CTA routes in the same way passio go shows but make the bus shapes identifiable to be cta and make their stations square. Also list them noticably idfferently on the routes menu. They should still behave on the interface like the normal bus routes.")

The research and the plan for the live app are the live repo's `CTA Implementation.md` (routes, data sources, terms,
budget); this section is the experimental build's contract.

**Data, the way Passio's is done.** CTA's GTFS zip has no CORS header, so `tools/build_cta.py` (tests
`tools/test_build_cta.py`) keeps the 14 CTA bus routes that serve Hyde Park (2, 4, X4, 6, 10, 15, 28, 47, 55, 59, 63,
171, 172, 192) and only their stops, line shapes and stop times inside BOX (47th to 63rd Street, King Drive to the
lake), and writes `web/data/cta/{routes,stops,shapes,route_stops,patterns,service,schedule,meta}.json` (about 160 KB).
`pages.yml` runs its tests and then the tool on every deploy and daily, keeping the committed copy on failure. Details:
route colors are CTA's, darkened until white text passes 4.5:1 (`cta_color` keeps CTA's own); stop names carry the
direction like the shuttle names ("55th Street & Ellis (EB)"); shapes lose CTA's curb jogs at stops (`despike`) and
are clipped and simplified; a day whose one window covers 23 hours or more is written 00:00 to 24:00 ("24 hours").

**Ids.** Every CTA route, stop, trip and vehicle id is namespaced `cta:` (route `cta:171`, stop `cta:1427`, vehicle
`cta:8123`). The live Passio route_id join stays Passio-only. `core/agency.js isCta(id)` tells them apart.

**Static: the same slices.** `data/static.js` loads the CTA files beside Passio's (all optional, failures in
`ctaFailed`, never `failed`) and `data/cta-static.js mergeCta` adds the `cta:` entries (only those: a CTA file can
never replace a shuttle route or stop) to store.routes / stops / shapes / routeStops / service.routes (CTA's feed
window as service.ctaFeed). New slice `store.ctaPatterns` = patterns.json: `{"cta:55": [{dir:"Westbound",
stops:[...]}, {dir:"Eastbound", stops:[...]}]}`; `routeStops[cta rid]` is direction 0 then direction 1. So
visibility, custom routes, map order, favorites, route search, the route and stop pages, line taps and Lines by Time
treat CTA routes like any route, with no special case.

**Live: separate slices.** CTA vehicles and predictions are NEVER in store.buses / store.trips. `data/cta-live.js`
(started by main.js after the first render) writes only `store.ctaSchedule` (decoded schedule.json),
`store.ctaBuses`, `store.ctaTrips` and `store.cta = {mode, lastOk, failed, feedTs, loaded}`; every shuttle rule
(staleLevel, liveUnknown, silent service, "No shuttles running", off-route hiding, operating buses, the status
banner) keeps reading Passio's slices only, so a CTA failure never hides the shuttle state, or the reverse.
Code that shows "the buses" or "the arrivals" of any route reads both: `arrivalsFor` and `runningCount`
(core/arrivals.js) read the CTA slices too; `allBuses(state)` / `allTrips(state)` (memoized concatenations) feed the
map, the route page, the planner; `selectedBus` looks among CTA's buses for a CTA route. `core/operating.js`
`scheduledRoutes` and `scheduledNoLive` never count a CTA route; `data/demo.js` (it stands in for Passio's feed)
simulates shuttles only; `core/coverage.js` (the 800 m note names "the campus shuttle routes") measures from shuttle
stops only.

Modes of `data/cta-live.js` (`ctaLevel(store.cta, now)`: off / demo / wait / err / late / fresh):
- `off` (default: `CTA_LIVE_URL = ''`): every minute `store.ctaTrips` = the next 90 minutes of scheduled stop times
  (`core/ctasched.js scheduledTrips`, trip ids `cta:sched:<rt>:<dir>:<start>`, each entry `sched:true`); no CTA bus
  is drawn. `arrivalsFor` returns those with `sched:true`.
- `live` (`CTA_LIVE_URL` = the owner's proxy, `tools/cta-proxy/`): polls every 20 s (paused in a background tab unless
  bus alerts need it), the same URL for everyone, nothing about the rider. Answer `{v, ok, ts, vehicles:[Bus Tracker
  vehicle], predictions:[Bus Tracker prd], errors}`; `parseCtaLive` keeps known routes and stops, drops reports over
  5 minutes old and predictions with dyn 1 / 4 / 16 / 17 (canceled, drop-off only, invalidated), sets each bus's next
  stop. A failure or `ok:false` keeps the last answer (flagged) for `FALLBACK_S` (120 s), then scheduled times take
  over, labeled.
- `demo` (`?demo=1`): simulated CTA buses on CTA's own schedule (`demoCta`: each trip under way between its last and
  next stop on the line shape, predictions for the trips under way or starting within 30 minutes); never the proxy.

**Wording and labels (ship checklist 1, 2, 5).** A CTA scheduled time is never live: arrival rows say "Scheduled,
est." with a hollow square (`.dot-sched`), the time gets "~", screen readers hear "CTA route 171, ..., scheduled time,
an estimate" (`components.js ctaArrLabel`, `arrStale`). A CTA live prediction takes its freshness from `store.cta`
(`ctaLevel`), never Passio's. Status lines of a CTA route come from `core/agency.js ctaStatusText` ("2 buses live",
"1 simulated bus", "Scheduled 24 hours", "Scheduled until 1:38 AM", "Not running now · Scheduled from 6:00 AM today"),
never "no live location"; where CTA times come from is `ctaSourceText` ("Scheduled times · CTA live data not
connected" / "... unavailable" / "CTA live data"). CTA pages end with CTA's contact (transitchicago.com,
1-888-YOURCTA, customer information) and "Data provided by Chicago Transit Authority. Straight Bussing is unofficial
and not affiliated with CTA." (`routes-cta.js ctaContactHTML`); 773.702.8181 stays for the shuttles.

**Screens.**
- Route badge (`routeChip`): a CTA route's is squared (`.chip.chip--cta`, radius 2 px) and reads "CTA 171". Never a bare
  `.cta` class: that is the shell's call-to-action button style.
- Routes list: the shuttle groups hold shuttles only (`groupRoutes`); after them a "CTA buses" section
  (`ui/views/routes-cta.js ctaSectionHTML`): a rule, a squared "CTA" mark, the heading, its own Show all / Hide all
  (CTA routes only), the time source line, the CTA rows (same eye toggle and route page), a CTA "Hidden" part, CTA's
  contact and credit. Search matches CTA routes by number and name ("171", "55 garfield"). Show running keeps the
  CTA routes the schedule or a CTA bus has running (`ctaOperating`); the list's Show all / Hide all count them.
- Route page: one timeline per direction (`store.ctaPatterns`, headings "Southbound" / "Northbound"), each with its
  buses heading along it (`busPositions(state, rid, now, only)`); CTA's status and source lines; no shuttle no-bus help;
  CTA's contact at the end. Hours & service from CTA's schedule (the Hyde Park part).
- Stop page: "CTA stop 1427" in place of an address, CTA arrivals without waiting for the shuttle feed, "No CTA bus
  scheduled in the next 90 minutes" when empty, CTA's source line and contact as the footer.
- Current trip: the nearest SHUTTLE stop stays the hero (CTA stops sit on every block); the nearest CTA stop within
  800 m gets its own "CTA nearby" card; "Arriving soon" stays shuttle-only. My Routes: saved CTA routes say CTA's
  status; the editor lists CTA routes in a "CTA buses" group.
- Map (map/cta.js, map/layers.js): CTA buses are squared badges with a "CTA" tag (`.sb-bus.sb-bus-cta`, named "CTA bus
  171, ..."); CTA stops are squares in their own pane under the shuttle stops, from zoom 16 (14 for a focused CTA
  route); CTA lines are about 2/3 of a shuttle line's width, lifted to 3:1 against the land, and drawn under the
  shuttle lines (`core/visibility.js drawOrder`: shuttles first, then CTA, unless the rider's map order or a focus
  says otherwise). A missing bus is held only while other buses of the same feed report.
- Directions (`core/planner.js`): `data.patterns` makes each CTA route one stop sequence per direction (no ride past a
  terminal, no "transfer" between two directions of one route); a scheduled CTA time is a timed wait (`waitTimed`,
  `waitLive:false`, source `schedule`, shown "est."), missed like a live one in refineWalking. Trip following
  (core/tripprogress.js `followState`) uses CTA live data but never a scheduled CTA time.

**Proxy** (`tools/cta-proxy/worker.js`, owner steps in its README.md, tests `tools/test_cta_proxy.py`): a Cloudflare
Worker holding the Bus Tracker key as the secret `CTA_KEY`; `GET /cta/v1/live.json` (one CTA refresh per 25 s for
everyone: 2 getvehicles calls for the 14 routes, getpredictions for the buses within 3 km of Hyde Park) and
`/cta/v1/health` (counts only); GET / OPTIONS only, every other path 404, no query parameter passed on to CTA; CORS for
`https://blobberus.github.io` (both Pages sites) plus `EXTRA_ORIGINS`; a daily call budget; CTA's daily limit reported
as `cta-limit`; the key scrubbed from every message. Privacy: privacy.html "CTA bus data" and About say the proxy gets
the same request from everyone with nothing about the rider and keeps nothing.

**Tests.** core-cta.js (ids, freshness, schedule decoding on service days, drawOrder, the planner with CTA legs,
coverage), data-cta.js (time parsing, the proxy answer, demo buses, the three modes, failure fallback), data-static.js
(the merge), views-cta.js (Routes section, badges, labels, Nearby, My Routes, search, Show running, CTA bulk
buttons), route-cta.js (route page), map-cta.js (map), tools/test_build_cta.py, tools/test_cta_proxy.py.

**iPhone:** paused (docs/redesign/GLASS-IOS-PAUSED.md has the port list). Not in the live app (its plan is the live
repo's `CTA Implementation.md`).

## Schedule by hour on the route page (2026-11-09, ported from the live repo; owner: "Clicking on a particular line and going to the bottom should display it's schedule by hour (i.e.: Every 30 minutes between x times). This time specification should have a disclaimer that the bus schedules don't often follow this schedule.")

The live repo's docs/ARCHITECTURE.md "Schedule by hour on the route page" is the full contract (data, rule, day, view,
tests); web/js/core/schedule.js is the same file in both repos except the CTA "24 hours" label. Here only:
- **CTA routes too.** `tools/build_cta.py` passes its stop order to `build_gtfs.build_service` (route_stops) and prefixes
  the reference stop (`at: "cta:<stop>"`), so web/data/cta/service.json carries `dep` for the Hyde Park part of each route
  (40 KB, 3 KB gzipped; pages.yml rebuilds it daily). The route page shows it like a shuttle's, at a CTA stop, under the
  CTA source line. CTA's noisy timetables are why hourlyHeadways tidies (same-pace neighbours, bursts under 30 min, at
  most 6 lines a stretch): CTA 47 weekdays "About every 20 min, 4:03 to 5:05 AM", "About every 9 min, 5:05 AM to 10:08
  PM", "About every 20 min, 10:08 to 11:11 PM", "About every 25 min, 11:11 PM to 12:21 AM", "Every 22 min, 12:21 to 1:28
  AM". A 24-hour CTA route's service day starts at its quietest minute (build_gtfs service_spans), so its list starts
  there ("About every 25 min, 11:51 PM to 1:29 AM" first).
- Tests: web/tests/route-schedule.js, route-hourly.js (+ every CTA route), data-static.js, tools/test_truth.py,
  tools/test_build_cta.py (cta `at` is a known stop, dep in range). sw `sb-v2-117`. iPhone: paused here
  (docs/redesign/GLASS-IOS-PAUSED.md); the live repo's main has it.
