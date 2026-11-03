/**
 * @module ui/frame
 * Desktop / tablet "iPhone frame" (SHELL). On windows matching FRAME_MEDIA, css/base.css draws the app
 * in a 393 x 852 CSS px phone frame; this module shrinks it uniformly (--frame-k on <html>) when the
 * window is too small to show it whole, so the page never scrolls. Phones (narrow windows) are untouched.
 * The frame keeps its layout size, so Leaflet and the sheet measure 393 x 852 at any scale; pointer
 * math that uses clientX/Y must divide by the scale (ui/sheet.js does).
 */

/** Must match the media query in css/tokens.css and css/base.css. */
export const FRAME_MEDIA = "(min-width: 521px) and (min-height: 560px)";
/** Logical iPhone 15/16 size in CSS px. */
export const FRAME_W = 393, FRAME_H = 852;
/** Space kept around the frame (bezel + breathing room), px. */
export const FRAME_MARGIN = 28;

/**
 * Uniform scale that fits the frame in a window (never above 1).
 * @param {number} winW
 * @param {number} winH
 * @returns {number}
 */
export function frameScale(winW, winH) {
  const k = Math.min(1, (winH - 2 * FRAME_MARGIN) / FRAME_H, (winW - 2 * FRAME_MARGIN) / FRAME_W);
  return Math.max(0.3, Math.round(k * 1000) / 1000);
}

/**
 * Is the phone frame active right now?
 * @returns {boolean}
 */
export function frameActive() {
  try { return typeof matchMedia === "function" && matchMedia(FRAME_MEDIA).matches; } catch (e) { return false; }
}

/**
 * Text-size class for a root font size (docs/DESIGN-SPEC.md 2.2): "default" under 20 px, "large" from 20 to 27 px (iOS
 * xLarge to xxxLarge), "ax" from 28 px (iOS accessibility sizes). Layout switches read html[data-text].
 * @param {number} px computed root font size
 * @returns {'default'|'large'|'ax'}
 */
export function textClass(px) {
  const n = Number(px) || 17;
  return n >= 28 ? "ax" : n >= 20 ? "large" : "default";
}

/**
 * Keep html[data-text] in step with the root font size: on resize, on return to the page (iOS Dynamic Type changes
 * while Safari is in the background) and whenever a 1rem probe changes size (browser text size, zoom). Safe to call once.
 * @param {HTMLElement} [root] default <html>
 * @returns {() => void} stop
 */
export function initTextSize(root = document.documentElement) {
  const apply = () => {
    const c = textClass(parseFloat(getComputedStyle(root).fontSize));
    if (root.dataset.text !== c) root.dataset.text = c;
  };
  apply();
  addEventListener("resize", apply);
  const vis = () => { if (!document.hidden) apply(); };
  document.addEventListener("visibilitychange", vis);
  let ro = null, probe = null;
  if (typeof ResizeObserver === "function" && document.body) {
    probe = document.createElement("span");
    probe.setAttribute("aria-hidden", "true");
    probe.style.cssText = "position:fixed;left:-99px;top:0;width:1rem;height:1px;visibility:hidden;pointer-events:none";
    document.body.appendChild(probe);
    ro = new ResizeObserver(apply);
    ro.observe(probe);
  }
  return () => { removeEventListener("resize", apply); document.removeEventListener("visibilitychange", vis); ro?.disconnect(); probe?.remove(); };
}

/**
 * Keep --frame-k current on resize. Safe to call once at boot.
 * @param {HTMLElement} [root] element that gets the variable (default <html>)
 * @returns {() => void} stop
 */
export function initFrame(root = document.documentElement) {
  const apply = () => {
    if (frameActive()) root.style.setProperty("--frame-k", String(frameScale(innerWidth, innerHeight)));
    else root.style.removeProperty("--frame-k");
    root.classList.toggle("is-framed", frameActive());
  };
  apply();
  addEventListener("resize", apply);
  return () => removeEventListener("resize", apply);
}
