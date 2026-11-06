/**
 * @module ui/views/routes-cta
 * The Routes list's CTA part (experimental, owner 2026-11-06: "list them noticably idfferently on the routes menu. They
 * should still behave on the interface like the normal bus routes"): a "CTA buses" section after the shuttle groups,
 * with its own heading, a CTA mark, where its times come from (scheduled, or CTA live data), CTA's square route
 * badges (components.js routeChip), each row with the same eye toggle and route page as a shuttle row; then CTA's own
 * contact and the credit line. Status words for CTA routes (never the shuttle feed's "no live location").
 */
import { esc } from "../../core/esc.js";
import { runningCount } from "../../core/arrivals.js";
import { isScheduledNow, scheduledUntil, clock12 } from "../../core/schedule.js";
import { isCta, ctaLevel, ctaSourceText, CTA_URL, CTA_INFO_URL, CTA_PHONE, CTA_TEL, CTA_CREDIT } from "../../core/agency.js";
import { restingText } from "./myroutes.js";

/**
 * Is a CTA route operating now (the "Show running" rule): a CTA bus reporting on it, or the schedule has it running.
 * @param {object} state
 * @param {string} id
 * @param {number} now
 * @returns {boolean}
 */
export function ctaOperating(state, id, now) {
  return isCta(id) && (runningCount(state, id) > 0 || isScheduledNow(state.service || {}, id, now) === true);
}

/**
 * Status line of a CTA route (plain text): "2 buses live", "1 simulated bus", "Scheduled until 11:40 PM",
 * "Not running now · Scheduled from 5:00 AM today", "No more service today", "Not running today".
 * @param {object} state
 * @param {string} id
 * @param {number} now
 * @returns {string}
 */
export function ctaStatusText(state, id, now) {
  const n = runningCount(state, id), lvl = ctaLevel(state.cta, now);
  if (n) return lvl === "demo" ? `${n} simulated bus${n > 1 ? "es" : ""}` : `${n} bus${n > 1 ? "es" : ""} live`;
  if (isScheduledNow(state.service || {}, id, now) === true) {
    const end = scheduledUntil(state.service || {}, id, now);
    const until = end === "24:00" ? "Scheduled 24 hours" : end ? `Scheduled until ${clock12(end)}` : "Scheduled now";
    return lvl === "" || lvl === "late" ? `${until} · no bus reporting` : until;
  }
  return restingText(state, id, now);
}

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
  return `<section class="rt-cta" aria-labelledby="rt-cta-h"><div class="rt-ctahead"><span class="rt-ctamark" aria-hidden="true">CTA</span>`
    + `<h3 class="v-h rt-ctah" id="rt-cta-h">CTA buses</h3></div>`
    + `<p class="v-sec rt-ctasrc${warn}" role="status">${esc(src)}</p>`
    + (shown.length ? `<div class="v-list rt-ctalist">${shown.map((i) => rowFn(state, i, false, now)).join("")}</div>` : "")
    + (hidden.length ? `<h4 class="v-sec rt-ctahid">${state.journey ? "Not on this trip" : "Hidden"}</h4><div class="v-list rt-ctalist">${hidden.map((i) => rowFn(state, i, true, now)).join("")}</div>` : "")
    + ctaContactHTML() + "</section>";
}
