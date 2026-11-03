import SwiftUI
import StraightBussingKit

/// Directions' typed text, focused field and suggestions (owner spec 2026-10-12: the Start / Destination fields sit
/// in a card at the top of the screen, where the search bar was, and the suggestions and trip options in the sheet
/// below). Owned by RootView and shared by both through the environment. Keystrokes never touch AppModel, so the map
/// and the rest of the UI don't redraw while typing.
@MainActor @Observable
final class DirectionsUI {
    enum Field: Hashable { case from, to }
    var focus: Field?
    var fromText = ""
    var toText = ""
    var items: [Endpoint] = []
    var places = PlaceUI()
    var itemsQuery: String?

    var query: String { focus == .from ? fromText : focus == .to ? toText : "" }

    func sync(_ model: AppModel) {
        fromText = model.dir.from?.label ?? ""
        toText = model.dir.to?.label ?? ""
    }

    /// A suggestion picked (or Return on the field): set the endpoint, show its name, drop the keyboard.
    func choose(_ e: Endpoint, for f: Field, model: AppModel) {
        if e.isMe {
            model.useMyLocation(to: f == .to)
        } else {
            model.setEndpoint(f == .from ? \DirectionsState.from : \DirectionsState.to, e)
        }
        sync(model)
        focus = nil
    }
}

extension String {
    /// Metadata with at most one middle dot per line (spec 10.8): place and stop subtitles read with commas.
    var commaSeparated: String {
        if hasPrefix("Shuttle stop \u{00B7} ") { return "Shuttle stop: " + dropFirst("Shuttle stop \u{00B7} ".count) }
        return replacingOccurrences(of: " \u{00B7} ", with: ", ")
    }
}

/// The Directions field card (spec 10.2): it takes the search bar's place (and turns back into it when Directions
/// closes; RootView). A 20 pt card of system material, two 44 pt fields on `fill`, a hollow `tint` ring for Start and a
/// `dangerFill` dot for Destination (the map's destination pin), the swap button between them. Collapsing the sheet
/// drops the keyboard and leaves the card in place, so the map shows between the card and the collapsed sheet.
struct DirectionsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(DirectionsUI.self) private var ui
    @FocusState private var focus: DirectionsUI.Field?

    var body: some View {
        @Bindable var ui = ui
        let shape = RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
        HStack(spacing: Space.s1) {
            VStack(spacing: Space.s2) {
                field(.from, text: $ui.fromText, placeholder: "Start")
                field(.to, text: $ui.toText, placeholder: "Destination")
            }
            Button { model.swapEndpoints(); ui.sync(model) } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: IconSize.row, weight: .medium))
                    .foregroundStyle(Palette.tint)
                    .frame(width: Space.tap, height: Space.tap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChromePressStyle())
            .accessibilityLabel("Swap start and destination")
        }
        .padding(10)
        .background(.regularMaterial, in: shape)
        .elevation(.floating, in: shape)
        // map chrome: grows with text size, but not so far that it hides the map
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("directionsCard")
        .onAppear {
            ui.sync(model)
            ui.places = PlaceUI()
            ui.items = []
            ui.itemsQuery = nil
            if let q = model.demoQuery { model.demoQuery = nil; ui.toText = q; setFocus(.to) }
            else if model.dir.to == nil { setFocus(.to) } else if model.dir.from == nil { setFocus(.from) }
        }
        .onDisappear { ui.focus = nil }
        .onChange(of: model.dir.from) { _, e in ui.fromText = e?.label ?? "" }
        .onChange(of: model.dir.to) { _, e in ui.toText = e?.label ?? "" }
        .onChange(of: focus) { _, f in
            if ui.focus != f { ui.focus = f }
            if let f {
                model.dirActiveTo = f == .to
                ui.places.exact = false
                ui.places.fix = nil
                if model.detent == .peek { model.detent = .full }   // typing: the suggestions need the sheet
            }
        }
        .onChange(of: ui.focus) { _, f in if focus != f { focus = f } }
        // collapsing the sheet drops the keyboard; the card stays where it is
        .onChange(of: model.detent) { _, d in if d == .peek { setFocus(nil) } }
    }

    func setFocus(_ f: DirectionsUI.Field?) {
        focus = f
        ui.focus = f
    }

    func field(_ f: DirectionsUI.Field, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Group {
                if f == .from { Circle().strokeBorder(Palette.tint, lineWidth: 2.5) } else { Circle().fill(Palette.dangerFill) }
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
            TextField(placeholder, text: text)
                .font(Typo.body)
                .foregroundStyle(Palette.label)
                .focused($focus, equals: f)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: Space.tap)
                .onSubmit { if let first = ui.items.first { ui.choose(first, for: f, model: model) } }
                .accessibilityLabel("\(placeholder): station or place")
                .accessibilityIdentifier(f == .from ? "dirFrom" : "dirTo")
            if !text.wrappedValue.isEmpty && focus == f {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: IconSize.status)).foregroundStyle(Palette.label3)
                        .frame(width: 32, height: Space.tap).contentShape(Rectangle())
                }
                .buttonStyle(ChromePressStyle())
                .accessibilityLabel("Clear")
            }
        }
        .padding(.leading, Space.s3)
        .padding(.trailing, Space.s1)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Directions in the sheet (ui/views/directions.js; spec J2 to J4), under the field card: station + place suggestions
/// for the field being typed in (on-device first, Photon only when fewer than 5 local matches, spelling-fix note);
/// else the destination's place summary, then up to 4 option cards ranked least walking > earliest arrival > shortest
/// wait, the selected one with its steps and Start. While a trip is on, a trip bar heads the results and picking
/// another card makes the timeline follow it; changing an endpoint ends the trip.
struct DirectionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(DirectionsUI.self) private var ui

    struct SuggestionKey: Equatable {
        var field: DirectionsUI.Field?
        var text: String
        var exact: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let f = ui.focus { suggestions(for: f) } else { results }
            }
            .padding(.horizontal, Space.insetContent)
            .padding(.top, Space.s1)
            .padding(.bottom, Space.s6)
        }
        .reportsSheetScroll()
        .task(id: SuggestionKey(field: ui.focus, text: ui.query, exact: ui.places.exact)) { await loadSuggestions() }
    }

    /// On-device suggestions right away; Photon merged in when it answers (only if the index has < 5 matches).
    func loadSuggestions() async {
        guard ui.focus != nil else { return }
        let q = ui.query, user = model.user, S = model.staticData
        // one "use my location" action per screen (web DESIGN "Copy"): with no start yet, the Start field offers it
        let dropMe = ui.focus == .to && model.dir.from == nil && user == nil
        func sugs(_ places: [PlaceHit], _ assumed: SearchAssumption?) -> [Endpoint] {
            let all = AppModel.suggestions(q, user: user, staticData: S, places: places, assumed: assumed)
            return dropMe ? all.filter { !$0.isMe } : all
        }
        if ui.itemsQuery != nil { try? await Task.sleep(nanoseconds: 60_000_000) }   // typing: coalesce a burst of keystrokes
        guard !Task.isCancelled else { return }
        await PlaceSearchFlow.run(q, exact: ui.places.exact, model: model, update: { st in
            ui.places = st
            ui.items = sugs(st.items, st.assumed)
            ui.itemsQuery = q
        }, current: { ui.places })
        if PlaceIndex.norm(q).count < 2 && !Task.isCancelled {
            ui.items = sugs([], nil)
            ui.itemsQuery = q
        }
    }

    @ViewBuilder func suggestions(for f: DirectionsUI.Field) -> some View {
        let q = (f == .from ? ui.fromText : ui.toText).trimmingCharacters(in: .whitespaces)
        let mine = q.count >= 2 && ui.places.q == q
        if mine { AssumeNote(state: ui.places) { on in ui.places.fix = on ? ui.places.assumed : nil; ui.places.exact = on } }
        if !ui.items.isEmpty {
            Card {
                ForEach(Array(ui.items.enumerated()), id: \.offset) { item in
                    if item.offset > 0 { RowDivider() }
                    Button { ui.choose(item.element, for: f, model: model) } label: {
                        RowLayout {
                            Image(systemName: item.element.isMe ? "location.fill" : item.element.stopId != nil ? "bus" : "mappin")
                                .font(.system(size: IconSize.row))
                                .foregroundStyle(item.element.isMe ? Palette.tint : Palette.label2)
                                .accessibilityHidden(true)
                        } content: {
                            Text(item.element.label).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                            Text(model.placeSubtitle(item.element).commaSeparated).font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(2)
                        } trailing: { EmptyView() }
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
        }
        if mine && ui.places.status == .busy {
            Hint(ui.items.contains { $0.stopId == nil && !$0.isMe } ? "Searching more places\u{2026}" : "Searching places\u{2026}")
        }
        if mine && ui.places.status == .err { Hint("Couldn\u{2019}t search places right now. Station names still work.") }
        if ui.items.isEmpty && (q.count >= 2 && ui.itemsQuery == q) && ui.places.status == .idle {
            EmptyStateView(title: "No stations or places match", message: "Try another name or an address.", icon: "magnifyingglass")
        }
        if model.dirMeDenied { Hint("Location is off. Allow it in iOS Settings, or type a start.") }
        if q.count >= 2 { PhotonNote() }
    }

    @ViewBuilder var results: some View {
        if model.dir.from == nil || model.dir.to == nil {
            if let t = model.dir.to { PlaceSummary(endpoint: t) }
            Hint("Choose a start and a destination. Type a station name, a place, or an address.")
            if model.dir.from == nil && model.user == nil {
                Button { model.useMyLocation(to: false) } label: {
                    Label("Start from my location", systemImage: "location.fill")
                }
                .secondaryButtonStyle(full: true)
            }
        } else if let r = model.dir.result {
            TripBar()
            if model.staleLevel != .fresh {
                InlineBanner(kind: .warn, icon: Sym.delayed, text: "Live data delayed. Bus times may be off.")
            }
            if let t = model.dir.to { PlaceSummary(endpoint: t) }
            if r.options.isEmpty {
                let running = !model.buses.isEmpty
                if model.liveOutage {   // a feed outage is not "no shuttles running" (rider safety)
                    EmptyStateView(title: "Can't plan shuttle trips right now",
                                   message: "The live shuttle feed can't be reached, so we can't tell which buses are running.",
                                   icon: Sym.feedError, showOfficial: true, operatorAlerts: true)
                } else {
                    let idle: String = (model.silentService ? model.silentText() : nil) ?? "No shuttles are running right now."
                    EmptyStateView(title: "No practical shuttle route right now",
                                   message: r.missedAll ? "The next buses leave before you could reach the stop."
                                       : running ? "Nothing runs close enough to both places." : idle,
                                   icon: "bus", showOfficial: !running, operatorAlerts: !running)
                }
                WalkOptionCard(r: r)
                refiningNote
            } else {
                // very close (owner 2026-10-30): walking the whole way is the first option when it takes 10 min or less
                // or arrives no later than the best bus (Kit Rank.walkFirst)
                let walkFirst = Rank.walkFirst(r)
                if walkFirst {
                    WalkOptionCard(r: r, caption: "Close enough to walk").accessibilityIdentifier("dirWalkFirst")
                }
                // the walk counts as one of the (at most 4) options, like the web list
                ForEach(Array(r.options.prefix(Planner.maxOpts - (walkFirst ? 1 : 0)).enumerated()), id: \.element.key) { item in
                    OptionCard(option: item.element, index: item.offset, showCriteria: r.options.count > 1,
                               selected: item.offset == model.dir.selected)
                }
                if !walkFirst {
                    Text("Walking the whole way: \(TripInfo.mins(r.walkOnlyMin)) min (\(r.walkOnlyM) m), \(r.walkOnlySource == .router ? "sidewalk route" : "estimate")")
                        .font(Typo.footnote).foregroundStyle(Palette.label2)
                        .padding(.horizontal, Space.insetContent)
                }
                refiningNote
                Text("Bus times are estimates from schedules and live predictions. They will get more accurate as we collect more ride data.")
                    .font(Typo.footnote).foregroundStyle(Palette.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.insetContent)
            }
        } else {
            if let t = model.dir.to { PlaceSummary(endpoint: t) }
            // finding trips: option-shaped placeholders, never a spinner on a blank sheet
            Card { SkeletonRows(count: 2) }
                .accessibilityLabel("Finding trips")
            Hint("Finding trips\u{2026}")
        }
    }

    /// Shown while Apple Maps walking routes replace the straight-line estimates.
    @ViewBuilder var refiningNote: some View {
        if model.dir.refining {
            Text("Checking sidewalk routes\u{2026}").font(Typo.footnote).foregroundStyle(Palette.label2)
                .padding(.horizontal, Space.insetContent)
                .accessibilityIdentifier("dirRefining")
        }
    }
}

/// The destination's place summary (spec 10.14, the "place details" step at no extra tap): a pin in a 36 pt `tintBg`
/// circle, the name (`heroTitle`, 2 lines), what and where it is; a destination farther than 800 m from a served stop
/// carries the coverage note inside (owner wording 2026-10-15, `Coverage`).
struct PlaceSummary: View {
    @Environment(AppModel.self) private var model
    let endpoint: Endpoint
    var body: some View {
        Card(padded: true) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    IconCircle(symbol: endpoint.stopId != nil ? "bus" : endpoint.isMe ? "location.fill" : "mappin")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(endpoint.label).font(Typo.heroTitle).foregroundStyle(Palette.label).lineLimit(2)
                        Text(model.placeSubtitle(endpoint).commaSeparated).font(Typo.rowDetail).foregroundStyle(Palette.label2)
                            .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("placeSummary")
                if !model.covered(endpoint) {
                    InlineBanner(kind: .warn, lead: Coverage.text, text: Coverage.advice)
                        .accessibilityIdentifier("dirCoverage")
                }
            }
        }
    }
}

/// Walking the whole way (spec 10.15 walk-first card, directions.js walkOptionHTML): a walk icon in a 36 pt circle,
/// "8 min walk", the arrival, the distance and where the walking time comes from. Walking times carry no "est." on the
/// iPhone (owner 2026-10-11); the source is said in words.
struct WalkOptionCard: View {
    @Environment(AppModel.self) private var model
    let r: PlanResult
    var caption: String? = nil
    var body: some View {
        let mins = TripInfo.mins(r.walkOnlyMin)
        let arrive = Text("Arrive \(TimeFmt.clock(model.now + r.walkOnlyMin * 60))").font(Typo.rowTitle).foregroundStyle(Palette.label)
        Card(padded: true) {
            HStack(alignment: .top, spacing: Space.s3) {
                IconCircle(symbol: Sym.walk)
                VStack(alignment: .leading, spacing: 2) {
                    if let caption { Text(caption).font(Typo.caption).foregroundStyle(Palette.label2) }
                    ViewThatFits(in: .horizontal) {   // large text: the arrival under the minutes, never broken inside the clock
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            Text("\(mins) min walk").font(Typo.heroTitle).monospacedDigit().foregroundStyle(Palette.label)
                            Spacer(minLength: Space.s2)
                            arrive
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(mins) min walk").font(Typo.heroTitle).monospacedDigit().foregroundStyle(Palette.label)
                            arrive
                        }
                    }
                    Text("\(r.walkOnlyM) m\(r.walkOnlySource == .router ? " on sidewalks" : ", walking estimate")")
                        .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Trip bar at the top of the results while a trip is on (journey.js tripBarHTML).
struct TripBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let trip = model.activeTrip {
            Card(padded: true) {
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Trip to \(trip.label)").font(Typo.rowTitle).foregroundStyle(Palette.label)
                        HStack(spacing: Space.s1) {
                            Text(trip.journey.rids.count > 1 ? "Map shows only these routes" : "Map shows only this route")
                                .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                            ForEach(trip.journey.rids, id: \.self) { RouteBadge(route: model.route($0), rid: $0, size: .small) }
                        }
                    }
                    Spacer(minLength: 0)
                    Button("End trip") { model.endTrip() }.secondaryButtonStyle(destructive: true, compact: true).fixedSize()
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Trip in progress")
            }
        }
    }
}

extension TripInfo {
    /// The option card's fourth line (spec 10.15): "Leave in 10 min, bus 3:11 PM at Ellis Ave & 57th St" when the first
    /// bus is live (with the live dot), else "Bus about 3:11 PM at Ellis Ave & 57th St, est." (scheduled).
    static func optionLeaveLine(_ o: TripOption, now: Double) -> (text: String, live: Bool)? {
        let times = legsTimes(o, now: now)
        guard let fb = o.legs.firstIndex(where: { $0.bus != nil }), let bus = o.legs[fb].bus, let tb = times[fb] else { return nil }
        let board = bus.board.name.isEmpty ? "the stop" : bus.board.name
        let busAt = TimeFmt.clock(tb.b)
        if let lv = leaveInfo(o, now: now) {
            let leave = lv.now ? "Leave now" : "Leave in \(Int(lv.slack.rounded(.down))) min"
            return ("\(leave), bus \(busAt) at \(board)", true)
        }
        return ("Bus about \(busAt) at \(board), est.", false)
    }
}

/// One ranked option (spec 10.15): what it minimizes, the total with "est." and the arrival, the leg strip, the leave
/// line; selected: a 2 pt `tint` border drawn inside, the steps, Start and its note.
struct OptionCard: View {
    @Environment(AppModel.self) private var model
    let option: TripOption
    let index: Int
    let showCriteria: Bool
    let selected: Bool

    var body: some View {
        let crit = showCriteria ? Rank.criteriaText(option.meets) : ""
        let leave = TripInfo.optionLeaveLine(option, now: model.now)
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Space.s3) {
            Button { model.selectOption(index) } label: {
                VStack(alignment: .leading, spacing: Space.s2) {
                    if !crit.isEmpty {
                        Text(crit).font(Typo.caption).foregroundStyle(Palette.label2)
                            .accessibilityIdentifier("criteria.\(index)")
                    }
                    // large text: the arrival goes under the total instead of breaking inside "6:37 AM"
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                            total
                            Spacer(minLength: Space.s2)
                            arrive
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            total
                            arrive
                        }
                    }
                    LegStrip(option: option)
                    if let leave {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if leave.live { LiveDot().alignmentGuide(.firstTextBaseline) { $0[.bottom] } }
                            Text(leave.text).font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ChromePressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TripInfo.optionLabel(option, index: index, criteria: crit, routes: model.staticData.routes, now: model.now))
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            if selected {
                RowDivider(inset: 0)
                StepList(option: option)
                if model.activeTrip == nil, !option.busLegs.isEmpty {
                    Button {
                        model.startTrip(option, label: model.dir.to?.label ?? "destination")
                    } label: { Text("Start") }
                        .primaryButtonStyle(full: true)
                        .accessibilityIdentifier("startTrip")
                    Text("Shows only this trip\u{2019}s routes on the map. Follow the bus stop by stop in Current trip, on the Lock Screen and in the Dynamic Island.")
                        .font(Typo.footnote).foregroundStyle(Palette.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.insetContent)
        .background(Palette.bgCard, in: shape)
        .overlay { if selected { shape.strokeBorder(Palette.tint, lineWidth: 2) } }
    }

    /// "29 min est." (`heroTitle` + the "est." suffix; no "~" in front of an estimate, O4).
    var total: some View {
        (Text("\(option.totalMin) min").font(Typo.heroTitle).foregroundStyle(Palette.label)
            + Text(" est.").font(Typo.footnote).foregroundStyle(Palette.label2))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    var arrive: some View {
        Text("Arrive \(TimeFmt.clock(option.arrive))").font(Typo.rowTitle).foregroundStyle(Palette.label).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The leg strip (spec 10.15 line 3): walk icon + minutes, `chevron.forward` in `label3`, 20 pt route badges.
struct LegStrip: View {
    @Environment(AppModel.self) private var model
    let option: TripOption
    var body: some View {
        FlowLayout(spacing: Space.s1, lineSpacing: Space.s1) {
            ForEach(Array(option.legs.enumerated()), id: \.offset) { item in
                HStack(spacing: Space.s1) {
                    if item.offset > 0 {
                        Image(systemName: "chevron.forward").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.label3)
                    }
                    switch item.element {
                    case .walk(let w):
                        HStack(spacing: 1) {
                            Image(systemName: Sym.walk).font(.system(size: IconSize.inline))
                            Text(TripInfo.walkMins(w.min)).font(Typo.footnote.weight(.semibold)).monospacedDigit()
                        }
                        .foregroundStyle(Palette.label2)
                    case .bus(let b):
                        RouteBadge(route: model.route(b.rid), rid: b.rid, size: .small)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Steps for an option (spec 10.16, tripinfo.js stepsHTML) as a timeline: walks on a dotted `tintFill` rail with a walk
/// node, bus legs on a rail in the route color under their badge, the destination pin last. Stop names and clock times
/// are Semibold; every derived time says "est." as text; the walking source ("Sidewalk route" / "Walking estimate") is
/// plain detail text.
struct StepList: View {
    @Environment(AppModel.self) private var model
    let option: TripOption
    var body: some View {
        let steps = TripInfo.steps(option, now: model.now, fromLabel: model.dir.from?.label, toLabel: model.dir.to?.label)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { item in
                StepRow(step: item.element, last: item.offset == steps.count - 1)
            }
        }
    }
}

struct StepRow: View {
    @Environment(AppModel.self) private var model
    let step: TripInfo.Step
    let last: Bool

    var body: some View {
        let s = step
        let source: String? = s.tag == "sidewalk route" ? "Sidewalk route" : s.tag == "estimate" ? "Walking estimate" : nil
        HStack(alignment: .top, spacing: Space.s3) {
            node.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                (s.title.reduce(Text("")) { acc, r in acc + Text(r.text).fontWeight(r.bold ? .semibold : .regular) }
                    + Text(s.tag == "est." ? " est." : "").font(Typo.footnote).foregroundStyle(Palette.label2))
                    .font(Typo.body).foregroundStyle(Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                if s.tag == "live" {
                    SourceLine(level: model.staleLevel)
                }
                if let sub = s.sub {
                    Text(sub + (s.subTag != nil ? ", " + s.subTag! : "")).font(Typo.rowDetail).foregroundStyle(Palette.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let source {
                    Text(source).font(Typo.rowDetail).foregroundStyle(Palette.label2)
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.bottom, last ? 0 : Space.s4)
        .background(alignment: .topLeading) {
            if !last {
                rail.padding(.top, 28).padding(.bottom, 2).frame(width: 24).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder var node: some View {
        switch step.kind {
        case .walk:
            Image(systemName: Sym.walk).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tint)
                .frame(width: 24, height: 24).background(Palette.tintBg, in: Circle())
                .accessibilityHidden(true)
        case .bus(let rid):
            RouteBadge(route: model.route(rid), rid: rid, size: .small).accessibilityHidden(true)
        case .arrive:
            Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.dangerFill)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder var rail: some View {
        switch step.kind {
        case .walk: RailLine(style: .walk)
        case .bus(let rid): RailLine(style: .bus(Color(hex: model.route(rid)?.color)))
        case .arrive: EmptyView()
        }
    }
}
