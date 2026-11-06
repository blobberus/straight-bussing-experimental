/**
 * map/cta.js: how CTA routes look on the map (experimental, owner 2026-11-06: "implemenent the CTA routes in the same way
 * passio go shows but make the bus shapes identifiable to be cta and make their stations square ... They should still
 * behave on the interface like the normal bus routes"). CTA routes are ordinary routes to map/layers.js (ids "cta:<id>",
 * core/agency.js); this file only holds what is drawn differently, never by color alone:
 *  - lines: thinner than the shuttle lines (CTA_LINE_WIDTHS) and, unless the rider's draw order says otherwise, under
 *    them (layers.js stackOrder); in the route color, lifted to 3:1 against the land where it is darker (ctaLineColor:
 *    on the dark map core/routecolor.js liftForDark, the shuttles' function; lineColorFor picks per route);
 *  - stops: squares (squareMarker: a Leaflet CircleMarker that draws a square), in their own pane under the shuttle stops,
 *    shown from CTA_STOP_MIN_Z (they stand on every block, both sides of the street) unless their route is in focus (its
 *    route page): then from zoom 14 like any focused route;
 *  - buses: a squared badge with a "CTA" tag before the route number (markCtaBus) and a name that says CTA (markerName).
 * The pure helpers (squarePath, ctaStopStyle, markerName) do not touch Leaflet.
 */
import { isCta } from '../core/agency.js';
import { safeColor, contrast } from '../core/esc.js';
import { liftForDark, mapColor } from '../core/routecolor.js';
import { PALETTE } from './style.js';

export { isCta };

/** The least contrast a CTA line or stop outline keeps against the map land (WCAG 1.4.11, graphics). */
export const CTA_LINE_MIN_CONTRAST = 3;

/** Mix two '#RRGGBB' colors: k = 0 gives a, 1 gives b. */
function mix(a, b, k) {
  const x = parseInt(a.slice(1), 16), y = parseInt(b.slice(1), 16);
  const ch = (s) => Math.round(((x >> s) & 255) * (1 - k) + ((y >> s) & 255) * k);
  return '#' + ((ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).padStart(6, '0').toUpperCase();
}

/**
 * The color a CTA line and its stop outlines are drawn in, with CTA_LINE_MIN_CONTRAST against the land. Dark map:
 * core/routecolor.js liftForDark (the shuttles' dark-map function, 2026-11-06): the same hue made lighter, against the
 * land only, so CTA lines stay quieter than the shuttles (key-route gray #414145, 1.6:1 on the dark land, -> #6C6C70,
 * still darker than the regular CTA gray #747477). Light map: moved toward black in 5% steps. The badges keep the route
 * color (white text on it is what counts there).
 * @param {string} color route color
 * @param {boolean} dark the dark map
 * @returns {string} '#RRGGBB'
 */
export function ctaLineColor(color, dark) {
  if (dark) return liftForDark(color, PALETTE.dark.bg, CTA_LINE_MIN_CONTRAST);
  const c = safeColor(color), land = PALETTE.light.bg, to = '#000000';
  for (let i = 0; i <= 20; i++) {
    const m = i ? mix(c, to, i / 20) : c;
    if (contrast(m, land) >= CTA_LINE_MIN_CONTRAST) return m;
  }
  return to;
}

/**
 * The color any route's line, stop rings, chevrons and planned legs are drawn in: CTA routes ctaLineColor; shuttles
 * core/routecolor.js mapColor (as published on the light map; on the dark map a color under 3:1 against the land lifted
 * in its own hue to 3:1 against the land and the street fill, owner 2026-11-06: "Outline or change coloring of the dark
 * shuttles to make them more noticable").
 * @param {string} rid route id
 * @param {string} color route color
 * @param {boolean} dark the dark map
 * @returns {string} '#RRGGBB'
 */
export function lineColorFor(rid, color, dark) {
  return isCta(rid) ? ctaLineColor(color, dark) : mapColor(color, dark);
}

/** CTA line width (px) by zoom: about two thirds of a shuttle line (map/layers.js LINE_WIDTHS 2 .. 6). */
export const CTA_LINE_WIDTHS = Object.freeze([[13, 1.25], [14, 1.5], [15, 2], [16, 2.5], [17, 3], [18, 3.5]]);

/** Below this zoom only CTA stops of a route in focus are drawn (shuttle stops show from 14). */
export const CTA_STOP_MIN_Z = 16;

/** The Leaflet pane of CTA stops: above building names (410), under the shuttle stops (420), so a shuttle stop wins a shared corner. */
export const CTA_STOP_PANE = 'sbCtaStops';
export const CTA_STOP_PANE_Z = 415;

/** Corner rounding (px) of a CTA stop square: just enough to soften it, still read as a square. */
const CORNER = 1;

/**
 * CTA stop square by zoom: half the side and the stroke (px). 8 px squares up to zoom 16, 10 px from 17.
 * @param {number} z
 * @returns {{radius:number, weight:number}} radius = half the side (a CircleMarker option)
 */
export function ctaStopStyle(z) {
  return z >= 17 ? { radius: 5, weight: 2 } : { radius: 4, weight: 2 };
}

/**
 * SVG path of a square centered on (x, y), `h` px from the center to each side, corners rounded by `c` px.
 * @param {number} x
 * @param {number} y
 * @param {number} h
 * @param {number} [c]
 * @returns {string}
 */
export function squarePath(x, y, h, c = CORNER) {
  const k = Math.max(0, Math.min(+c || 0, h / 2)), l = x - h, r = x + h, t = y - h, b = y + h;
  if (!k) return `M${l},${t}H${r}V${b}H${l}Z`;
  const a = `A${k},${k} 0 0 1 `;
  return `M${l + k},${t}H${r - k}${a}${r},${t + k}V${b - k}${a}${r - k},${b}H${l + k}${a}${l},${b - k}V${t + k}${a}${l + k},${t}Z`;
}

let Square = null;

/**
 * A square map marker with the CircleMarker API (setStyle, setRadius, pane, events): `radius` = half the side. Drawn as a
 * square by the SVG renderer (the app's); any other renderer falls back to a circle.
 * @param {[number, number]} ll
 * @param {object} opts L.CircleMarker options (+ corner: px)
 * @returns {L.CircleMarker}
 */
export function squareMarker(ll, opts) {
  const L = window.L;
  if (!Square) {
    Square = L.CircleMarker.extend({
      _updatePath() {
        const r = this._renderer;
        if (!r || typeof r._setPath !== 'function' || !this._point) return L.CircleMarker.prototype._updatePath.call(this);
        r._setPath(this, this._empty() ? 'M0 0' : squarePath(this._point.x, this._point.y, this._radius, this.options.corner ?? CORNER));
      },
    });
  }
  return new Square(ll, opts);
}

/**
 * Turn a bus badge (layers.js busIcon root) into a CTA badge: squared corners and a "CTA" tag before the route number,
 * printed in the ring color so it reads on every route color and in both themes. Text, not color: the tag says CTA.
 * @param {HTMLElement} root .sb-bus
 */
export function markCtaBus(root) {
  root.classList.add('sb-bus-cta');
  const tag = document.createElement('span');
  tag.className = 'sb-bus-cta-tag';
  tag.setAttribute('aria-hidden', 'true');   // the marker's own name says CTA
  tag.textContent = 'CTA';
  const tx = root.querySelector('.sb-bus-tx');
  root.insertBefore(tag, tx || null);
}

/**
 * A bus marker's name (title + screen readers). Shuttles: "Bus 2, Central" on a route showing several buses, else
 * "Route CEN bus". CTA: "Bus 2, CTA 55 Garfield", else "CTA bus 171, U. of Chicago/Hyde Park".
 * @param {boolean} cta
 * @param {string} label route badge text (layers.js routeLabel)
 * @param {string} name route long name (or the label)
 * @param {number} [num] bus number (core/busnum.js), 0 = none
 * @returns {string}
 */
export function markerName(cta, label, name, num = 0) {
  if (!cta) return num ? `Bus ${num}, ${name}` : `Route ${label} bus`;
  const long = name && name !== label ? ` ${name}` : '';
  return num ? `Bus ${num}, CTA ${label}${long}` : `CTA bus ${label}${long ? ',' + long : ''}`;
}
