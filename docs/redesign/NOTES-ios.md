# iOS implementation notes (redesign, 2026-11-02)

How the iPhone app (`ios/`) implements `docs/DESIGN-SPEC.md`, and every place it deviates from the spec, with the
reason. Kept separate from the spec so the web engineer's edits and these notes never conflict. Screens:
`docs/redesign/after/ios/`.

## Where the spec lives in Swift

| Spec | Swift |
|---|---|
| 4 Color, 14.1 | `ios/Shared/Palette.swift`: every token by its spec name (`bgSheet`, `bgCard`, `fill`, `fillPressed`, `label`, `label2`, `label3`, `labelInverse`, `separator`, `tint`, `tintFill`, `tintBg`, `onFill`, `live`, `liveMark`, `warn`, `warnBg`, `danger`, `dangerBg`, `dangerFill`, `scrim`, `shadow`, `mapLabel`, `badgeRing`); Increase Contrast variants for `label2`, `tint`, `tintFill`, `separator`, `mapLabel`. The old names (`text`, `text2`, `accent`, `card`, `sheet`) are read-only aliases. |
| 2 Typography, 14.2 | `ios/Shared/Typography.swift` `Typo.*`: one Dynamic Type style per role (`sheetTitle` = `.title2.bold()`, `rowTitle` = `.headline`, `rowDetail` = `.subheadline`, `etaRow` = `.title2.weight(.semibold).monospacedDigit()`, ...), fixed sizes only for map labels. |
| 3, 6, 5 sizes, 8, 9 | `ios/Shared/Metrics.swift`: `Space` (s1 to s10 and the layout constants), `Radius` (`tag` 6, `control` 12, `card` 14, `sheet` 20; `busMarker` 7), `IconSize`, `Motion` (`press`, `quick`, `standard`, `exit`, `sheet`, `morph`, `camera`, `reduced`, `pick(_:reduce:)`), `Elevation` + `.elevation(_:in:)` (light shadows, dark 0.5 pt border). |
| 10.11, 10.12 buttons | `ios/App/Sources/Views/Styles.swift`: `PrimaryButtonStyle` (50 full width / 44 inline), `SecondaryButtonStyle` (+ destructive, compact 36 visual / 44 hit), `TextButtonStyle`, `CapsuleButtonStyle` (Routes filter), `RowButtonStyle` (pressed row = `fillPressed`), `EqualWidthHStack` (equal-width button rows that fall back to a stack through `ViewThatFits`), `FlowLayout`, `Sym` (one SF Symbol per meaning, with fallbacks for symbols newer than iOS 17). |
| 10.8 to 10.10, 10.20 | `ios/App/Sources/Views/Components.swift`: `RouteBadge` (24 / 20 pt, contrast-picked text, ring under 3:1), `EtaView` (numeral + inline unit, Now, clock at 60 min, `~` stale, `est.`), `LiveDot`, `SourceLine`, `RowLayout` (40 pt leading slot; stacks at accessibility sizes), `Card`, `RowDivider` (68 pt in), `SectionTitle`, `ListHeader`, `InlineBanner`, `IconCircle`, `SkeletonRows` (row-shaped, pulse off under Reduce Motion), `EmptyStateView` (in a card, help under it). |

## Retry never shifts the screen (owner request 2026-11-03)

"When the connection/bus location is not updated and the error shows up, move the retry button to the left side of the
notification so if the user spams it while on a route, it doesn't shift and accidentally cancel their current trip."

- `StatusBanner` (`RootView.swift`): Retry (and See alert) sit in a fixed slot at the banner's top-leading corner, 84 x
  44 pt (scaled with Dynamic Type only), a `bgCard` capsule with `tint` text. A running Retry poll shows a spinner in
  the same slot; the banner is top-aligned, so a text change (for example "Retrying. Showing last known data.") never
  moves the slot.
- `AppModel.retryFeed()`: one Retry poll at a time; every tap (on Retry or on the held banner) extends the hold.
- Kit `RetryHold` (pure, `RetryHoldTests`): when the feed comes back right after a tap, the banner keeps its height and
  place for 2.5 s after the last tap, drawn as "Live data is back." (new copy, a check mark, `chromeSolid` surface), and
  absorbs taps. Without it, the trip chip (whose Show all calls `endJourney`, which ends the trip) would move up into
  the banner's place under a finger that keeps tapping.
- On the leading side a tap that misses still lands on the trip chip's badges or label (no action), never on its
  trailing Show all; End trip is in the sheet's trip card, on the trailing side and far below the banner.
- UI test `testRepeatedRetryDuringATripKeepsTheTrip`: `-feed flaky` starts a trip with live data, then fails the feed;
  six taps on the same screen point keep the slot in place, the trip running, and the chip in its row.
- The web applies the same rule (spec 10.3 now says leading slot + hold).

## Larger text (spec 13.7), as fixed after the first CI gallery

- The sheet header stacks at accessibility sizes: Back and the title (up to 3 lines) on top, the summary or action
  under it. Before, the trailing summary squeezed the title until words broke in the middle ("Reynol ds Cl...").
- Nothing in a sheet page may ask for more than the screen's width: the J1 text buttons wrap, the option card's total
  and arrival wrap in their stacked layout, the rail pills wrap; and the chrome and the sheet with the bottom bar are
  pinned to the screen's width, so one wide child can never push the gear or My Routes off screen again (AX5 did).
- The place summary shows the full name and address at accessibility sizes (no line limit).
- Rows follow `RowLayout`: the badge above the title and the ETA under the text from AX1.

## Directions on the map

- The selected option's routes take the focused state while Directions is open (wider, casings, chevrons; the rest
  at 0.2 and their stops hidden), like a route page; a started trip already hides the other routes.
- Collapsing the Directions sheet frames the selected option again in the larger visible map (it was framed for the
  strip above the expanded sheet), so the route and its destination pin are not left behind the field card.

## Deviations from the spec, and why

1. **Basemap colors (11.2).** MapKit cannot be recolored; the app uses `.standard(elevation: .flat, emphasis: .muted,
   pointsOfInterest: .excludingAll)` as the spec says. Parity is on the overlays.
2. **Line opacity (11.3).** MapKit draws a polyline's color without its alpha (observed in earlier CI shots), so the
   network state is drawn at full opacity and the unfocused lines of the focused state are the route color mixed 80%
   toward the land color (`Color.mixed(hex:toward:amount:)`), which looks like 0.2 opacity. Casing colors are opaque mixes
   of the spec's rgba values over the land.
3. **Width by zoom (11.3, 11.4).** Line widths and stop sizes follow the zoom in 0.5 steps, set when the camera settles
   (`MapCameraModel.setZoom` from `layoutLabels`), not continuously during a pinch: re-creating the overlays per frame
   would cost the smoothness the brief asks for.
4. **Header hairline (10.6).** Shown when the content scrolls under the header on iOS 18 and later
   (`onScrollGeometryChange`); iOS 17 has no scroll-offset API without per-view geometry readers, so it stays off there.
5. **Current trip header during a trip (10.6, O3).** Collapsed: the current step, "Trip to X" and Arriving In, as
   specified. Expanded: the title "Current trip" without the trailing value, because the next-step card right under it
   shows the same step and the same minutes in the hero size (three copies otherwise).
6. **Missed bus (13.8, O8).** The warnBg note at the top of the next-step card shows the Kit's existing words ("Your
   planned bus has left. Showing the next one."). The proposed wording (O8) is not answered yet and would change a Kit
   string shared with the web; it is one line in `TripText.missedNote` when the owner decides.
7. **"Options updated with live times." (13.8, new).** Not added: the re-plan keeps the selected index, and telling a
   vanished option from a renumbered one needs a Kit change; noted for a later pass.
8. **Step text (10.16).** Step actions are `body` with the stop names and clock times Semibold (the existing bold runs
   of `TripInfo.steps`) rather than all `rowTitle`: the steps are long sentences, and all-Semibold lines lost the
   emphasis on where and when.
9. **Option card line 4 (10.15).** Kit has no such string; the app composes it from Kit values
   (`TripInfo.optionLeaveLine`, in `DirectionsView.swift`): "Leave in 10 min, bus 3:11 PM at Ellis Ave & 57th St" with the
   live dot when the first bus is live, "Bus about 3:11 PM at X, est." when it is scheduled.
10. **Walk-first card (10.15).** Shown as specified, without a Start button: the iPhone Kit follows trips with a bus leg
    only (`TripJourney.plan` returns nil for walk-only options). Starting a walk-only trip is a web feature the iOS port
    does not have yet (a Kit change).
11. **J1 secondary actions.** "Type an address or place" and "Routes to station…" are text buttons in one row (stacked
    when they do not fit) under the station search; full-width secondary buttons would not fit two to a row at 393 pt.
12. **Trip chip (10.5) labels.** A trip reads "Trip to <destination>", a station journey "Routes to <station>", Lines by
    Time its own name, a custom route its name (before: "Only showing routes for: To X"). VoiceOver keeps the full
    sentence ("Only showing routes for ...").
13. **Route header (10.6).** "2 buses" / "Not running" as specified, plus "No live location" for a scheduled route with
    no reporting bus and "Status unknown" in a feed outage: never "Not running" when we cannot know (ship checklist 1).
14. **My Routes "New".** In the sheet header (spec 10.6) once a custom route exists; with none, the empty card's
    "New custom route" is the one primary action.
15. **Settings.** The beta feedback card moved to the top (parity with web Settings, spec 10.11 "Give feedback" as a
    primary). Sections keep the iOS order otherwise; About / Contact support got a "Help" header and My Routes' Service
    alerts / About a "More" header (sentence case, O7). Settings and Lines by Time stay system sheets (Liquid Glass on iOS
    26), with the spec's `bgSheet` / `bgCard` surfaces.
16. **Toast (10.19).** Keeps a 15 pt icon before the text (the bell for bus alerts, a check mark for confirmations): a
    bus alert shown as a toast must not read like a confirmation.
17. **Map stop names.** Only the open stop shows its name on the map (11.4 "Selected stop"); the Routes to station
    candidates get the ring without names (up to 12 names would cover the map).
18. **Bus marker notch.** The notch's distance from the center grows with the marker's estimated width on east / west
    headings, so it never hides under a wide marker ("AP/DX | 2").
19. **Liquid Glass (O2).** Not hand-rolled on the app's own chrome (default "No"); system sheets, alerts, menus and
    the keyboard get it from iOS 26 automatically.
20. **Live Activity / Dynamic Island.** The chip follows the badge spec (Bold system text, contrast-picked color, 6 pt
    radius) and the arrival numerals drop the rounded face; the layout of the Lock Screen card and the islands is
    unchanged (system frames, whole minutes, the same words).
21. **Stop actions (10.14).** Directions / From here / Favorite are sized by their words with the leftover width shared
    (`FillRowLayout`, like the web's `flex: 1 1 auto`), not three equal columns: three columns of the widest label
    ("Favorited" with its star) did not fit at 393 pt. A narrow phone wraps the last one; accessibility sizes stack.
22. **Button rows inside lists.** Edit / Delete, Cancel / Save and the Routes filter are plain equal-split HStacks in
    their list rows (short labels); the measured equal-width layout is kept for ScrollView pages only, where it gave
    list rows an empty band in the first CI gallery.
