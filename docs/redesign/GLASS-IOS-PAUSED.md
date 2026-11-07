# iPhone (SwiftUI) glass redesign: PAUSED (2026-11-04)

The owner paused the Swift side of the second redesign (2026-11-04: "cancel the swift model implementation for now.
Write an md file for that to save the progress. Currently, focus on the Apple Maps and redesign on straight bussing
experimental"). The web side continues. This file records exactly where the iPhone work stopped so it can resume
without re-reading everything.

## Where the code is
- Branch **`redesign-ios`** on this repo (github.com/blobberus/straight-bussing-experimental), head **`f7a7b6c`**
  (13 commits on top of main `b3dcfbd`). Nothing of it is on `main`: main's iPhone app is the FIRST redesign
  (DESIGN-SPEC.md), last green CI on main: run 41785185467 (`697b735`).
- Spec it implements: `docs/APPLE-MAPS-STUDY.md`, `docs/DESIGN-SPEC-GLASS.md` (delta on `docs/DESIGN-SPEC.md`;
  SwiftUI APIs per component, `#available(iOS 26, *)` with fallbacks, minimum stays iOS 17).

## Done on the branch (oldest first)
| Commit | What |
|---|---|
| 21e9b99 | iOS notes: what was visually verified on the simulator (first redesign) |
| 35c4384 | Glass tokens and the `sbGlass` helper (DESIGN-SPEC-GLASS 5, 6, 7, 13.1) |
| 0efa5ff | Glass helpers: material fallback with its shadow, fill capsules on glass, zoom sheets |
| eb63e0d | Text on glass: `labelGlass2` for secondary text, no green text, a ringed live dot |
| 8bdfb71 | Sheet: an inset glass card when collapsed, the opaque sheet when expanded |
| baf6c46 | Glass layout: top rows, bottom row with the search circle, lower-right group |
| 1af582e | Directions: the Start / Destination card moves to the top of the sheet |
| 55c61a2 | Settings Done as a checkmark, Lines by Time Cancel as an xmark (iOS 26) |
| 8a13545 | UI tests: the glass layout, and the Directions card under the sheet title |
| 0e1231a | Buttons become capsules: Primary, Secondary and Secondary destructive |
| bfa2cf1 | CI gallery: the collapsed glass card on every kind of page, and the compass |
| 343b490 | Tab bar minimizes to a circle while the expanded content scrolls (spec Q3) |
| f7a7b6c | iOS README: the glass layout and where its helpers and notes live |

## State when paused
- **Builds:** yes (CI "TEST BUILD SUCCEEDED"); the Kit tests (`swift test`) pass.
- **UI tests fail** on the branch (runs 41788885621 on `8a13545` and 41789523050 on `343b490`, each failure seen
  twice, so real, not runner flakes):
  - `SmokeUITests.testMainFlow`: line 52 expects the "My Routes" section but finds "Routes" (the floating tab bar's
    order or selection after the glass layout), and line 116 an `XCTAssertTrue`.
  - `SmokeUITests.testRepeatedRetryDuringATripKeepsTheTrip` (line 211): the Retry button's position moved between
    taps (`XCTAssertEqualWithAccuracy`): the owner's rule "Retry never moves" must hold in the glass banner too.
  - `SmokeUITests.testGlassLayout` (line 259): an element of the glass layout not found within 5 s.
  - `SmokeUITests.testCurrentTripNextBusFirst` (line 308): times out waiting for the next-bus row.
- **Not started:** the bug run on the simulator screenshots (light, dark, larger text) for the glass layout, curated
  screenshots in `docs/redesign/glass/ios/`, notes `docs/redesign/NOTES-glass-ios.md`, the push to main.
- Open owner questions are in DESIGN-SPEC-GLASS (Q1 to Q9; defaults used; Q7, porting the live app's map feedback
  button, on hold).

## Owner request noted while paused: an Apple Maps-like map with green parks (2026-11-04)
Owner: "Change the background map to resemble something closer to apple maps (if this is easy on swift and appstore
then note that)" and "the current map should make green spaces like parks actually green."
- **On iPhone this is easy and App Store safe:** the app's map IS Apple's map (MapKit), so it looks like Apple Maps by
  default. The first redesign deliberately toned it down in `ios/App/Sources/Views/MapScreen.swift`:
  `.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))`. `emphasis: .muted`
  washes out parks and water; `.excludingAll` hides every place icon.
- **Change when iOS resumes (one line):** `.mapStyle(.standard(elevation: .flat, emphasis: .automatic,
  pointsOfInterest: .including([.park, .publicTransport, .university, .hospital])))` (or `.excludingAll` kept if the
  icons crowd the bus markers). Parks then render green, water blue, exactly as in Apple Maps, in light and dark.
- **App Store:** nothing to add: MapKit is free, needs no API key, no attribution work beyond the built-in legal link,
  and it is what App Review expects on iPhone. No tile costs at any scale.
- **Check after the change:** route lines and bus badges must keep their contrast on the more colorful map (the
  first redesign's contrast edges on route lines and badges apply), and the screenshots in light, dark and larger
  text should be re-checked. The web map is being restyled toward Apple Maps at the same time (web/js/map/style.js),
  so the two stay close.

## Owner request noted while paused: faded buses, trip-only lines (2026-11-04)
Owner: "The buses on faded routes should also be faded. If on a trip, only the lines on the particular trip should be
displayed." Same day: "Remove the outlines on each line." / "Make the bus lines slightly thinner from the zoomed out
view to not overclutter the map." and, for this build, "Remove the outlines for the lines but make the lines themselves
thinner. All these changes should go onto the experimental build." Done on the live app (straight-bussing commit
d0e20d0e on branch `fade-buses`, landed on its main in smaller commits; its iOS CI is the reference) and on this repo's web.
Port to this iPhone app when iOS resumes (copy by hand, never merge):
- **Kit** `RouteState.swift` `RouteVisibility`: add `tripRoutes`, `mapHidden`, `busFaded`; `mapFocus` returns nil during
  a trip (`journey.kind == .plan`) unless the route page is open; `mapVisibility().hidden = mapHidden`. Tests: the live
  `VisibilityCustomTests` (`testTripShowsOnlyItsLines`, `testBusFaded`).
- **AppModel** `buildLayers`: draw a focused route even when hidden; dim every line while a plan is drawn (`planDim`,
  from a new `mapPlanRids`: the drawn option's bus-leg routes, [] for the walk-only line, nil when nothing is drawn); no
  chevrons while a plan is drawn. **Remove the casings**: the `-c` casing `MapLine`s (`casingDefault` / `casingContrast`,
  `MapLine.casing`, the skip in `lineHit`) and the bus-leg under-stroke in MapScreen (`Palette.busRing`, `legW + 3`).
  Keep the line tap as wide as before (measure it from the old width plus the old casing).
- **Line widths** (this build, as the web here): `AppModel.lineWidth(zoom)` from z13 2, z14 2.25, z15 3, z16 4, z17 5,
  z18 6 (was the spec 11.3 widths); focused lines keep their +2. (The live app's Kit `RouteLineWidth.scale(zoom:)` only
  thins zoomed out.)
- **MapScreen buses**: draw a hidden route's bus only when its route is in focus; a bus with
  `RouteVisibility.busFaded(rid, focus:, plan: mapPlanRids)` (never the one you ride) gets `BusMarker(faded: true)`:
  scale 0.8, opacity 0.42 (0.3 when stale), not a Button (no tap), drawn before the others so it sits under them.
- The paused glass branch (`redesign-ios`) needs the same when it resumes; the web version on this repo's test site is
  the parity reference.

## Owner requests noted while paused: the web glass build, 2026-11-04 (port when the iPhone work resumes)

- **No current trip selected** (owner: "In the current trip menu, if a current trip is not selected, don't display
  nearby routes, rather, just show that no current trip is selected. Keep the favorites and search station bar. Also
  keep the alerts."): with no trip, Current trip shows the alert row, "No current trip selected" with "Search for a
  destination, choose a route and tap Start." and a Search for a destination button, the station search with its
  links, and the favorites; no nearest stop, no Arriving soon / Also nearby, no "Use my location"; the collapsed card's
  subtitle says "No current trip selected" and its trailing slot is empty. During a trip the next-bus block stays. Web:
  `web/js/ui/views/nearby.js` (`noTripHTML`, `NO_TRIP_TITLE`, `NO_TRIP_HINT`); spec 18 D6. This departs from the
  ship checklist's "next bus in one glance" on purpose (the owner's choice).
- **Trip chip stays visible when the sheet is expanded** (spec 18 D5), like the Settings circle.
- **Only motorways yellow on the map** (spec 18 D4): MapKit already draws main streets neutral.
- **Compact status banner** (spec 18 D2), **feedback circle under Settings** (D1).

## Owner request noted while paused: route search (2026-11-04)
Owner: "You should be able to search routes from the routes menu which will bring them to the top. Allow keywords and
smart search such as allowing 53rdst -> 53rd Street or 53rd St -> 53rd Street etc."
- **Web here: done** (core/routesearch.js + core/text.js, the Routes list's search field, docs/ARCHITECTURE.md "Route
  search"). The live repo (github.com/blobberus/straight-bussing) did web AND iPhone; port its iPhone part by hand
  when iOS resumes (never merge or cherry-pick between the repos):
  - Kit: `ios/StraightBussingKit/Sources/StraightBussingKit/RouteSearch.swift` and
    `ios/StraightBussingKit/Tests/StraightBussingKitTests/RouteSearchTests.swift` (live commit 421eab3c; the test reads
    `web/tests/routesearch-golden.json`, which is already here, so it checks the same cases as the web); add
    `"web/tests/routesearch-golden.json"` to `ios.yml`'s push paths.
  - App (live commit 75e2c823): `AppModel.routeSearchCache` + `AppModel.routeMatches` / `sortedRouteIds`
    (AppModel.swift, AppModel+Actions.swift), `SearchField(clearLabel:)` (PlaceSearchViews.swift), RoutesView
    `searchSection` / `matchSection` / `Groups.without` / `RouteRow(stop:)`, UI test `SmokeUITests.testRouteSearch`.
  - Glass adaptation: the field goes where the glass Routes list puts its first control (under the custom-route bar;
    Edit map order stays in the header), matches as a grouped card under "N routes match", the "Other routes"
    divider, then the usual groups; same words as the web here.
  - Follow-up (owner 2026-11-05: "Searching routes in the routes menu should still show results if they are inactive
    (the top results, unless the name is clearly specified, should priortize active routes--make it clearly show which
    ones are active by graying them out in results)"). Web here: done. iPhone, from the live repo: Kit
    `RouteSearch.rankByActive` + `namedMin` + tests (live commit a4034d1e; the golden file's `active` cases are
    already here), and `AppModel.routeMatches` returning `active` (Set(operatingRoutes()), nil while live status is
    unknown), `RouteRow(idle:)` (`.grayscale(1)` chip, label2 name, "Not running now · ..." from
    `Schedule.restingText`, the hidden line on its own line) in RoutesView (live commit ea5257b8).
- 2026-11-05 web changes to port when iOS resumes (owner): favorite stars yellow instead of brown (map badge `#FFCC00` / `#FFD60A` disc, `#1C1C1E` star, 1 px dark edge on light; `Palette.starBadge` and the Favorite button's filled star, today `#A35400` / `warn`; glass spec D7), and Routes search matches right under the field, above the notices, the operator's alerts and the phone numbers (RoutesView: `matchSection` before the status / alert sections while searching; glass spec D8).

## How to resume
1. `git fetch origin && git checkout -B glass origin/redesign-ios`, then `git rebase origin/main` (the web side keeps
   changing docs and web/; resolve docs conflicts by keeping both).
2. Fix the four UI tests above (app first where the glass layout broke a promise, test where the test assumed the old
   layout); keep every accessibility identifier the tests use and the Retry rule.
3. CI on the branch: `git push origin glass:redesign-ios`, then `gh workflow run ios.yml -R
   blobberus/straight-bussing-experimental --ref redesign-ios`; rerun a run whose jobs never started (busy macOS
   runners). Download the `ios-simulator-preview` artifact of a green run and do the bug run against the spec.
4. Push to main in large green chunks; the web version on the test site is the parity reference.

## CTA routes (web, 2026-11-06): port when iOS resumes
Owner 2026-11-06 (experimental only): "implemenent the CTA routes in the same way passio go shows but make the bus shapes
identifiable to be cta and make their stations square. Also list them noticably idfferently on the routes menu. They
should still behave on the interface like the normal bus routes." Web here: done (docs/ARCHITECTURE.md "CTA routes
beside the shuttles", glass spec D9). The iPhone app has none of it yet. To port:
- Kit: the CTA files in `StaticLoader` (merge `cta:` entries only, `ctaPatterns`), `Agency` (isCta, allBuses, ctaLevel,
  ctaStatusText, ctaSourceText), `CtaSchedule` (decode, servicesOn, scheduledTrips, tripsUnderway; golden cases from
  web/tests/core-cta.js), shuttle-only `Operating.scheduledRoutes` / `scheduledNoLive` / `Coverage`, planner per CTA
  direction with `waitTimed`, `TripFollow` never following a scheduled CTA time.
- App: `CtaLive` (off / live / demo; the same proxy URL, `CTA_LIVE_URL`), squared CTA bus annotation with a "CTA"
  tag, square stop annotations from the zoom the web uses, thinner CTA overlays under the shuttles, the Routes "CTA
  buses" section, the route page per direction, the stop page, "Scheduled, est." rows, CTA contact rows, Settings >
  Credits CTA line, App Privacy: still Data Not Collected (the proxy request carries no user data).

- Dark shuttle colors (web 2026-11-06, owner: "Outline or change coloring of the dark shuttles to make them more noticable"): the live repo's main already has the iPhone side (Kit `RouteColor` + RouteColorTests on `routecolor_golden.json`, `MapLine` / `MapChevron` `darkColor`, `BusMarker`); bring it over with the next iOS merge, CTA overlays in `ctaLineColor` (dark = `RouteColor.liftForDark` against the land only).
- Arrivals name the numbered bus (web 2026-11-06, owner: "state which bus number displayed on the route is about to arrive if there is more than 1 bus"): the live repo's main has the iPhone side (Kit `BusNumbers.arrivalName` / `legName` / `rowExtra`, `TripFollow.Vehicle.number`, `Notify` / `TripInfo` `numbers:`); bring it over with the next iOS merge, CTA buses numbered from their own list as on the web.
