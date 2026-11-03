/**
 * @module ui/pill
 * The floating status chip / banner under the search bar (DESIGN-SPEC 10.3; moved out of main.js 2026-10-10): stale / failed feed and
 * empty-feed states, each with its own icon so the state never rests on color alone (iOS RootView
 * StatusPill): feed error = wifi off, delayed / out of date = clock with an alert mark, no live locations
 * while routes are scheduled = antenna off, no shuttles running = bus. Same words as before (and as the
 * iOS Kit LiveText.pill). Writes the DOM only when the state changes; --pill-h follows its real height.
 * A fresh feed with no bus while a service alert is up also offers "See alert" (action alerts:open): the operator's
 * alert may say why no bus shows, or which number to call (iOS "See alert", 2026-10-11).
 * Demo mode (`?demo=1`, owner decision 2026-10-11: no banner): the pill is the one quiet, honest indicator. It reads
 * "Simulated buses" (flask icon) and the whole pill is a button (action demo:info, ui/demo.js) that explains the
 * demo and offers the way back to live buses. Feed errors and delays still win over it.
 */
import { clock, nowS } from "../core/time.js";
import { staleLevel, activeAlerts } from "../core/arrivals.js";
import { silentService } from "../core/operating.js";
import { DEMO_PILL } from "../core/demo.js";
import { OFFICIAL_PHONE } from "./components.js";
import { PATHS, svg } from "./icons.js";

/** Seconds after boot before "never polled" counts as a feed error. */
export const FIRST_POLL_GRACE_S = 20;
/**
 * After a Retry tap the banner holds still this long (ms), even if the feed comes back at once (owner 2026-11-03: "if the
 * user spams it while on a route, it doesn't shift and accidentally cancel their current trip"): Retry stays under the
 * finger (aria-busy) and nothing else slides into its place; then the banner shows the current state.
 */
export const RETRY_HOLD_MS = 2000;

/** Status icons (ui/icons.js, Lucide + drawn), keyed by pillState().icon: one glyph per state (spec 5). */
export const PILL_ICONS = Object.freeze({
  feed: PATHS["wifi-off"], delay: PATHS["clock-alert"], silent: PATHS["antenna-off"], idle: PATHS["bus-front"], demo: PATHS["flask-conical"],
});
/** The demo chip's tap mark (info): it says the chip can be tapped for more. */
const INFO_SVG = svg("info", 15);

/**
 * What the pill shows (pure).
 * @param {object} s store state
 * @param {number} now unix seconds
 * @param {{bootS?:number, graceS?:number, demo?:boolean}} [o] bootS: app start (before the first poll, an error only
 *   after graceS); demo: the page runs the simulated feed (`?demo=1`)
 * @returns {{kind:''|'err'|'warn'|'info', icon:''|'feed'|'delay'|'silent'|'idle'|'demo', msg:string, retry:boolean, alert:boolean, demo:boolean}}
 *   alert: offer "See alert" (fresh empty feed and at least one active service alert); demo: "Simulated buses", tap to explain
 */
export function pillState(s, now, { bootS = now, graceS = FIRST_POLL_GRACE_S, demo = false } = {}) {
  const polled = s.liveLoaded || s.failed;
  const lvl = polled ? staleLevel(s, now) : now - bootS > graceS ? "err" : "";
  const out = (kind, icon, msg, more) => ({ kind, icon, msg, retry: false, alert: false, demo: false, ...more });
  if (lvl === "err") {
    return out("err", "feed", s.lastOk ? "Can't reach the shuttle feed. Retrying. Showing last known data."
      : `Can't reach the shuttle feed. Don't rely on these times; call ${OFFICIAL_PHONE}.`, { retry: true });
  }
  if (lvl === "old") return out("warn", "delay", `Live data is out of date${s.feedTs ? " (last update " + clock(s.feedTs) + ")" : ""}. Times are approximate.`);
  if (lvl === "late") return out("warn", "delay", "Live data delayed. Times may be off.");
  if (demo) return out("info", "demo", DEMO_PILL, { demo: true });   // simulated feed: always say so (never stored, ?demo=1 only)
  if (s.liveLoaded && !(s.buses || []).length) {   // fresh, empty feed: "no shuttles" only if the schedule agrees
    const alert = activeAlerts(s, now).length > 0;
    return silentService(s, now) ? out("warn", "silent", "No shuttles are reporting live locations", { alert })
      : out("info", "idle", "No shuttles running right now", { alert });
  }
  return out("", "", "");
}

/**
 * Inline SVG for a pill icon ('' for none). Decorative: the text says the same.
 * @param {string} name PILL_ICONS key
 * @returns {string}
 */
export function pillIconSVG(name, size = 17) {
  const key = { feed: "wifi-off", delay: "clock-alert", silent: "antenna-off", idle: "bus-front", demo: "flask-conical" }[name];
  return key ? svg(key, size) : "";
}

/**
 * The banner's words with the first sentence in Semibold (spec 10.3), as DOM nodes (the text is never parsed as HTML).
 * @param {HTMLElement} el
 * @param {string} msg
 */
export function setPillText(el, msg) {
  const m = /^(.+?[.!?])\s+(.+)$/.exec(String(msg || ""));
  const b = document.createElement("b");
  b.textContent = m ? m[1] : String(msg || "");
  if (m) el.replaceChildren(b, document.createTextNode(" " + m[2]));
  else el.replaceChildren(b);
}

/**
 * Pill controller over the #pill element (creates the icon slot, the "See alert" button and the demo tap button when
 * the markup has none). Retry is the first control, on the leading edge, at a fixed spot and width (owner 2026-11-03):
 * the text, the icon and See alert follow it, so a state or text change never moves it, and after a tap the banner holds
 * still for RETRY_HOLD_MS so repeated taps keep landing on Retry (never on a control that slid up from below).
 * @param {{pill:HTMLElement, text:HTMLElement, retry:HTMLElement, app?:HTMLElement|null}} els
 * @param {{bootS?:number, graceS?:number, demo?:boolean}} [o]
 * @returns {{render(s:object, now:number):void}}
 */
export function createPill(els, o = {}) {
  let ic = els.pill.querySelector(".pillicon");
  if (!ic) {
    ic = document.createElement("span");
    ic.className = "pillicon";
    ic.setAttribute("aria-hidden", "true");
    els.pill.prepend(ic);
  }
  if (els.retry && els.retry.parentNode === els.pill && els.pill.firstElementChild !== els.retry) els.pill.prepend(els.retry);   // leading edge
  els.retry?.classList?.add("pillretry");
  let see = els.pill.querySelector('[data-action="alerts:open"]');
  if (!see) {
    see = document.createElement("button");
    Object.assign(see, { type: "button", className: "pillbtn", textContent: "See alert", hidden: true });
    see.dataset.action = "alerts:open";
    see.setAttribute("aria-label", "Read the service alert");
    els.pill.appendChild(see);
  }
  let tap = els.pill.querySelector('[data-action="demo:info"]');
  if (!tap) {
    tap = document.createElement("button");
    Object.assign(tap, { type: "button", className: "pilltap", innerHTML: INFO_SVG, hidden: true });
    tap.dataset.action = "demo:info";
    tap.setAttribute("aria-label", "Simulated buses: what this means, and how to see live buses");
    els.pill.appendChild(tap);
  }
  let sig = "", holdUntil = 0, holdTimer = 0, latest = null;
  const api = {};
  // a Retry tap: hold the banner still (see RETRY_HOLD_MS), then show whatever the feed says by then
  els.retry?.addEventListener?.("click", () => {
    if (els.retry.hidden) return;
    holdUntil = Date.now() + RETRY_HOLD_MS;
    els.retry.setAttribute("aria-busy", "true");
    clearTimeout(holdTimer);
    holdTimer = setTimeout(() => {
      holdUntil = 0;
      els.retry.removeAttribute("aria-busy");
      if (latest) api.render(latest, nowS());
    }, RETRY_HOLD_MS);
  });
  if (els.app && typeof ResizeObserver === "function") {
    // --pill-h on #app = the pill's real height (text can wrap); the full detent and the chip sit below it (sheet.css, base.css)
    new ResizeObserver(() => {
      const v = els.pill.offsetHeight + "px";
      if (v !== "0px" && els.app.style.getPropertyValue("--pill-h") !== v) els.app.style.setProperty("--pill-h", v);
    }).observe(els.pill);
  }
  api.render = (s, now) => {
    latest = s;
    if (Date.now() < holdUntil && !els.retry.hidden) return;   // Retry was just tapped: nothing moves under the finger
    const p = pillState(s, now, o), next = [p.kind, p.icon, p.msg, p.retry, p.alert, p.demo].join("|");
    if (next === sig) return;
    sig = next;
    els.pill.hidden = !p.msg;
    els.pill.className = "statuspill" + (p.kind ? " " + p.kind : "");
    els.pill.dataset.icon = p.icon;
    els.pill.dataset.form = p.demo ? "chip" : "banner";   // spec 10.3: simulated buses = a small chip, every other state = a banner
    ic.innerHTML = pillIconSVG(p.icon, p.demo ? 15 : 17);
    if (p.demo) els.text.textContent = p.msg;
    else setPillText(els.text, p.msg);
    els.retry.hidden = !p.retry;
    see.hidden = !p.alert;
    tap.hidden = !p.demo;
  };
  return api;
}
