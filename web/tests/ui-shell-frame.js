// Tests for ui/frame.js (desktop phone frame scale) and ui/sheet.js drag math under a scaled frame (SHELL).
import { test, eq, ok, near } from "./lib.js";
import { frameScale, FRAME_W, FRAME_H, FRAME_MEDIA, FRAME_MARGIN, textClass, initTextSize } from "../js/ui/frame.js";
import { createSheet, PANEL_MEDIA } from "../js/ui/sheet.js";

const NEVER = "(min-width: 100000px)";

test("frame: iPhone logical size and media queries", () => {
  eq([FRAME_W, FRAME_H], [393, 852]);
  ok(FRAME_MEDIA.includes("min-width: 521px"), FRAME_MEDIA);
  ok(PANEL_MEDIA.includes("min-width: 768px") && PANEL_MEDIA.includes("max-height"), "panel only on wide + short screens");
});

test("text size: classes by root size (spec 2.2: default under 20 px, large 20 to 27, ax from 28)", () => {
  eq([textClass(17), textClass(19.9), textClass(20), textClass(27.9), textClass(28), textClass(53)], ["default", "default", "large", "large", "ax", "ax"]);
  eq([textClass(NaN), textClass(undefined), textClass("x")], ["default", "default", "default"], "unreadable size: the default layout");
});

test("text size: nothing is read synchronously at boot (no forced style pass; the probe's first observation reads it), a resize reads it", () => {
  const root = document.createElement("div");
  root.style.fontSize = "30px";
  document.body.appendChild(root);
  const stop = initTextSize(root);
  try {
    eq(root.dataset.text, undefined, "nothing read at boot");
    dispatchEvent(new Event("resize"));
    eq(root.dataset.text, "ax", "30 px root: ax");
    root.style.fontSize = "21px";
    dispatchEvent(new Event("resize"));
    eq(root.dataset.text, "large", "21 px root: large");
  } finally { stop(); root.remove(); }
});

test("frame: scale fits the window, never above 1, keeps a margin", () => {
  eq(frameScale(1440, 1200), 1, "tall window: full size");
  near(frameScale(1440, 900), (900 - 2 * FRAME_MARGIN) / FRAME_H, 0.002);
  near(frameScale(1280, 720), (720 - 2 * FRAME_MARGIN) / FRAME_H, 0.002);
  ok(frameScale(600, 600) < 1 && frameScale(600, 600) > 0.5);
  ok(frameScale(10, 10) >= 0.3, "clamped");
});

test("sheet: drag distance is measured in the frame's CSS px when the frame is scaled", async () => {
  const wrap = document.createElement("div");
  wrap.style.cssText = "position:fixed;left:0;top:0;width:400px;height:800px;transform:scale(.5);transform-origin:0 0";
  const sheetEl = document.createElement("section");
  sheetEl.className = "sheet";
  sheetEl.innerHTML = '<header class="sheet-head"><button class="grab" type="button"></button><h1>T</h1></header><div class="sheet-content"></div>';
  wrap.appendChild(sheetEl);
  document.body.appendChild(wrap);
  const head = sheetEl.querySelector("header");
  const sh = createSheet({ sheetEl, headEl: head, contentEl: sheetEl.querySelector(".sheet-content"), initial: "half", panelMedia: NEVER });
  const pe = (type, y) => head.dispatchEvent(new PointerEvent(type, { pointerId: 9, clientY: y, bubbles: true, pointerType: "touch", isPrimary: true }));
  pe("pointerdown", 300);
  pe("pointermove", 290);
  pe("pointermove", 270); // 30 screen px up at scale .5 = 60 CSS px
  const d = parseFloat(sheetEl.style.getPropertyValue("--drag"));
  near(d, -60, 0.5, "--drag in CSS px: " + d);
  pe("pointercancel", 270);
  eq(sh.getDetent(), "peek", "cancel keeps the state ('half' is no resting state any more)");
  sh.destroy();
  wrap.remove();
});
