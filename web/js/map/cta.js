/**
 * map/cta.js: how CTA routes look on the map (experimental, owner 2026-11-06: "implemenent the CTA routes in the same way
 * passio go shows but make the bus shapes identifiable to be cta and make their stations square ... They should still
 * behave on the interface like the normal bus routes"). CTA routes are ordinary routes to map/layers.js (ids "cta:<id>",
 * core/agency.js); this file only holds what is drawn differently, never by color alone:
 *  - lines: thinner than the shuttle lines (CTA_LINE_WIDTHS) and, unless the rider's draw order says otherwise, under
 *    them (layers.js stackOrder);
 *  - stops: squares (squareMarker: a Leaflet CircleMarker that draws a square), in their own pane under the shuttle stops,
 *    shown from CTA_STOP_MIN_Z (they stand on every block, both sides of the street) unless their route is in focus (its
 *    route page): then from zoom 14 like any focused route;
 *  - buses: a squared badge with a "CTA" tag before the route number (markCtaBus) and a name that says CTA (markerName).
 * The pure helpers (squarePath, ctaStopStyle, markerName) do not touch Leaflet.
 */
import { isCta } from '../core/agency.js';

export { isCta };

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
