import SwiftUI
import StraightBussingKit

/// The trip in progress (docs/DESIGN-SPEC.md 10.17, web ui/views/tripprogress.js): "Trip to <destination>" with End
/// trip, the arrival line, the next-step card (the one hero of the screen: the step and its big ETA), then the steps
/// as a timeline: walks on a dotted rail, each bus leg on a rail in the route color with its stops, the followed bus
/// as a chip ON the rail between the right stops. Passed stops are dimmed AND say "Passed"; the bus position is also
/// written out, never color alone. A missed bus is a `warnBg` note at the top of the next-step card (spec 13.8).
/// Data: Kit `TripFollow` (web core/tripprogress.js), words: Kit `TripText`.
struct TripTimelineView: View {
    @Environment(AppModel.self) private var model
    let progress: TripFollow
    let trip: ActiveTrip

    var body: some View {
        let p = progress
        VStack(alignment: .leading, spacing: Space.s3) {
            // large text: End trip goes under the heading instead of squeezing the clock
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    heading
                    Spacer(minLength: Space.s2)
                    endButton
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    heading
                    endButton
                }
            }
            .padding(.horizontal, Space.s1)
            if p.stale == .old || p.stale == .err {
                InlineBanner(kind: .warn, icon: Sym.delayed, text: "Live data delayed. Bus position and times may be off.")
                    .accessibilityAddTraits(.updatesFrequently)
            }
            NowCardView(progress: p)
            SectionTitle(text: "Steps")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(p.legs.enumerated()), id: \.offset) { item in
                        switch item.element {
                        case .walk(let w): TripWalkRow(progress: p, index: item.offset, leg: w)
                        case .bus(let b): TripBusLeg(progress: p, leg: b, legIndex: item.offset)
                        }
                    }
                    TripDestinationRow(progress: p)
                }
                .padding(.vertical, Space.s2)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Trip timeline")
            }
            // never a wrapped button label: side by side, stacked at large text sizes
            ViewThatFits(in: .horizontal) {
                EqualWidthHStack {
                    stepsButton
                    PickButton()
                }
                VStack(spacing: Space.s2) {
                    stepsButton
                    PickButton()
                }
            }
            Text(TripText.footnote(p)).font(Typo.footnote).foregroundStyle(Palette.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.insetContent)
            if p.stale == .err { OfficialContact() }
        }
        .padding(.bottom, Space.s2)
    }

    /// "Trip to X" + "Arrive about 4:12 PM, 15 min est."
    var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Trip to \(progress.to)").font(Typo.heroTitle).foregroundStyle(Palette.label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            (Text(TripText.arriveLine(progress, now: model.now).replacingOccurrences(of: " \u{00B7} ", with: ", "))
                + Text(progress.arriveT != nil ? " est." : ""))
                .font(Typo.rowDetail).foregroundStyle(Palette.label2)
        }
    }

    var stepsButton: some View {
        Button {
            if model.page != .directions { model.push(.directions) }
        } label: { Text("Trip steps") }
            .secondaryButtonStyle(full: true)
    }

    var endButton: some View {
        Button("End trip") { model.endTrip() }
            .secondaryButtonStyle(destructive: true, compact: true)
            .fixedSize()
            .accessibilityIdentifier("endTrip")
    }
}

/// The next-step card: an icon (walk circle, route badge or the destination pin), the step in `heroTitle`, the big ETA
/// on the right, the detail lines under it; a missed bus first, as a `warnBg` note.
struct NowCardView: View {
    @Environment(AppModel.self) private var model
    let progress: TripFollow
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // `tripYou` comes from the same evaluation: far from the bus the counts follow, the card says so
        let c = TripText.nowCard(progress, routes: model.staticData.routes, now: model.now, you: model.tripYou)
        let missed = c.sec.filter { $0.hasPrefix("Your planned bus has left") }
        let sec = c.sec.filter { !$0.hasPrefix("Your planned bus has left") }
        Card(padded: true) {
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(missed, id: \.self) { m in
                    InlineBanner(kind: .warn, icon: "arrow.triangle.2.circlepath", text: m)
                        .accessibilityIdentifier("missedBus")
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s3))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: Space.s3))
                layout {
                    icon(c.icon)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(c.prim).font(Typo.heroTitle).foregroundStyle(Palette.label)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("tripHeadline")
                        ForEach(sec, id: \.self) {
                            Text($0).font(Typo.rowDetail).foregroundStyle(Palette.label2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    if let t = c.eta { EtaView(t: t, now: model.now, stale: c.etaApprox, size: .hero) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder func icon(_ i: TripText.NowCard.Icon) -> some View {
        switch i {
        case .walk: IconCircle(symbol: Sym.walk, size: 40)
        case .route(let rid): RouteBadge(route: model.route(rid), rid: rid).frame(minWidth: 40, minHeight: 40)
        case .pin: IconCircle(symbol: "mappin", size: 40, fill: Palette.dangerBg, color: Palette.danger)
        }
    }
}

/// The trip timeline's rail column (24 pt): a dotted walking line in `tintFill` or a solid 4 pt line in the route color.
struct RailLine: View {
    enum Style { case walk, bus(Color), passed, none }
    let style: Style
    var body: some View {
        switch style {
        case .walk:
            DottedLine()
                .stroke(Palette.tintFill, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.001, 9]))
                .frame(width: 3)
        case .bus(let c):
            Rectangle().fill(c).frame(width: 4)
        case .passed:
            Rectangle().fill(Palette.label3.opacity(0.45)).frame(width: 4)
        case .none:
            Color.clear.frame(width: 4)
        }
    }
}

struct DottedLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY + 1.5))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

/// A walking step (spec 10.16): a walk icon in a 24 pt `tintBg` circle on the dotted rail; "Walk 4 min to Ratner
/// Center" / "Walked to …" and the leave guidance.
struct TripWalkRow: View {
    @Environment(AppModel.self) private var model
    let progress: TripFollow
    let index: Int
    let leg: TripFollow.WalkStep
    var body: some View {
        let t = TripText.walkRow(progress, index, now: model.now)
        let done = leg.state == .done, active = leg.state == .active
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: done ? "checkmark" : Sym.walk)
                .font(.system(size: done ? 11 : 13, weight: .semibold))
                .foregroundStyle(done ? Palette.label2 : Palette.tint)
                .frame(width: 24, height: 24)
                .background(done ? Palette.fill : Palette.tintBg, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.head).font(active ? Typo.rowTitle : Typo.body).foregroundStyle(done ? Palette.label2 : Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                if !t.sub.isEmpty { Text(t.sub).font(Typo.rowDetail).foregroundStyle(Palette.label2) }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.insetContent)
        .padding(.bottom, Space.s4)
        .background(alignment: .topLeading) {
            RailLine(style: .walk).padding(.top, 28).padding(.bottom, 2).frame(width: 24).padding(.leading, Space.insetContent)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(active ? "Now" : done ? "Done" : "")
    }
}

/// One bus leg: head (route, stops, where the bus is; opens the route) + its stops on a rail in the route color.
struct TripBusLeg: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var rowH: CGFloat = 52
    let progress: TripFollow
    let leg: TripFollow.BusStep
    let legIndex: Int
    static let railW: CGFloat = 24

    var body: some View {
        let r = model.route(leg.rid)
        let color = Color(hex: r?.color)
        let late = progress.stale != .fresh
        let shown = TripText.shownStops(leg)
        let lead = TripText.leadRow(leg)
        let v = leg.state == .active ? leg.vehicle : nil
        let showV = v != nil && v!.idx < shown.stops.count
        let name = !(r?.long ?? "").isEmpty ? r!.long : !(r?.short ?? "").isEmpty ? r!.short : "Route"
        let meta = TripText.busMeta(leg)
        let whereLine = TripText.whereLine(leg, now: model.now)
        // minutes to every station: live where Passio has a time, else an estimate (est.) from the scheduled ride time
        let predictor = model.predictor, now = model.now, rid = leg.rid
        let times = TripText.stopTimes(leg, now: now, ride: { a, b in predictor?.rideMinutes(rid: rid, from: a, to: b, when: now).min })
        VStack(alignment: .leading, spacing: 0) {
            Button { model.push(.route(leg.rid)) } label: {
                HStack(alignment: .top, spacing: Space.s3) {
                    RouteBadge(route: r, rid: leg.rid, size: .small).frame(width: Self.railW)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(Typo.rowTitle).foregroundStyle(Palette.label)
                        Text(meta.joined(separator: ", ")).font(Typo.rowDetail).foregroundStyle(Palette.label2)
                        if !whereLine.isEmpty {
                            Text(whereLine).font(Typo.rowDetail).foregroundStyle(v?.stale == true ? Palette.warn : Palette.label2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Palette.label3)
                        .padding(.top, 3)
                }
                .padding(.horizontal, Space.insetContent)
                .padding(.bottom, Space.s2)
                .frame(minHeight: Space.tap)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name): \(meta.joined(separator: ", "))\(whereLine.isEmpty ? "" : ". " + whereLine). Open route details")
            .accessibilityAddTraits(.isButton)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    if let lead {
                        LeadRow(text: lead.text, passed: lead.passed, rowH: rowH)
                    }
                    ForEach(Array(shown.stops.enumerated()), id: \.element.id) { item in
                        TripStopRow(stop: item.element, k: item.offset, count: shown.stops.count, leg: leg, shown: shown,
                                    color: color, late: late, hasLead: lead != nil, rowH: rowH,
                                    time: times.indices.contains(item.offset) ? times[item.offset] : nil,
                                    textOn: Color.badgeText(hex: r?.color))
                    }
                }
                if showV, let v {
                    let n = Double(shown.stops.count + (lead != nil ? 1 : 0))
                    let raw = lead != nil ? (v.idx < 0 ? 0 : v.pos + 1) : v.pos
                    let vpos = (raw * 5).rounded() / 5
                    let y = CGFloat(min(max(vpos, -0.4), n - 0.6) + 0.5) * rowH
                    BusChip(label: v.label, color: color, textColor: Color.badgeText(hex: r?.color), stale: v.stale)
                        .offset(x: Space.insetContent + Self.railW / 2 - BusChip.w / 2, y: y - BusChip.h / 2)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: y)
                        .accessibilityHidden(true)   // the head line and the row labels say where the bus is
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Stops from \(leg.boardName) to \(leg.alightName)")
        }
        .padding(.bottom, Space.s2)
    }
}

/// The stop the bus just left (passed, outside your trip) or "2 more stops before X".
struct LeadRow: View {
    let text: String
    let passed: Bool
    let rowH: CGFloat
    var body: some View {
        HStack(spacing: Space.s3) {
            RailLine(style: .passed).frame(width: TripBusLeg.railW)
            Text(text).font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(2)
            Spacer(minLength: 0)
            if passed { Text("Passed").font(Typo.caption).foregroundStyle(Palette.label2) }
        }
        .padding(.horizontal, Space.insetContent)
        .frame(height: rowH)
        .accessibilityElement(children: .combine)
    }
}

/// One stop of a bus leg (spec 10.16): the rail (4 pt, route color; dimmed before boarding and once passed), a 10 pt
/// stop circle or the 14 pt solid boarding / alighting stop, the name with "Board here" / "Get off here" or the bus
/// pill, the minutes ("4 min" live, "~4 min est." estimate) or "Passed".
struct TripStopRow: View {
    @Environment(AppModel.self) private var model
    let stop: TripFollow.StopRow
    let k: Int
    let count: Int
    let leg: TripFollow.BusStep
    let shown: (stops: [TripFollow.StopRow], boardIdx: Int, alightIdx: Int)
    let color: Color
    let late: Bool
    let hasLead: Bool
    let rowH: CGFloat
    /// Minutes to this stop (TripText.stopTimes): live, or an estimate.
    let time: TripFollow.StopTime?
    /// Text on the route color.
    var textOn: Color = .white

    /// The rail between row j and j+1 is dimmed before boarding and once the bus has passed it.
    func dimSeg(_ j: Int) -> Bool {
        if j + 1 <= shown.boardIdx { return true }
        guard j + 1 < shown.stops.count else { return false }
        let s = shown.stops[j + 1].state
        return s == .passed || s == .current
    }

    var body: some View {
        let passed = stop.state == .passed
        let key = stop.role == .board || stop.role == .alight
        let topDim = (k > 0 && dimSeg(k - 1)) || (k == 0 && hasLead)
        let botDim = k < count - 1 && dimSeg(k)
        let eta = TripText.stopEta(stop, time, now: model.now, late: late)
        let pill = TripText.busPill(stop, k: k, leg)
        Button { model.push(.stop(stop.id)) } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    VStack(spacing: 0) {
                        RailLine(style: k == 0 && !hasLead ? .none : (topDim ? .passed : .bus(color)))
                        RailLine(style: k == count - 1 ? .none : (botDim ? .passed : .bus(color)))
                    }
                    if key {
                        Circle().fill(passed ? Palette.label3 : color)
                            .overlay(Circle().strokeBorder(Palette.bgCard, lineWidth: 2))
                            .frame(width: 16, height: 16)
                    } else {
                        Circle().fill(Palette.bgCard)
                            .overlay(Circle().strokeBorder(passed ? Palette.label3 : color, lineWidth: 2.5))
                            .frame(width: 11, height: 11)
                    }
                }
                .frame(width: TripBusLeg.railW)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stop.name)
                        .font(key ? Typo.rowTitle : Typo.body)
                        .foregroundStyle(passed || stop.role == .before ? Palette.label2 : Palette.label)
                        .lineLimit(2)
                    if stop.role == .board || stop.role == .alight || pill != nil {
                        HStack(spacing: Space.s1) {
                            if stop.role == .board { RoleTag(text: "Board here") }
                            if stop.role == .alight { RoleTag(text: "Get off here") }
                            if let pill {
                                Text(pill).font(Typo.badgeSmall).foregroundStyle(textOn)
                                    .padding(.horizontal, 6).frame(minHeight: 20)
                                    .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                stopTime(eta, passed: passed)
            }
            .padding(.horizontal, Space.insetContent)
            .frame(minHeight: rowH)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripText.stopSay(stop, k: k, leg, time, now: model.now, late: late))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder func stopTime(_ eta: (text: String, est: Bool), passed: Bool) -> some View {
        if passed {
            Text("Passed").font(Typo.caption).foregroundStyle(Palette.label2)
        } else if !eta.text.isEmpty {
            let now = eta.text == "Now" && !eta.est && !late
            (Text(eta.text).font(Typo.rowDetail.weight(.semibold)).monospacedDigit()
                .foregroundStyle(now ? Palette.live : (eta.est || eta.text.hasPrefix("~")) ? Palette.label2 : Palette.label)
                + Text(eta.est ? " est." : "").font(Typo.footnote).foregroundStyle(Palette.label2))
                .fixedSize()
        }
    }
}

/// "Board here" / "Get off here" (spec 10.16): `caption` Semibold in `tint` on a 20 pt `tintBg` capsule.
struct RoleTag: View {
    let text: String
    var body: some View {
        Text(text).font(Typo.caption).foregroundStyle(Palette.tint)
            .padding(.horizontal, Space.s2).frame(minHeight: 20)
            .background(Palette.tintBg, in: Capsule())
            .fixedSize()
    }
}

/// The followed bus on the rail: a route-colored chip, 20 pt tall.
struct BusChip: View {
    static let w: CGFloat = 54
    static let h: CGFloat = 20
    let label: String
    let color: Color
    let textColor: Color
    let stale: Bool
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bus.fill").font(.system(size: 10, weight: .bold))
            Text(label.count > 5 ? String(label.suffix(5)) : (label.isEmpty ? "Bus" : label)).font(Typo.badgeSmall).monospacedDigit()
        }
        .frame(width: Self.w, height: Self.h)
        .foregroundStyle(textColor)
        .background(color, in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).strokeBorder(Palette.bgCard, lineWidth: 2))
        .opacity(stale ? 0.6 : 1)
        .shadow(color: Palette.shadow.opacity(0.25), radius: 1.5, y: 1)
    }
}

/// The destination at the end of the timeline.
struct TripDestinationRow: View {
    @Environment(AppModel.self) private var model
    let progress: TripFollow
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.dangerFill)
                .frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.to).font(Typo.rowTitle).foregroundStyle(Palette.label)
                if let a = progress.arriveT {
                    (Text("Arrive about \(TimeFmt.clock(a))") + Text(" est."))
                        .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                } else {
                    Text("Destination").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.insetContent)
        .padding(.vertical, Space.s1)
        .accessibilityElement(children: .combine)
    }
}

/// The bus on the route detail rail (route.js busMarker).
struct BusRailMarker: View {
    let route: Route?
    let label: String?
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bus.fill").font(.system(size: 10, weight: .bold))
            if let label { Text(label).font(Typo.badgeSmall).monospacedDigit() }
        }
        .padding(.horizontal, 6).frame(height: 20)
        .foregroundStyle(Color.badgeText(hex: route?.color))
        .background(Color(hex: route?.color), in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).strokeBorder(Palette.bgCard, lineWidth: 2))
        .shadow(color: Palette.shadow.opacity(0.25), radius: 1.5, y: 1)
        .accessibilityLabel("Live bus position")
    }
}
