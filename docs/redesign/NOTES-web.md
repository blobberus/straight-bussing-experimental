# Web implementation notes (redesign, 2026-11-03)

How the website (`web/`) implements `docs/DESIGN-SPEC.md`, every place it deviates from the spec and why, what was
measured and what was verified. Kept separate from the spec so the iPhone engineer's edits and these notes never
conflict; the iOS counterpart is `docs/redesign/NOTES-ios.md`. Screens: `docs/redesign/after/web/`.

## Where the spec lives in the web code

| Spec | Web |
|---|---|
| 14 tokens (color light / dark, type roles, spacing, radii, icon sizes, elevation, motion) | `css/tokens.css` under the table's CSS names; old names (`--bg`, `--text`, `--accent`, `--surface`, `--fs-*`, `--d-*`) are aliases at the bottom. `--live` is now the text color and `--live-mark` the dot (the rename the spec warns about). |
| 2.2 root size, Dynamic Type, text-size classes | `css/base.css` (`html { font-size: 106.25% }`; `font: -apple-system-body` on iPhone Safari), `js/ui/frame.js initTextSize` (`html[data-text]` default / large / ax, from a 1rem probe) |
| 5 icons | `js/ui/icons.js` (Lucide, ISC; drawn walk and antenna-off; filled twins for state) |
| 7 materials, 8 elevation | `css/base.css`; the sheet, cards, Settings and dialogs are opaque |
| 10.1 to 10.7 chrome, banner, chip, sheet, bottom bar | `css/base.css`, `css/sheet.css`, `js/ui/pill.js`, `js/ui/contextbar.js`, `js/ui/sheet.js`, `js/main.js` |
| 10.8 to 10.13, 10.18 to 10.21 | `css/components.css`, `js/ui/components.js` |
| 10.14 to 10.17 | `css/views.css`, `css/journey.css`, `css/trip.css`, `views/stop.js`, `views/directions.js`, `views/tripinfo.js`, `views/tripprogress.js` |
| 11 map | `js/map/style.js`, `js/map/layers.js`, `css/map.css`, `js/map/landmarks.js` |

## Deviations from the spec, and why

1. **Words shared with the iPhone app win over the spec's examples** (parity contract 15.1: every word identical). The
   step list keeps the Kit's strings ("Walk 3 min (240 m) to X", "Bus arrives at X 3:11 PM", "Wait ~11 min, then ride
   ~10 min (10 stops) to Y, 3:21 PM · from schedule, est.") instead of 10.16's example actions ("Ride 53RD 10 stops
   to ..."), shown the way iOS StepRow shows them: body text with the place and time Semibold (not all `rowTitle`; the
   steps are long sentences), the live source line under a live bus time, the walk's source as plain detail text
   ("Sidewalk route" / "Walking estimate"). Same as NOTES-ios item 8.
2. **Option card line 4** (10.15) uses the iPhone app's words: "Leave in 10 min, bus 3:11 PM at X" with the live dot
   when the first bus is live, else "Bus about 3:11 PM at X, est." (NOTES-ios item 9).
3. **Missed bus** (13.8, O8 unanswered): the warnBg banner at the top of the next-step card carries the Kit's words,
   "Your planned bus has left. Showing the next one." (NOTES-ios item 6). `tripprogress.js missedNote()` is the one place
   to change when the owner decides.
4. **Trip header expanded** (10.6, O3): collapsed, the header shows the next-step card's own words over "Trip to X" with
   Arriving In; expanded it reads "Current trip" with no trailing value, because the next-step card right under it says
   the same in the hero size (NOTES-ios item 5).
5. **"Options updated with live times."** (13.8) is implemented on the web (a live re-plan that drops the selected
   option says so under the list). The iPhone app does not have it yet (NOTES-ios item 7); a parity gap to close there.
6. **Walk-first card** keeps its Start button on the web (a trip with no bus is a web feature; iOS lacks it, NOTES-ios
   item 10). Its words follow iOS: "8 min walk", "Arrive 3:05 PM", "605 m on sidewalks" / "605 m, walking estimate".
7. **Route header** shows "2 buses", "No live location", "Status unknown" or "Not running" (10.6 plus two honest states,
   NOTES-ios item 13): never "Not running" when we cannot know.
8. **Routes, Edit map order**: in the header's trailing slot as the spec says; while editing, the header shows nothing
   and the editor keeps its own Done button in the list (iOS turns the header action into "Done"). Kept because the
   editor's Done is where the drag-and-arrow work happens; the same action either way.
9. **Routes filter** (Show all / Show running / Hide all): the button matching the current state shows a check and is
   not drawn disabled (10.12), but keeps its `disabled` / `aria-disabled` semantics (a no-op is announced as such).
10. **Trip chip** labels follow iOS TripChip: "Trip to X", "Routes to X" (a station journey), the Lines by Time name, the
    custom route's name; screen readers hear the full sentence ("Only showing routes for Trip to X"). The old scrolling
    marquee is gone (the spec has the label truncate; the marquee clipped its own text, audit defect 2).
11. **Status banner action** (10.3, owner 2026-11-03): Retry or See alert sits in a fixed 84 x 44 slot on the LEADING
    edge, held still 2.5 s after the last Retry tap, "Live data is back." when the feed answers meanwhile (the shared
    rule now written in 10.3). Consequence: with the slot, the feed-error banner can wrap to 3 lines at the default size
    at 393 pt (the spec says at most 2); the safety copy is kept whole rather than shortened.
12. **Paint containment** (7) is on the search bar, the Directions card and the locate button only: the 32 / 36 pt chips
    extend their hit areas to 44 pt outside their box, and `contain: paint` would clip those hit areas.
13. **Landmark sizes** keep the zoom-based sizes (11.5 to 14.5 px for tier 1, as the iPhone app's Kit does) in mapLandmark
    Semibold, rather than a fixed 12 px; the tier-1 list is the owner's curation and was not cut to "about 8" (the
    collision rules decide what fits). The names now also keep clear of the location dot (11.5 hierarchy).
14. **Toast** (10.19) has no icon (the iPhone app shows a bell or a check, NOTES-ios item 16): web toasts are short
    confirmations and errors, and bus alerts on the web are separate notifications or the in-app alert banner.
15. **Bus marker pulse** (old one-shot ring on every poll) is removed: live updates move without decoration (9).
16. **Corner shape**: circular arcs, not continuous squircles (15.2, a platform difference).
17. **Font**: the system stack renders SF Pro on Apple devices; the screenshots in `after/web/` come from Windows
    (Segoe UI Variable), so letterforms differ from an iPhone while spacing, color and hierarchy hold.

## Performance (measured)

Headless Edge 156 with SwiftShader (software GPU), 393 x 852 at DPR 2, demo mode, median of 4 runs per build, the
unchanged build (`base/`, commit 0d1b602) and the redesign served side by side and measured interleaved
(`tmp/redesign-web/trace.py`: a Chrome trace of a scripted sheet drag up and down, and of 5 s idle with buses gliding;
`perf.py`: first paint with 4x CPU throttling). Headless rAF is not vsync-bound, so frame cost is read from the trace.

| Measure | Before | After | Change |
|---|---|---|---|
| Sheet drag: GPU / raster time per frame (SkiaRenderer swap + draw) | 6.43 ms | 4.67 ms | -27% |
| Sheet drag: main-thread BeginMainFrame per frame | 0.45 ms | 0.28 ms | -38% |
| Sheet drag: paint + pre-paint, whole drag | 25.8 ms | 11.1 ms | -57% |
| Idle 5 s, buses gliding: style recalculation | 30.5 ms | 8.3 ms | -73% |
| Idle 5 s: paint + pre-paint | 27.5 ms | 11.5 ms | -58% |
| Idle 5 s: GPU time per frame | 5.91 ms | 5.47 ms | -7% |
| First contentful paint, 4x CPU throttle | 512 ms | 556 ms | +44 ms (within the 2 s budget; inline chrome icons and a larger token file) |

No long tasks in either build. Why: the sheet is opaque (no 24 px blur, saturate 1.8 layer moving under the finger),
blur is limited to four small controls at 20 px / 1.2, the bus pulse animation is gone, and `will-change` is set only
while dragging. Final numbers are re-measured on the shipped build at the end of the run (see the report).

## Verified (headless Edge, `tmp/redesign-web/cdp.py` scenarios, 393 x 852 DPR 2 unless noted)

Light and dark: Current trip collapsed and expanded, search and results, Directions with the place card and options,
selected option with steps, trip in progress (expanded, collapsed with the trip map), route detail, stop detail,
Routes, My Routes, Settings, Lines by Time, Alerts. Light: no location, blocked location, feed unreachable, live data
delayed and out of date, no live locations, loading (450 ms), long names (results, options, stop), beta welcome popup,
Routes to station, About, 320 x 640 phone, 200% text (32 px browser default: Current trip collapsed / expanded,
Directions, route page). The browser suite (748 tests) passes.

## Not verified

Real iPhone Safari (SF Pro rendering, Dynamic Type at AX5 through `-apple-system-body`, safe areas, the sheet's touch
feel, momentum and rubber band), VoiceOver and Increase Contrast on a device, keyboard-up states, the landscape panel,
the missed-bus banner on a live trip (rendered in the unit tests only), Reduce Transparency.
