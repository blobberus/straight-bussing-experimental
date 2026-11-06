#!/usr/bin/env python3
"""CTA bus routes that serve Hyde Park / UChicago -> compact JSON in web/data/cta/ (experimental repo, owner 2026-11-06:
"implemenent the CTA routes in the same way passio go shows but make the bus shapes identifiable to be cta and make
their stations square").

CTA's static GTFS zip (https://www.transitchicago.com/downloads/sch_data/google_transit.zip, about 70 MB) has no CORS
header, so the browser cannot read it; this script turns the part the app needs into small files, the way
tools/build_gtfs.py does for Passio. Only the routes in ROUTES are kept, and of those only the stops, line shapes and
stop times inside BOX (Hyde Park, Kenwood, Woodlawn's north edge and Washington Park: 47th to 63rd Street, King Drive to
the lake). Every route and stop id is namespaced "cta:<id>" so it never mixes with Passio's ids (the live Passio
route_id join stays Passio-only).

Files (all in web/data/cta/):
  routes.json       {"cta:171": {short, long, color, text_color, cta_color, agency:"cta", url, dirs:[...]}}
                    color = CTA's route_color, darkened until white text on it is at least 4.5:1 (AA); cta_color = CTA's own
  stops.json        {"cta:1427": {name: "55th Street & Ellis (EB)", lat, lon, code}}
  shapes.json       {"cta:55": [[[lat, lon], ...], ...]}   clipped to BOX + CLIP_PAD_M, simplified (SIMPLIFY_M)
  route_stops.json  {"cta:55": [direction 0 stops..., direction 1 stops...]}   (the app's one-list-per-route shape)
  patterns.json     {"cta:55": [{"dir": "Eastbound", "stops": [...]}, {"dir": "Westbound", "stops": [...]}]}
  service.json      tools/build_gtfs.py build_service format (hours per weekday, buses per hour, holiday changes) for the
                    times inside BOX
  schedule.json     the stop times inside BOX, compact (see encode_schedule; decoded by web/js/core/ctasched.js)
  meta.json         when, from where, which routes, the box, the credit line CTA's terms suggest

Usage: python tools/build_cta.py [--zip FILE] [--out DIR]. Stdlib only. pages.yml runs it on every deploy and daily,
keeping the committed copy when CTA's server fails. Tests: python tools/test_build_cta.py.
"""
import argparse, csv, io, json, math, sys, urllib.request, zipfile
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_gtfs as BG  # noqa: E402  (shared GTFS helpers: rows, color, hms, build_service)

URL = "https://www.transitchicago.com/downloads/sch_data/google_transit.zip"
OUT = Path(__file__).resolve().parent.parent / "web" / "data" / "cta"
PREFIX = "cta:"
# CTA bus routes with stops in Hyde Park / Kenwood / UChicago (checked against the GTFS stop list 2026-11-06: each has
# stops within 400 m of the campus shuttle stops, except 47, which runs along Kenwood's north edge).
ROUTES = ("171", "172", "2", "4", "X4", "6", "10", "15", "28", "47", "55", "59", "63", "192")
# south, north, west, east: 63rd Street (with a margin for the 63rd / Stony Island terminals) to 47th Street, King Drive
# (Washington Park, Garfield Green Line) to the lake
BOX = (41.7745, 41.8130, -87.6200, -87.5700)
CLIP_PAD_M = 250        # a line runs this far past the box edge, so it does not stop dead at the last stop
SIMPLIFY_M = 4.0        # Douglas-Peucker tolerance for the drawn lines
MIN_PATTERN_TRIPS = 2   # stop patterns with fewer trips add no stops to a direction's list
DIR_WORD = {"North": "Northbound", "South": "Southbound", "East": "Eastbound", "West": "Westbound"}
DIR_ABBR = {"Northbound": "NB", "Southbound": "SB", "Eastbound": "EB", "Westbound": "WB",
            "Northeastbound": "NEB", "Northwestbound": "NWB", "Southeastbound": "SEB", "Southwestbound": "SWB"}
CREDIT = "Data provided by Chicago Transit Authority"


def inside(lat, lon, box=BOX, pad_m=0.0):
    """Is (lat, lon) inside the box, grown by pad_m meters on every side?"""
    dlat = pad_m / 111320.0
    dlon = pad_m / (111320.0 * math.cos(math.radians((box[0] + box[1]) / 2)))
    return box[0] - dlat <= lat <= box[1] + dlat and box[2] - dlon <= lon <= box[3] + dlon


def _rel_lum(hex6):
    def ch(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex6[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    """WCAG contrast ratio of two #RRGGBB colors."""
    la, lb = sorted((_rel_lum(a), _rel_lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def aa_color(hex6, ink="#FFFFFF", target=4.5):
    """Darken #RRGGBB in small steps until `ink` text on it reaches `target` contrast (CTA's local-route gray #99999C
    with white text is 2.8:1). Returns the color unchanged when it already passes."""
    r, g, b = (int(hex6[i:i + 2], 16) for i in (1, 3, 5))
    k = 1.0
    out = hex6.upper()
    while contrast(out, ink) < target and k > 0.05:
        k -= 0.02
        out = "#%02X%02X%02X" % (round(r * k), round(g * k), round(b * k))
    return out


def simplify(pts, tol_m=SIMPLIFY_M):
    """Douglas-Peucker on [[lat, lon], ...] (local meters), endpoints kept."""
    if len(pts) < 3:
        return pts
    k = 111320.0 * math.cos(math.radians(pts[0][0]))
    xy = [((p[1]) * k, p[0] * 111320.0) for p in pts]
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = xy[a]
        bx, by = xy[b]
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy
        best, bi = -1.0, -1
        for i in range(a + 1, b):
            px, py = xy[i]
            if L == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L))
                d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if d > best:
                best, bi = d, i
        if best > tol_m and bi > 0:
            keep[bi] = True
            stack += [(a, bi), (bi, b)]
    return [p for p, kp in zip(pts, keep) if kp]


def clip_line(pts, box=BOX, pad_m=CLIP_PAD_M):
    """The runs of a polyline inside the padded box, each extended by one point past the edge. -> [[...], ...]"""
    runs, cur = [], []
    ins = [inside(la, lo, box, pad_m) for la, lo in pts]
    for i, p in enumerate(pts):
        if ins[i]:
            if not cur and i > 0:
                cur.append(pts[i - 1])
            cur.append(p)
        elif cur:
            cur.append(p)
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    return [r for r in runs if len(r) >= 2]


def merge_patterns(patterns):
    """One stop list per direction from its stop patterns [(tuple, trips)], most trips first: the main pattern, then
    every stop of the other patterns inserted after the stop it follows in that pattern (or before the stop it precedes
    when it comes first). Order of the main pattern is kept."""
    if not patterns:
        return []
    master = list(patterns[0][0])
    for p, n in patterns[1:]:
        if n < MIN_PATTERN_TRIPS:
            continue
        for i, s in enumerate(p):
            if s in master:
                continue
            prev = next((p[j] for j in range(i - 1, -1, -1) if p[j] in master), None)
            nxt = next((p[j] for j in range(i + 1, len(p)) if p[j] in master), None)
            if prev is not None:
                master.insert(master.index(prev) + 1, s)
            elif nxt is not None:
                master.insert(master.index(nxt), s)
            else:
                master.append(s)
    return master


def stop_label(name, desc):
    """'55th Street & Ellis' + 'Eastbound' from stop_desc -> '55th Street & Ellis (EB)' (the shuttle names say (EB) too)."""
    parts = [x.strip() for x in (desc or "").split(",")]
    ab = DIR_ABBR.get(parts[1]) if len(parts) > 1 else None
    return f"{name} ({ab})" if ab else name


def encode_schedule(trips_by_pat, n_stops):
    """One direction's stop times -> {"profiles": [[min offsets or null]...], "trips": {service_id: [start, profile,
    start delta, profile, ...]}}.
    Each trip is (start minute of the service day at its first served stop, [offset minutes per stop or None]); the
    times are rounded to whole minutes first (start = round(t0 / 60), offset = round(t / 60) - start), so decoding gives
    back exactly the rounded times. Profiles are the distinct offset lists; starts are sorted and delta-coded."""
    profiles, index = [], {}
    out = {}
    for svc, lst in sorted(trips_by_pat.items()):
        flat, last = [], 0
        for start, offs in sorted(lst, key=lambda x: (x[0], x[1] and json.dumps(x[1]))):
            key = json.dumps(offs)
            if key not in index:
                index[key] = len(profiles)
                profiles.append(offs)
            flat += [start - last, index[key]]
            last = start
        out[svc] = flat
    assert all(len(p) == n_stops for p in profiles)
    return {"profiles": profiles, "trips": out}


def decode_trips(enc):
    """Inverse of encode_schedule (tests): {service_id: [(start, offsets), ...]} in start order."""
    out = {}
    for svc, flat in enc["trips"].items():
        t, lst = 0, []
        for i in range(0, len(flat), 2):
            t += flat[i]
            lst.append((t, enc["profiles"][flat[i + 1]]))
        out[svc] = lst
    return out


def active_services(z, today):
    """service_id -> {days, start, end, add, drop} for the services still in effect on or after `today`."""
    cal = {}
    for c in BG.rows(z, "calendar.txt"):
        a, b = BG.ymd(c.get("start_date", "")), BG.ymd(c.get("end_date", ""))
        if not a or not b or b < today:
            continue
        cal[c["service_id"]] = {"days": "".join("1" if c.get(col, "0").strip() == "1" else "0" for col in BG.CAL_COLS),
                                "start": a.isoformat(), "end": b.isoformat(), "add": [], "drop": []}
    for r in BG.rows(z, "calendar_dates.txt"):
        d, sid, typ = BG.ymd(r.get("date", "")), r.get("service_id", ""), r.get("exception_type", "").strip()
        if not d or d < today:
            continue
        if sid not in cal and typ == "1":
            cal[sid] = {"days": "0000000", "start": d.isoformat(), "end": d.isoformat(), "add": [], "drop": []}
        if sid in cal:
            (cal[sid]["add"] if typ == "1" else cal[sid]["drop"]).append(d.isoformat())
    for v in cal.values():
        v["add"].sort()
        v["drop"].sort()
        if not v["add"]:
            del v["add"]
        if not v["drop"]:
            del v["drop"]
    return cal


def build(z, today=None, routes=ROUTES, box=BOX):
    """Everything from an open GTFS zip -> {file name: object}."""
    today = today or datetime.now(timezone(timedelta(hours=-6))).date()   # Chicago date, near enough for "still in effect"
    keep = set(routes)
    services = active_services(z, today)

    routes_out = {}
    for r in BG.rows(z, "routes.txt"):
        rid = r.get("route_id", "")
        if rid not in keep:
            continue
        raw = BG.color(r.get("route_color")) or "#565A5C"
        routes_out[PREFIX + rid] = {"short": r.get("route_short_name", "") or rid, "long": (r.get("route_long_name") or "").strip(),
                                    "color": aa_color(raw), "text_color": "#FFFFFF", "cta_color": raw, "agency": "cta",
                                    "url": (r.get("route_url") or f"https://www.transitchicago.com/bus/{rid}/").replace("http://", "https://")}

    trips = {}
    for t in BG.rows(z, "trips.txt"):
        if t.get("route_id") in keep and t.get("service_id") in services:
            trips[t["trip_id"]] = t

    all_stops = {}
    for s in BG.rows(z, "stops.txt"):
        try:
            all_stops[s["stop_id"]] = (float(s["stop_lat"]), float(s["stop_lon"]), s.get("stop_name", ""), s.get("stop_desc", ""))
        except (KeyError, ValueError):
            continue

    times = defaultdict(list)    # trip_id -> [(seq, stop_id, arr_s, dep_s, dist)] inside the box only
    with z.open("stop_times.txt") as f:
        for st in csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig")):
            tid = st["trip_id"]
            if tid not in trips:
                continue
            s = all_stops.get(st["stop_id"])
            if not s or not inside(s[0], s[1], box):
                continue
            a, d = BG.hms(st.get("arrival_time")), BG.hms(st.get("departure_time"))
            a = d if a is None else a
            d = a if d is None else d
            if a is None:
                continue
            times[tid].append((int(st["stop_sequence"]), st["stop_id"], a, d, None))
    for v in times.values():
        v.sort()

    # stop patterns per (route, direction_id)
    pats = defaultdict(Counter)
    dir_name = {}
    for tid, seq in times.items():
        t = trips[tid]
        key = (t["route_id"], t.get("direction_id", "0"))
        pats[key][tuple(x[1] for x in seq)] += 1
        dir_name[key] = DIR_WORD.get(t.get("direction", ""), t.get("direction", "") or ("Direction " + key[1]))
    patterns_out, masters = {}, {}
    for (rid, did), cnt in sorted(pats.items(), key=lambda kv: (kv[0][0], kv[0][1])):
        master = merge_patterns(cnt.most_common())
        if len(master) < 2:
            continue
        masters[(rid, did)] = master
        patterns_out.setdefault(PREFIX + rid, []).append({"dir": dir_name[(rid, did)], "stops": [PREFIX + s for s in master]})
    for rid, lst in patterns_out.items():
        if rid in routes_out:
            routes_out[rid]["dirs"] = [p["dir"] for p in lst]
    routes_out = {k: v for k, v in routes_out.items() if k in patterns_out}

    stops_out = {}
    for master in masters.values():
        for s in master:
            la, lo, name, desc = all_stops[s]
            stops_out[PREFIX + s] = {"name": stop_label(name, desc), "lat": round(la, 5), "lon": round(lo, 5), "code": s}
    route_stops = {rid: [s for p in lst for s in p["stops"]] for rid, lst in patterns_out.items()}

    # schedule: per direction, per service, (start, offsets on the master list)
    sched = {}
    for (rid, did), master in masters.items():
        pos = {s: i for i, s in enumerate(master)}
        by_svc = defaultdict(list)
        for tid, seq in times.items():
            t = trips[tid]
            if t["route_id"] != rid or t.get("direction_id", "0") != did:
                continue
            start = round(seq[0][3] / 60)
            offs = [None] * len(master)
            for _, s, a, d, _ in seq:
                if s in pos and offs[pos[s]] is None:
                    offs[pos[s]] = round((d if s == seq[0][1] else a) / 60) - start
            by_svc[t["service_id"]].append((start, offs))
        enc = encode_schedule(by_svc, len(master))
        sched.setdefault(PREFIX + rid, []).append({"dir": dir_name[(rid, did)], **enc})

    # line shapes: per direction the most used shape, plus a second one when it covers stops the first does not reach
    pts = defaultdict(list)
    shape_ids = {t.get("shape_id") for tid, t in trips.items() if tid in times and t.get("shape_id")}
    for s in BG.rows(z, "shapes.txt"):
        if s["shape_id"] in shape_ids:
            pts[s["shape_id"]].append((int(s["shape_pt_sequence"]), float(s["shape_pt_lat"]), float(s["shape_pt_lon"])))
    lines = {k: [[a, b] for _, a, b in sorted(v)] for k, v in pts.items()}
    usage = defaultdict(Counter)
    for tid, t in trips.items():
        if tid in times and t.get("shape_id"):
            usage[(t["route_id"], t.get("direction_id", "0"))][t["shape_id"]] += 1
    shapes_out = {}
    for (rid, did), cnt in sorted(usage.items()):
        kept = 0
        for sid, n in cnt.most_common(2):
            if kept and n < MIN_PATTERN_TRIPS * 5:
                break
            for run in clip_line(lines.get(sid, []), box):
                run = [[round(a, 5), round(b, 5)] for a, b in simplify(run)]
                if run not in shapes_out.setdefault(PREFIX + rid, []):
                    shapes_out[PREFIX + rid].append(run)
            kept += 1

    # hours (build_gtfs format) from the times inside the box
    svc_trips = [{"trip_id": tid, "route_id": PREFIX + t["route_id"], "service_id": t["service_id"]}
                 for tid, t in trips.items() if tid in times]
    service = BG.build_service(z, svc_trips, times, (), today=today)
    service["routes"] = {k: v for k, v in service["routes"].items() if k in routes_out}

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    used = {svc for dirs in sched.values() for d in dirs for svc in d["trips"]}
    services = {k: v for k, v in services.items() if k in used}
    schedule = {"v": 1, "generated": generated, "tz": "America/Chicago", "services": services, "routes": sched}
    meta = {"generated_utc": generated, "source": URL, "routes": sorted(routes_out, key=lambda r: (len(r), r)),
            "box": list(box), "credit": CREDIT, "terms": "https://www.transitchicago.com/developers/terms/"}
    return {"routes.json": routes_out, "stops.json": stops_out, "shapes.json": shapes_out, "route_stops.json": route_stops,
            "patterns.json": patterns_out, "service.json": service, "schedule.json": schedule, "meta.json": meta}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--zip", help="a local google_transit.zip instead of downloading CTA's")
    ap.add_argument("--out", help="write here instead of web/data/cta")
    a = ap.parse_args(argv)
    out = Path(a.out) if a.out else OUT
    if a.zip:
        data = Path(a.zip).read_bytes()
    else:
        req = urllib.request.Request(URL, headers={"User-Agent": "straight-bussing/1.0 (+https://github.com/blobberus/straight-bussing-experimental)"})
        data = urllib.request.urlopen(req, timeout=180).read()
    files = build(zipfile.ZipFile(io.BytesIO(data)))
    if len(files["routes.json"]) < len(ROUTES) // 2:
        raise SystemExit(f"only {len(files['routes.json'])} of {len(ROUTES)} routes found: not writing (feed changed?)")
    out.mkdir(parents=True, exist_ok=True)
    for name, obj in files.items():
        (out / name).write_text(json.dumps(obj, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
        print(f"{name:18} {(out / name).stat().st_size:>8} bytes")
    print("routes:", " ".join(r[len(PREFIX):] for r in files["meta.json"]["routes"]))


if __name__ == "__main__":
    main()
