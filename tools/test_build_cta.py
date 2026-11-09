#!/usr/bin/env python3
"""Tests for tools/build_cta.py (CTA routes in Hyde Park, experimental, owner 2026-11-06). Stdlib only:
python tools/test_build_cta.py   (a small made-up GTFS zip; no network)"""
import io, json, sys, zipfile
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_cta as B  # noqa: E402

TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


def csv_text(head, rows):
    return "\n".join([",".join(head)] + [",".join(str(x) for x in r) for r in rows]) + "\n"


# Two stops inside the box on 55th Street, one far west outside it (Midway), one on Stony Island inside
STOPS = [("1", "1", "55th Street & Ellis", "55th Street & Ellis, Eastbound, Southside of the Street", 41.7950, -87.6010),
         ("2", "2", "55th Street & University", "55th Street & University, Eastbound, Southside", 41.7951, -87.5980),
         ("3", "3", "Midway Airport", "Midway Airport, Bus Terminal", 41.7870, -87.7380),
         ("4", "4", "55th Street & University", "55th Street & University, Westbound, Northside", 41.7953, -87.5981),
         ("5", "5", "55th Street & Ellis", "55th Street & Ellis, Westbound, Northside", 41.7952, -87.6011),
         ("6", "6", "Museum of Science & Industry", "Museum of Science & Industry, Bus Turnaround", 41.7906, -87.5830),
         ("9", "9", "Downtown", "Downtown", 41.8800, -87.6300)]


def make_zip():
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z:
        z.writestr("routes.txt", csv_text(["route_id", "route_short_name", "route_long_name", "route_type", "route_url", "route_color", "route_text_color"],
                                          [("55", "55", "Garfield", 3, "http://www.transitchicago.com/bus/55/", "414145", "ffffff"),
                                           ("171", "171", "U. of Chicago/Hyde Park", 3, "", "99999C", "ffffff"),
                                           ("8", "8", "Halsted", 3, "", "99999C", "ffffff")]))
        z.writestr("stops.txt", csv_text(["stop_id", "stop_code", "stop_name", "stop_desc", "stop_lat", "stop_lon"],
                                         [(a, b2, n, '"' + d + '"', la, lo) for a, b2, n, d, la, lo in STOPS]))
        z.writestr("calendar.txt", csv_text(["service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "start_date", "end_date"],
                                            [("WK", 1, 1, 1, 1, 1, 0, 0, "20261101", "20261130"),
                                             ("OLD", 1, 1, 1, 1, 1, 0, 0, "20260901", "20260919"),
                                             ("SA", 0, 0, 0, 0, 0, 1, 0, "20261101", "20261130")]))
        z.writestr("calendar_dates.txt", csv_text(["service_id", "date", "exception_type"], [("WK", "20261126", 2)]))
        z.writestr("trips.txt", csv_text(["route_id", "service_id", "trip_id", "direction_id", "shape_id", "direction"],
                                         [("55", "WK", "E1", 1, "SE", "East"), ("55", "WK", "E2", 1, "SE", "East"),
                                          ("55", "WK", "W1", 0, "SW", "West"), ("55", "OLD", "X1", 1, "SE", "East"),
                                          ("55", "SA", "S1", 1, "SE", "East"), ("8", "WK", "H1", 0, "SH", "North")]))
        st = [("E1", "08:00:00", "3", 1), ("E1", "08:30:10", "1", 2), ("E1", "08:32:40", "2", 3), ("E1", "08:40:00", "6", 4),
              ("E2", "09:00:00", "3", 1), ("E2", "09:31:00", "1", 2), ("E2", "09:33:00", "2", 3), ("E2", "09:41:00", "6", 4),
              ("W1", "10:00:00", "6", 1), ("W1", "10:07:00", "4", 2), ("W1", "10:09:00", "5", 3), ("W1", "10:40:00", "3", 4),
              ("X1", "07:00:00", "1", 1), ("X1", "07:05:00", "2", 2),
              ("S1", "25:10:00", "1", 1), ("S1", "25:12:00", "2", 2),
              ("H1", "08:00:00", "9", 1), ("H1", "08:10:00", "1", 2)]
        z.writestr("stop_times.txt", csv_text(["trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"],
                                              [(t, a, a, s, q) for t, a, s, q in st]))
        shp = [("SE", 41.7870, -87.7380, 1), ("SE", 41.7950, -87.6200, 2), ("SE", 41.7950, -87.6010, 3), ("SE", 41.7951, -87.5980, 4),
               ("SE", 41.7906, -87.5830, 5), ("SW", 41.7906, -87.5830, 1), ("SW", 41.7953, -87.5981, 2), ("SW", 41.7952, -87.6011, 3),
               ("SW", 41.7870, -87.7380, 4), ("SH", 41.88, -87.63, 1), ("SH", 41.795, -87.601, 2)]
        z.writestr("shapes.txt", csv_text(["shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence"], shp))
    b.seek(0)
    return zipfile.ZipFile(b)


FILES = B.build(make_zip(), today=date(2026, 11, 6), routes=("55", "171"))


@test
def route_and_stop_ids_are_namespaced():
    assert set(FILES["routes.json"]) == {"cta:55"}, FILES["routes.json"]   # 171 has no trips: left out; 8 not asked for
    assert all(k.startswith("cta:") for k in FILES["stops.json"])
    assert all(s.startswith("cta:") for lst in FILES["route_stops.json"].values() for s in lst)
    assert all(k.startswith("cta:") for k in FILES["service.json"]["routes"])


@test
def only_stops_inside_the_box_are_kept():
    assert set(FILES["stops.json"]) == {"cta:1", "cta:2", "cta:4", "cta:5", "cta:6"}, FILES["stops.json"]   # not Midway (3)


@test
def stop_names_carry_the_direction_like_the_shuttle_names():
    assert FILES["stops.json"]["cta:1"]["name"] == "55th Street & Ellis (EB)"
    assert FILES["stops.json"]["cta:4"]["name"] == "55th Street & University (WB)"
    assert FILES["stops.json"]["cta:6"]["name"] == "Museum of Science & Industry"
    assert FILES["stops.json"]["cta:1"]["code"] == "1"


@test
def patterns_have_one_list_per_direction_and_route_stops_joins_them():
    p = FILES["patterns.json"]["cta:55"]
    assert [x["dir"] for x in p] == ["Westbound", "Eastbound"], p
    assert p[1]["stops"] == ["cta:1", "cta:2", "cta:6"], p
    assert FILES["route_stops.json"]["cta:55"] == p[0]["stops"] + p[1]["stops"]
    assert FILES["routes.json"]["cta:55"]["dirs"] == ["Westbound", "Eastbound"]


@test
def expired_services_are_dropped_and_holidays_listed():
    s = FILES["schedule.json"]["services"]
    assert "OLD" not in s and s["WK"]["days"] == "1111100" and s["WK"]["drop"] == ["2026-11-26"], s
    assert set(s) == {"WK", "SA"}


@test
def schedule_decodes_to_the_rounded_stop_times():
    east = FILES["schedule.json"]["routes"]["cta:55"][1]
    trips = B.decode_trips(east)
    # E1 departs Ellis 08:30:10 -> 510 min; University 08:32:40 -> 513 (rounded); MSI 08:40 -> 520
    assert trips["WK"][0] == (510, [0, 3, 10]), trips["WK"]
    assert trips["WK"][1] == (571, [0, 2, 10]), trips["WK"]
    assert trips["SA"] == [(1510, [0, 2, None])], trips["SA"]   # after midnight stays > 24 h on the service day


@test
def colors_pass_aa_with_white_text():
    r = FILES["routes.json"]["cta:55"]
    assert r["cta_color"] == "#414145" and r["color"] == "#414145"
    assert B.contrast(B.aa_color("#99999C"), "#FFFFFF") >= 4.5
    assert B.aa_color("#B71234") == "#B71234"
    assert r["url"].startswith("https://") and r["agency"] == "cta"


@test
def lines_are_clipped_near_the_box():
    lines = FILES["shapes.json"]["cta:55"]
    for line in lines:
        for la, lo in line[1:-1]:
            assert B.inside(la, lo, B.BOX, B.CLIP_PAD_M), (la, lo)
    assert all(len(line) >= 2 for line in lines)


@test
def service_hours_use_the_times_inside_the_box():
    days = FILES["service.json"]["routes"]["cta:55"]["days"]
    assert days["mon"]["first"] == "08:30" and days["mon"]["last"] == "10:09", days   # Ellis 08:30, not Midway 08:00
    assert days["sat"]["first"] == "01:10" and days["sat"]["buses"][1] == 1, days    # the 25:10 trip folds onto the clock
    assert days["sun"] is None


@test
def a_day_of_23_hours_or_more_is_written_as_24_hours():
    d = {"first": "01:14", "last": "25:06", "spans": [["01:14", "25:06"]]}
    assert B.all_day(d) == {"first": "00:00", "last": "24:00", "spans": [["00:00", "24:00"]]}, d
    night = {"first": "16:00", "last": "28:29", "spans": [["16:00", "28:29"]]}
    assert B.all_day(dict(night)) == night
    assert B.all_day(None) is None


@test
def despike_drops_the_curb_jogs_at_stops():
    a, b, c, d = [41.795, -87.600], [41.79509, -87.600], [41.795, -87.599], [41.795, -87.598]   # b: 10 m north and back
    assert B.despike([a, b, a, c, d]) == [a, c, d], B.despike([a, b, a, c, d])
    assert B.despike([a, a, c, d]) == [a, c, d], "repeated points dropped"
    corner = [[41.795, -87.600], [41.796, -87.600], [41.796, -87.599]]   # a real 90 degree corner stays
    assert B.despike(corner) == corner


@test
def committed_lines_have_no_spikes():
    out = B.OUT / "shapes.json"
    if not out.exists():
        return
    for rid, lines in json.loads(out.read_text(encoding="utf-8")).items():
        for line in lines:
            assert B.despike(line) == line, rid


@test
def merge_patterns_inserts_extra_stops_in_order():
    m = B.merge_patterns([(("a", "b", "d"), 10), (("a", "b", "c", "d"), 3), (("z", "a"), 2), (("q",), 1)])
    assert m == ["z", "a", "b", "c", "d"], m


@test
def the_committed_build_is_sane():
    out = B.OUT
    if not (out / "routes.json").exists():
        return
    routes = json.loads((out / "routes.json").read_text(encoding="utf-8"))
    stops = json.loads((out / "stops.json").read_text(encoding="utf-8"))
    pats = json.loads((out / "patterns.json").read_text(encoding="utf-8"))
    assert len(routes) >= 10 and all(k.startswith("cta:") for k in routes)
    for rid, lst in pats.items():
        assert rid in routes
        for p in lst:
            assert all(s in stops for s in p["stops"]), rid
    total = sum(f.stat().st_size for f in out.glob("*.json"))
    assert total < 400_000, total
    svc = json.loads((out / "service.json").read_text(encoding="utf-8"))
    for rid, r in svc["routes"].items():   # Schedule by hour: departures timed at a CTA stop the app knows
        if "at" in r:
            assert r["at"].startswith("cta:") and r["at"] in stops, (rid, r["at"])
        for d in r["days"].values():
            if d and d.get("dep"):
                assert d["dep"][0] < 1440 and all(isinstance(x, int) and 0 <= x <= 2880 for x in d["dep"]), rid


def main():
    bad = 0
    for fn in TESTS:
        try:
            fn()
            print("ok  ", fn.__name__)
        except Exception as e:  # noqa: BLE001
            bad += 1
            print("FAIL", fn.__name__, repr(e))
    print(f"{len(TESTS) - bad}/{len(TESTS)} passed")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
