import SwiftUI
import StraightBussingKit

/// Route detail (ui/views/route.js): status + today's hours (calendar exceptions named), where each bus is in
/// words, the stop timeline in travel order with the next ETA per stop, "Bus N heading here" pills, direction
/// chevrons and the buses on the rail, the loop note, then "Hours & service" from the official schedule (week,
/// schedule changes incl. this route's service alerts, scheduled buses by hour). While the route is closed (Kit
/// `RouteText.closed`: no bus running and not scheduled now) "Hours & service" comes before the stops (owner 2026-10-27,
/// web route.js routeClosed) and before the no-bus help numbers (owner 2026-10-29); open routes keep the help first.
/// Two or more buses are "Bus 1", "Bus 2" (Kit `BusNumbers`, owner 2026-10-30, web core/busnum.js): tapping a bus (here
/// or on the map) picks it and each station shows that bus's own time ("Showing Bus 2's times", "Show the next bus at each stop" or
/// tapping its row again clears it; leaving the page or the map no longer drawing the bus too).
struct RouteDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let rid: String
    /// Stop row height on the rail: 48 pt at the default text size, more with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowH: CGFloat = 48

    var body: some View {
        if let r = model.route(rid) {
            content(r)
        } else {
            VStack(spacing: Space.s3) {
                EmptyStateView(title: "Route not found", message: "This route is not in the current schedule.", icon: "mappin.slash")
                Button { model.popToRoot(); model.select(.routes) } label: { Text("See all routes") }
                    .secondaryButtonStyle(full: true)
            }
            .padding(Space.insetContent)
        }
    }

    func content(_ r: Route) -> some View {
        let n = model.running(rid)
        let svc = model.staticData.service
        // scheduled but no bus reporting: "Scheduled until 4:29 AM, no live location", never "Not running" (rider safety)
        let quiet: String? = n == 0 && !model.liveOutage ? Operating.noLiveStatus(rid, buses: model.buses, service: svc, now: model.now) : nil
        let status: String = n > 0 ? "\(n) bus\(n == 1 ? "" : "es") running"
            : model.liveOutage ? "Live status unavailable" : quiet ?? "Not running right now"
        let ids = RouteText.stopOrder(model.staticData.routeStops[rid])
        let list = model.staticData.routeStops[rid] ?? []
        let loop = list.count > 2 && list.first == list.last
        let nums = model.busNumbers[rid] ?? [:]
        let spots = model.liveLoaded ? RouteText.busPositions(model.staticData, buses: model.buses, rid: rid, now: model.now, numbers: nums) : []
        // the picked bus while the map still draws it (a bus missing from one poll stays 45 s): its key and name
        let drawnPick = model.selectedBus.flatMap { s in s.rid == rid ? model.mapBuses.first { $0.rid == rid && $0.id == s.vehicleId } : nil }
        let sel: (vid: String, name: String)? = drawnPick.map { ($0.id, BusNumbers.name(number: nums[$0.id], label: $0.label)) }
        let closed = RouteText.closed(running: n, service: svc, rid: rid, now: model.now)
        let schedule = RouteScheduleView(rid: rid, day: Self.localDay(model.now), t: model.now, alertIds: routeAlerts.map(\.id),
                                         version: model.staticVersion).equatable()
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(alignment: .center, spacing: Space.s2) {
                        RouteBadge(route: r, rid: rid)
                        if n > 0 { LiveDot() }
                        Text(status).font(Typo.rowTitle).foregroundStyle(n > 0 ? Palette.live : Palette.label)
                    }
                    .accessibilityElement(children: .combine)
                    // the service day, not the calendar date: at 12:10 AM a route running until 12:25 AM shows
                    // "Friday service ... · Scheduled now", never "Today No service · Scheduled now"
                    if let sh = Schedule.serviceHoursAt(svc, rid, model.now) {
                        let h = sh.hours
                        let on = Schedule.isScheduledNow(svc, rid, model.now) ?? false
                        let head = sh.yesterday ? "\(Schedule.dayName[sh.dayKey] ?? "Yesterday") service " : "Today "
                        (Text(head).fontWeight(.semibold) + Text(h.label + RouteText.exceptionNote(h)) + Text(on ? " \u{00B7} Scheduled now" : " \u{00B7} Not scheduled now"))
                            .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if quiet != nil {
                        Text("No bus on this route is sending its location, so we can't confirm it's running. Call 773.702.8181 before you rely on it.")
                            .font(Typo.footnote).foregroundStyle(Palette.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Space.s1)
                if model.hidden.contains(rid) {
                    if model.routeState.journey != nil {
                        InlineBanner(kind: .info, icon: "eye.slash", text: "This route is not part of the current journey, so it is hidden on the map.")
                    } else {
                        Card {
                            RowLayout {
                                Image(systemName: "eye.slash").font(.system(size: IconSize.row)).foregroundStyle(Palette.label2)
                                    .accessibilityHidden(true)
                            } content: {
                                Text("This route is hidden from the map and arrival times.").font(Typo.rowDetail).foregroundStyle(Palette.label)
                                    .fixedSize(horizontal: false, vertical: true)
                            } trailing: {
                                Button("Show") { model.toggleRouteHidden(rid) }.secondaryButtonStyle(compact: true).fixedSize()
                            }
                        }
                    }
                }
                // closed: the hours and buses by hour first, then the help numbers, then the stops (owner 2026-10-29)
                if closed { schedule }
                if n == 0 && model.liveLoaded && model.buses.isEmpty {
                    // this route's own alerts are under Schedule changes; the operator's number, if given, is the primary call
                    NoBusHelp(untiedOnly: true)
                }
                if ids.isEmpty {
                    EmptyStateView(title: "No stops listed", message: "The schedule has no stops for this route.", icon: "mappin.slash")
                } else {
                    if !spots.isEmpty {
                        SectionTitle(text: "Where the buses are")
                        // each row picks its bus (its own time at each station); again = unpick
                        Card {
                            ForEach(Array(spots.enumerated()), id: \.offset) { item in
                                let b = item.element, on = b.key != nil && b.key == sel?.vid
                                if item.offset > 0 { RowDivider() }
                                Button {
                                    model.selectedBus = on ? nil : b.key.map { SelectedBus(rid: rid, vehicleId: $0) }
                                } label: {
                                    RowLayout {
                                        Image(systemName: on ? "checkmark.circle.fill" : "bus.fill").font(.system(size: IconSize.status))
                                            .foregroundStyle(on ? Palette.tint : Palette.label2).accessibilityHidden(true)
                                    } content: {
                                        Text(b.text).font(on ? Typo.rowTitle : Typo.body)
                                            .foregroundStyle(b.stale ? Palette.warn : Palette.label)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if on { Text("Showing its times").font(Typo.rowDetail).foregroundStyle(Palette.label2) }
                                    } trailing: { EmptyView() }
                                }
                                .buttonStyle(RowButtonStyle())
                                .accessibilityLabel("\(b.text). \(on ? "Showing its times" : "Show its times")")
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    if let sel {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: Space.s4) { pickedLine(sel.name) }
                            VStack(alignment: .leading, spacing: 0) { pickedLine(sel.name) }
                        }
                        .padding(.leading, Space.insetContent)
                        .accessibilityElement(children: .contain)
                    }
                    SectionTitle(text: "Stops")
                    Card { stopTimeline(ids: ids, loop: loop, spots: spots, color: Color(hex: r.color), route: r, pick: sel) }
                    VStack(alignment: .leading, spacing: Space.s1) {
                        if loop, let first = ids.first {
                            Label("Loop: continues to \(model.staticData.stops[first]?.name ?? first)", systemImage: "arrow.triangle.2.circlepath")
                                .font(Typo.footnote).foregroundStyle(Palette.label2)
                        }
                        if model.liveLoaded {
                            Text(model.isStale ? "Live data delayed. Times and bus positions may be off." : "Times are live predictions. Bus positions are approximate.")
                                .font(Typo.footnote).foregroundStyle(Palette.label2)
                        }
                    }
                    .padding(.horizontal, Space.insetContent)
                }
                if !closed { schedule }
            }
            .padding(.horizontal, Space.insetContent)
            .padding(.top, Space.s1)
            .padding(.bottom, Space.s6)
        }
        .reportsSheetScroll()
        // the pick lasts while the page is open and the map still draws the bus
        .onChange(of: drawnPick?.id) { _, v in if v == nil, model.selectedBus?.rid == rid { model.selectedBus = nil } }
        .onDisappear { if model.selectedBus?.rid == rid { model.selectedBus = nil } }
    }

    /// "Showing Bus 2's times" and the way back to the next bus at each stop (web route.js wording).
    @ViewBuilder func pickedLine(_ name: String) -> some View {
        Text("Showing \(name)'s times").font(Typo.rowDetail.weight(.semibold)).foregroundStyle(Palette.label)
        Button("Show the next bus at each stop") { model.selectedBus = nil }
            .textButtonStyle(font: Typo.rowDetail.weight(.semibold))
    }

    /// This route's alerts, also those naming it by Passio's own id (`Arrivals.alertRouteIds`, DC-009).
    var routeAlerts: [ServiceAlert] {
        model.activeAlerts.filter { Arrivals.alertRouteIds($0, routes: model.staticData.routes).contains(rid) }
    }

    /// `pick`: the picked bus (key + name); each station then shows only its own time (`BusNumbers.busArrival`).
    func stopTimeline(ids: [String], loop: Bool, spots: [RouteText.BusSpot], color: Color, route: Route,
                      pick: (vid: String, name: String)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.offset) { item in
                let i = item.offset, id = item.element
                let all = model.arrivals(at: id, routeId: rid)
                let next = pick != nil ? BusNumbers.busArrival(all, vehicleId: pick?.vid) : all.first   // a picked bus: its own time only
                let here = spots.filter { $0.next == i }
                let onRail = spots.filter { ($0.prev ?? $0.next) == i }   // a marker lives in the row it is leaving
                let last = i == ids.count - 1
                let eta = TimeFmt.etaLabel(next?.t, now: model.now, stale: model.isStale)
                let name = model.staticData.stops[id]?.name ?? id
                HStack(spacing: Space.s3) {
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            Rectangle().fill(i == 0 && !loop ? .clear : color).frame(width: 4)
                            Rectangle().fill(last && !loop ? .clear : color).frame(width: 4)
                        }
                        Circle().fill(Palette.bgCard).overlay(Circle().strokeBorder(color, lineWidth: 2.5)).frame(width: 11, height: 11)
                            .offset(y: rowH / 2 - 5.5)
                        if !(last && !loop) {
                            Image(systemName: "chevron.down").font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(Color.badgeText(hex: route.color))
                                .offset(y: rowH - 5)
                        }
                        ForEach(Array(onRail.enumerated()), id: \.offset) { b in
                            BusRailMarker(route: route, label: b.element.label).fixedSize()
                                .opacity(b.element.stale ? 0.55 : 1)
                                .offset(y: b.element.prev == nil ? 2 : rowH / 2 + CGFloat(b.element.frac) * rowH - 10)
                        }
                    }
                    .frame(width: 24, height: rowH)
                    .zIndex(1)
                    .accessibilityHidden(true)
                    Button { model.push(.stop(id)) } label: {
                        HStack(spacing: Space.s2) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name).font(Typo.body).foregroundStyle(Palette.label).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                // accessibility sizes: the minutes under the name, never pushed past the edge
                                if typeSize.isAccessibilitySize && !eta.isEmpty {
                                    Text(eta).font(Typo.rowDetail.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle(eta == "Now" ? Palette.live : eta.hasPrefix("~") ? Palette.label2 : Palette.label)
                                }
                                ForEach(Array(here.enumerated()), id: \.offset) { b in
                                    Text("\(b.element.name) heading here\(b.element.stale ? ", seen \(TimeFmt.ago(b.element.seen, from: model.now))" : "")")
                                        .font(Typo.badgeSmall).foregroundStyle(Color.badgeText(hex: route.color))
                                        .padding(.horizontal, 6).frame(minHeight: 20)
                                        .background(color.opacity(b.element.stale ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if !typeSize.isAccessibilitySize {
                                Spacer(minLength: 0)
                                if !eta.isEmpty {
                                    Text(eta).font(Typo.rowDetail.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle(eta == "Now" ? Palette.live : eta.hasPrefix("~") ? Palette.label2 : Palette.label)
                                        .fixedSize()
                                }
                            }
                        }
                        .frame(minHeight: rowH)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ChromePressStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name)\(Self.etaSay(eta, pick: pick?.name))\(here.isEmpty ? "" : ", a bus is heading here")")
                    .accessibilityAddTraits(.isButton)
                }
                .padding(.horizontal, Space.insetContent)
            }
        }
        .padding(.vertical, Space.s1)
    }

    /// The spoken time of a stop row (web route.js): ", next bus in 4 min" / ", no prediction", or for a picked bus
    /// ", Bus 2 in 4 min" / ", no prediction for Bus 2".
    static func etaSay(_ eta: String, pick: String?) -> String {
        let when = eta == "Now" ? "now" : "in " + eta.replacingOccurrences(of: "~", with: "about ")
        if let pick { return eta.isEmpty ? ", no prediction for \(pick)" : ", \(pick) \(when)" }
        return eta.isEmpty ? ", no prediction" : ", next bus \(when)"
    }

    /// Local (America/Chicago) date of `t`, e.g. "2026-10-9": the schedule section only changes with it.
    static func localDay(_ t: Double) -> String {
        let p = Schedule.localParts(t)
        return "\(p.y)-\(p.m)-\(p.d)"
    }
}

/// "Hours & service" from the official schedule. Its calendar maths (week summary, changes in the next 30 days,
/// scheduled buses by hour) depends only on the route, the local date and the route's alerts, so the view is
/// equatable on those and is not rebuilt on every live poll or clock tick.
struct RouteScheduleView: View, Equatable {
    @Environment(AppModel.self) private var model
    let rid: String
    let day: String
    /// A time on `day` (used for the 30-day window and the weekday).
    let t: Double
    /// This route's active service alerts (shown under "Schedule changes").
    let alertIds: [String]
    /// `AppModel.staticVersion`: a newer schedule downloaded while this page is open redraws it.
    var version = 0

    nonisolated static func == (a: RouteScheduleView, b: RouteScheduleView) -> Bool {
        a.rid == b.rid && a.day == b.day && a.alertIds == b.alertIds && a.version == b.version
    }

    var body: some View { service(model.staticData.service) }

    @ViewBuilder func service(_ svc: ServiceData) -> some View {
        let week = Schedule.weekSummary(svc, rid)
        let alerts = model.alerts.filter { alertIds.contains($0.id) }
        let has = Schedule.routeService(svc, rid) != nil
        if has || !alerts.isEmpty {
            SectionTitle(text: "Hours & service")
            if !week.isEmpty {
                Card {
                    ForEach(Array(week.enumerated()), id: \.element.days) { item in
                        let w = item.element
                        if item.offset > 0 { RowDivider(inset: Space.insetContent) }
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(w.days).font(Typo.rowTitle).foregroundStyle(Palette.label)
                            Spacer(minLength: Space.s2)
                            Text(w.label).font(Typo.rowDetail).foregroundStyle(Palette.label2).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, Space.insetContent)
                        .padding(.vertical, Space.s3)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            let changes = Schedule.upcomingChanges(svc, rid, t)
            if !changes.isEmpty || !alerts.isEmpty {
                SectionTitle(text: "Schedule changes")
                Card {
                    ForEach(alerts) { a in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Image(systemName: Sym.alert).font(.system(size: IconSize.inline)).foregroundStyle(Palette.warn)
                                .accessibilityHidden(true)
                            (Text("Service alert: ").fontWeight(.semibold)
                                + Text(a.header.isEmpty ? (a.description.isEmpty ? "Service alert" : a.description) : a.header))
                                .font(Typo.rowDetail).foregroundStyle(Palette.label)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.insetContent)
                        .padding(.vertical, Space.s3)
                        .background(Palette.warnBg)
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(Array(changes.enumerated()), id: \.element.date) { item in
                        let c = item.element
                        if item.offset > 0 || !alerts.isEmpty { RowDivider(inset: Space.insetContent) }
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(c.label).font(Typo.rowTitle).foregroundStyle(Palette.label)
                            Spacer(minLength: Space.s2)
                            Text(c.text).font(Typo.rowDetail).foregroundStyle(Palette.label2).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, Space.insetContent)
                        .padding(.vertical, Space.s3)
                        .accessibilityElement(children: .combine)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            } else if has {
                Text("No schedule changes in the next 30 days.").font(Typo.footnote).foregroundStyle(Palette.label2)
                    .padding(.horizontal, Space.insetContent)
            }
            busesChart(svc)
            if has {
                Text("Hours and bus counts come from the official published schedule. Live service may differ.")
                    .font(Typo.footnote).foregroundStyle(Palette.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.insetContent)
            }
        }
    }

    @ViewBuilder func busesChart(_ svc: ServiceData) -> some View {
        if let chart = RouteText.busesChart(svc, rid: rid, now: t) {
            let list = chart.list
            let maxN = max(1, list.map(\.buses).max() ?? 1)
            let first = list[0].hour
            let span = (list[list.count - 1].hour - first + 24) % 24 + 1
            let by = Dictionary(list.map { ($0.hour, $0.buses) }, uniquingKeysWith: { a, _ in a })
            let bars = (0..<span).map { i -> (hour: Int, buses: Int) in let h = (first + i) % 24; return (h, by[h] ?? 0) }
            SectionTitle(text: "Scheduled buses by hour, \(chart.when)")
            Card(padded: true) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(bars, id: \.hour) { x in
                            VStack(spacing: 3) {
                                Text(x.buses > 0 ? "\(x.buses)" : " ").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(Palette.label2)
                                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(x.buses > 0 ? Palette.tint : Palette.fill)
                                    .frame(height: max(2, CGFloat(x.buses) / CGFloat(maxN) * 60))
                                Text(x.hour % 3 == 0 ? Schedule.hourLabel(x.hour).replacingOccurrences(of: " ", with: "") : " ")
                                    .font(.system(size: 9)).foregroundStyle(Palette.label2).lineLimit(1).fixedSize()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(RouteText.hoursLines(list), id: \.self) { Text($0).font(Typo.footnote).foregroundStyle(Palette.label2) }
                    }
                }
            }
        }
    }
}
