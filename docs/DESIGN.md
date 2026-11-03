# Straight Bussing: design notes for the website

**The source of truth for every visual is [`docs/DESIGN-SPEC.md`](DESIGN-SPEC.md)** (the 2026-11-02 redesign spec shared
by the iPhone app and the website: typography roles, spacing, color tokens for light and dark, icons, radii, materials,
elevation, motion, every component, the map, the journeys, the required states, the token table and the parity
contract). This file keeps only what the spec does not cover: the copy rules, the z-index scale, how the spec maps onto
the web code, and the map style patch. Where the two ever disagree on a visual, the spec wins. Deviations of the web
implementation from the spec, and why, are listed in [`docs/redesign/NOTES-web.md`](redesign/NOTES-web.md); the iPhone
app's in [`docs/redesign/NOTES-ios.md`](redesign/NOTES-ios.md).

History: the v1 / v2 design notes (tokens, a translucent sheet, rounded ETA numerals, three detents) are in git history
(`git show v1-final:docs/DESIGN.md`, and this file before 2026-11-03). The audit that led to the redesign is
[`docs/REDESIGN-AUDIT.md`](REDESIGN-AUDIT.md).

Direction in one line (spec): Google Maps' functional clarity, Apple Maps' restrained native look. The map is the
product; everything else is quiet, consistent and readable at a glance. Unofficial: never UChicago names, logos or maroon
as a brand cue (place names, operator alert text verbatim and 773.702.8181 are content).

## 1. Copy (still in force; spec section 0 points here)

- No em dash or en dash anywhere in visible text: clock ranges read "4:00 PM to 4:29 AM", compact day ranges "Mon-Fri".
- At most one middle dot per line; more parts become a sentence (commas) or separate lines.
- Plain functional sentences; name tabs by their current label ("Current trip").
- One label per intent on a screen (one "use my location" action, not a suggestion plus a button).
- Button labels fit on one line at 393 px; stack buttons instead of wrapping a label.
- Words shared with the iPhone app (the Kit strings: steps, missed bus, Arriving In, status texts) stay identical on both
  platforms (spec 15.1); change them in both or in neither.

## 2. Layers (z-index tokens in `css/tokens.css`, unchanged by the redesign)

| Token | z | Layer |
|---|---|---|
| `--z-map` | 0 | map (Leaflet panes stack inside it) |
| `--z-sheet` | 1000 | bottom sheet |
| `--z-nav` | 1010 | bottom bar |
| `--z-chip` | 1090 | trip / filter chip |
| `--z-float` | 1100 | status banner / chip, locate button |
| `--z-search` | 1105 | floating search bar |
| `--z-overlay-scrim` / `--z-overlay` | 1140 / 1150 | Settings and Lines by Time scrim / card |
| `--z-dialog` | 1200 | `#dlg` scrim + card |
| `--z-toast` | 1300 | toast |
| `--z-frame` | 5000 | desktop phone frame decorations (never take taps) |

A component may use 1 / 2 locally.

## 3. Where the spec lives in the web code

| Spec | Web |
|---|---|
| 14 Token table (colors light / dark, type roles, spacing, radii, icon sizes, elevation, motion) | `css/tokens.css`, CSS names as in the table; old names kept as aliases at the bottom |
| 2.2 Root size and text scaling | `css/base.css` (`html { font-size: 106.25% }`, `-apple-system-body` on iPhone Safari), `js/ui/frame.js` `initTextSize` (`html[data-text]` = default / large / ax) |
| 5 Icons | `js/ui/icons.js` (Lucide, 2 px stroke, drawn walk and antenna-off); `components.js icon()` maps old names |
| 7 Materials | `css/base.css`: translucency only on the search bar, Directions card, locate button, demo chip, trip chip |
| 10.1 to 10.7 Chrome, sheet, bottom bar | `css/base.css`, `css/sheet.css`, `js/ui/sheet.js` (measured collapsed height), `js/ui/pill.js` (banner vs chip), `js/ui/contextbar.js` (trip chip), `js/main.js` (header subtitle and trailing slot) |
| 10.8 to 10.13, 10.18 to 10.21 Rows, cards, badges, ETA, buttons, controls, alert row, toast, empty states | `css/components.css`, `js/ui/components.js` |
| 10.14 to 10.17 Place details, option cards, step list, trip in progress | `css/views.css`, `css/journey.css`, `css/trip.css`; `views/stop.js`, `views/directions.js`, `views/tripinfo.js`, `views/tripprogress.js` |
| 11 Map | `js/map/style.js` (basemap palettes), `js/map/layers.js` (line widths, casing rule, stops, bus markers), `css/map.css` (markers, labels), `js/map/landmarks.js` |
| 13 Required states | the views; `tests/` cover the copy and the order |

Checks that keep it honest: `tests/ui-shell-contrast.js` (every token pair of spec 4.2 in both themes, buttons, tags),
the one-primary-button tests, the 44 pt target tests, and a grep for literal colors outside `tokens.css` (map.css keeps
literal fallbacks only inside `var()` for its own test page).

## 4. Map style patch (`web/js/map/style.js`)

Fetches the OpenFreeMap style (`positron` or `dark`), deep-clones it and patches by layer id (cached per theme; an
empty background-only style in the land color shows until it loads):
- `background`, `water`, `park` / `landuse_park`, `landcover_wood`, `building`: the spec 11.2 palettes (light land
  #F1F2EE, dark #18191C), desaturated parks and water.
- `highway_minor`: wider, round caps, white on light / #33343A on dark; NEW `sb_minor_casing` beneath it.
- `highway_major_casing`, `highway_major_inner`, `highway_path`: recolored and widened; roads on dark stay neutral gray.
- `highway-name-*` (positron) / `highway_name_other` (dark) are replaced by `sb_name_path` (z16), `sb_name_minor` (z14),
  `sb_name_major` (z12.5): no uppercase, majors Noto Sans Bold, #4A4C53 / #2E3036 on light, #C9CAD2 / #E2E3EA on dark,
  a 1.5 px halo in the land color (over 7:1 against it, tested).
- `highway-shield-*`, `road_shield_us`, `road_oneway*`: hidden.
- NEW `sb_housenumber` (z17) and `sb_poi_campus` (z17, college / school / hospital / library / stadium / museum / theatre,
  text only, in the landmark gray, skipping names the curated landmark labels already show).
- Raster fallback (no MapLibre / WebGL): OSM tiles, CSS-inverted in dark.
Zooms in the style are MapLibre zooms, one less than the Leaflet zoom the app uses.
