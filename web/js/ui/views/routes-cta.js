/**
 * @module ui/views/routes-cta
 * The Routes list's CTA part (experimental, owner 2026-11-06: "list them noticably idfferently on the routes menu. They
 * should still behave on the interface like the normal bus routes"): a "CTA buses" section after the shuttle groups,
 * with its own heading, a CTA mark, where its times come from (scheduled, or CTA live data), CTA's square route
 * badges (components.js routeChip), each row with the same eye toggle and route page as a shuttle row; then CTA's own
 * contact and the credit line. Status words for CTA routes (never the shuttle feed's "no live location").
 */
import { esc } from "../../core/esc.js";
import { registerAction } from "../actions.js";
import { showAll, hideAll } from "../../core/custom.js";
import { ctaLevel, ctaSourceText, ctaStatusText, ctaOperating, CTA_URL, CTA_INFO_URL, CTA_PHONE, CTA_TEL, CTA_CREDIT } from "../../core/agency.js";

export { ctaStatusText, ctaOperating };   // their home is core/agency.js

/** CTA's official contact and the credit CTA's terms suggest (under the CTA section and on CTA pages). */
export function ctaContactHTML() {
  return `<p class="v-sec cta-contact">CTA service and alerts: <a href="${CTA_URL}" target="_blank" rel="noopener">transitchicago.com</a>`
    + ` · <a href="${CTA_TEL}">${CTA_PHONE}</a> · <a href="${CTA_INFO_URL}" target="_blank" rel="noopener">customer information</a></p>`
    + `<p class="v-fine cta-credit">${esc(CTA_CREDIT)}. Straight Bussing is unofficial and not affiliated with CTA.</p>`;
}

/**
 * The CTA section: heading with the CTA mark and the time source, then the rows (shown first, hidden after).
 * @param {object} state
 * @param {string[]} ids CTA route ids to list (search matches already taken out)
 * @param {Set<string>} hiddenSet effectiveHidden(state)
 * @param {number} now
 * @param {(state:object, id:string, hidden:boolean, now:number) => string} rowFn the Routes row builder
 * @returns {string}
 */
export function ctaSectionHTML(state, ids, hiddenSet, now, rowFn) {
  if (!ids.length) return "";
  const shown = ids.filter((i) => !hiddenSet.has(i)), hidden = ids.filter((i) => hiddenSet.has(i));
  const src = ctaSourceText(state.cta, now), lvl = ctaLevel(state.cta, now);
  const warn = lvl === "err" || lvl === "late" ? " is-warn" : "";
  // Show all / Hide all for the CTA routes alone (the list's own Show all / Hide all cover every route)
  const bulk = state.journey ? "" : `<span class="rt-ctabulk" role="group" aria-label="All CTA routes">`
    + `<button type="button" class="v-btn v-btn--quiet" data-action="routes:cta-show"${hidden.length ? "" : " disabled"}>Show all<span class="v-sr"> CTA routes</span></button>`
    + `<button type="button" class="v-btn v-btn--quiet" data-action="routes:cta-hide"${shown.length ? "" : " disabled"}>Hide all<span class="v-sr"> CTA routes</span></button></span>`;
  return `<section class="rt-cta" aria-labelledby="rt-cta-h"><div class="rt-ctahead"><span class="rt-ctamark" aria-hidden="true">CTA</span>`
    + `<h3 class="v-h rt-ctah" id="rt-cta-h">CTA buses</h3>${bulk}</div>`
    + `<p class="v-sec rt-ctasrc${warn}" role="status">${esc(src)}</p>`
    + (shown.length ? `<div class="v-list rt-ctalist">${shown.map((i) => rowFn(state, i, false, now)).join("")}</div>` : "")
    + (hidden.length ? `<h4 class="v-sec rt-ctahid">${state.journey ? "Not on this trip" : "Hidden"}</h4><div class="v-list rt-ctalist">${hidden.map((i) => rowFn(state, i, true, now)).join("")}</div>` : "")
    + ctaContactHTML() + "</section>";
}

/** The CTA routes in the list's scope (the station filter's, when one is set). */
function ctaScope(state) {
  const f = state.routeFilter && Array.isArray(state.routeFilter.ids) ? new Set(state.routeFilter.ids.map(String)) : null;
  return Object.keys(state.routes || {}).filter((r) => r.startsWith("cta:") && (!f || f.has(r)));
}
registerAction("routes:cta-show", (ds, ev, ctx) => { const s = ctx.store.get(); ctx.store.set(showAll(s, ctaScope(s))); });
registerAction("routes:cta-hide", (ds, ev, ctx) => { const s = ctx.store.get(); ctx.store.set(hideAll(s, ctaScope(s))); });
