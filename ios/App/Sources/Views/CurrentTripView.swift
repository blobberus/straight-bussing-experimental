import SwiftUI
import UIKit
import StraightBussingKit

/// "Current trip" tab (web ui/views/nearby.js, view id `nearby`; docs/DESIGN-SPEC.md J1). Ship checklist item 3: the
/// next bus in one glance, no taps (owner decision 2026-10-11). Order, the same as the web:
/// 1. the one-line service alert row;
/// 2. the trip in progress (spec 10.17) when one is started;
/// 3. the next bus: the nearest stop with up to 3 arrivals (location known, or a place chosen), else the favorite
///    stations' next buses, else "Use my location" as the one primary action;
/// 4. the station search with "Type an address or place" and "Routes to station…" in one row under it;
/// 5. more of the same glance: "Also nearby", the walking footnote, favorites, "Arriving soon";
/// 6. a quiet "No trip in progress" line (no card).
/// A typed search shows its results right under the field and hides the rest. Never a dead end; location off is a
/// first-class state.
struct CurrentTripView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var placeMode = false
    @State private var places = PlaceUI()

    /// Farthest stop still called "nearby" (meters).
    static let nearbyMaxM = 5000.0
    /// Favorites shown here (the rest are in My Routes).
    static let favMax = 3

    struct SearchKey: Equatable { var q: String; var place: Bool; var exact: Bool }

    /// What the next-bus block is built from.
    enum Lead: Equatable { case here(LatLon), place(Endpoint), favorites, nothing }

    var lead: Lead {
        if let u = model.user { return .here(u) }
        if let a = model.nearAnchor { return .place(a) }
        return model.routeState.favStops.contains { model.staticData.stops[$0] != nil } ? .favorites : .nothing
    }

    var tripOn: Bool { model.tripFollow != nil && model.activeTrip != nil }
    var typing: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                // the search field keeps one place in this stack (typing never moves focus): the content around it
                // hides while a search is typed, so the results sit right under the field
                if !typing { leading }
                searchBlock
                if typing { results } else { trailing }
            }
            .padding(.horizontal, Space.insetContent)
            .padding(.top, Space.s1)
            .padding(.bottom, Space.s6)
        }
        .reportsSheetScroll()
        .accessibilityIdentifier("currentTrip")
        .task(id: SearchKey(q: query, place: placeMode, exact: places.exact)) {
            guard placeMode else { return }
            await PlaceSearchFlow.run(query, exact: places.exact, model: model, update: { places = $0 }, current: { places })
        }
    }

    // MARK: Above the search field

    @ViewBuilder var leading: some View {
        AlertsBanner()
        if let p = model.tripFollow, let trip = model.activeTrip {
            TripTimelineView(progress: p, trip: trip)
        }
        switch lead {
        case .here(let u):
            heroBlock(u, guide: true)
        case .place(let a):
            anchorRow(a)
            heroBlock(a.coord, guide: false)
        case .favorites:
            FavoritesCard()
            locBlock
        case .nothing:
            locBlock   // the one primary action, right under the title; the station search comes next
        }
    }

    // MARK: Under the search field

    @ViewBuilder var trailing: some View {
        switch lead {
        case .here(let u):
            moreNearby(u, guide: true)
            FavoritesCard()
        case .place(let a):
            moreNearby(a.coord, guide: false)
            FavoritesCard()
            locBlock
        case .favorites, .nothing:
            soonList
        }
        if !tripOn {
            Text("No trip in progress. To start one, search for a destination and tap Start.")
                .font(Typo.footnote).foregroundStyle(Palette.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.insetContent)
                .padding(.top, Space.s2)
        }
    }

    @ViewBuilder var searchBlock: some View {
        SearchField(placeholder: placeMode ? "Address, building or place" : "Search stations", text: $query,
                    identifier: "nearbySearch", onSubmit: submit)
            .padding(.top, typing ? 0 : Space.s1)
        if placeMode {
            Button("Search stations instead") { placeMode = false; places = PlaceUI() }
                .textButtonStyle(font: Typo.rowDetail.weight(.semibold))
            PhotonNote()
        } else if !typing {
            // two secondary actions in one row (spec J1), stacked when they do not fit
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s4) {
                    placeButton
                    Spacer(minLength: 0)
                    if !tripOn { PickButton(text: true) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    placeButton
                    if !tripOn { PickButton(text: true) }
                }
            }
            .padding(.top, -Space.s2)
        }
    }

    var placeButton: some View {
        Button("Type an address or place") { placeMode = true }
            .textButtonStyle(font: Typo.rowDetail.weight(.semibold))
            .multilineTextAlignment(.leading)
    }

    // MARK: Location

    @ViewBuilder var locBlock: some View {
        switch model.locState {
        case .asking:
            Hint("Finding your location\u{2026}").accessibilityAddTraits(.updatesFrequently)
        case .denied:
            // denied (spec 13.3): what is going on, the way to iOS Settings, and the station search right after
            Card(padded: true) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Image(systemName: "location.slash").font(.system(size: IconSize.status, weight: .semibold))
                            .foregroundStyle(Palette.label2).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Location is off").font(Typo.rowTitle).foregroundStyle(Palette.label)
                            Text("To see stops near you, allow location for Straight Bussing in iOS Settings. You can still search below.")
                                .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Text("Change in iOS Settings") }
                        .secondaryButtonStyle(full: true)
                        .accessibilityIdentifier("openLocationSettings")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("locationDenied")
        default:
            Button { model.locate() } label: {
                Label("Use my location", systemImage: "location.fill")
            }
            .primaryButtonStyle(full: true)
            .accessibilityHint("Your location stays on this iPhone")
            .accessibilityIdentifier("useMyLocation")
        }
    }

    func anchorRow(_ a: Endpoint) -> some View {
        Card {
            RowLayout {
                IconCircle(symbol: "mappin", size: 32)
            } content: {
                Text("Showing stops near").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                Text(a.label).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
            } trailing: {
                Button("Clear") { model.nearAnchor = nil }
                    .textButtonStyle(font: Typo.sectionTitle)
                    .accessibilityLabel("Clear place \(a.label)")
            }
        }
    }

    // MARK: Typed query

    func submit() {
        if placeMode { if let p = places.items.first { choosePlace(p) } ; return }
        if let first = StationSearch.match(model.staticData.stops, stopRoutes: model.staticData.stopRoutes, query, max: 1).first {
            model.push(.stop(first.id))
        }
    }

    func choosePlace(_ p: PlaceHit) {
        model.nearAnchor = Endpoint(label: p.label, coord: p.coord, sub: p.sub)
        query = ""; placeMode = false; places = PlaceUI()
        model.flyTo(p.coord, span: 0.01)
    }

    @ViewBuilder var results: some View {
        if placeMode {
            PlaceList(state: places, typed: query, errorTitle: "Could not search places right now",
                      errorBody: "Check your connection, or search a station by name.", onPick: choosePlace,
                      onExact: { on in places.fix = on ? places.assumed : nil; places.exact = on })
        } else {
            let m = StationSearch.match(model.staticData.stops, stopRoutes: model.staticData.stopRoutes, query, max: 8)
            if m.isEmpty {
                EmptyStateView(title: "No matching stations", message: "Check the spelling, or type an address instead.",
                               icon: "magnifyingglass")
                Button { placeMode = true } label: { Text("Search addresses and places") }
                    .secondaryButtonStyle(full: true)
            } else {
                Card {
                    ForEach(m, id: \.id) { s in
                        if s.id != m.first?.id { RowDivider() }
                        Button { model.push(.stop(s.id)) } label: {
                            RowLayout(chevron: true) {
                                Image(systemName: "bus").font(.system(size: IconSize.row)).foregroundStyle(Palette.label2)
                                    .accessibilityHidden(true)
                            } content: {
                                Text(s.name).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                                Text((model.staticData.stopRoutes[s.id] ?? []).map(model.shortName).joined(separator: ", "))
                                    .font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(2)
                            } trailing: { EmptyView() }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: The next bus

    func near(_ p: LatLon) -> [Geo.NearStop] {
        StationSearch.near(model.staticData, p, maxM: Self.nearbyMaxM, max: 3, hidden: Set(model.hidden))
    }

    /// The nearest stop with its next arrivals (the hero card, fully visible when expanded), then, when no bus is
    /// reporting, why and whom to call.
    @ViewBuilder func heroBlock(_ p: LatLon, guide: Bool) -> some View {
        let stops = near(p)
        if let first = stops.first {
            StopCard(stop: first, max: 3, hero: true, guide: guide)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("nextBusBlock")
            // no bus is reporting: why, the operator's alert in full and whom to call, before more stops
            if model.liveLoaded && model.buses.isEmpty { NoServiceView() }
        } else {
            EmptyStateView(title: guide ? "No stops near you" : "No stops within 5 km of this place",
                           message: guide ? "You seem to be more than 5 km from the shuttle network. Search a station or place below."
                                          : "Try another place or search a station.",
                           icon: "mappin.slash")
        }
    }

    /// "Also nearby": two more stops with one arrival each, then the walking footnote.
    @ViewBuilder func moreNearby(_ p: LatLon, guide: Bool) -> some View {
        let stops = near(p)
        if stops.isEmpty {
            if guide { soonList }
        } else if stops.count > 1 {
            SectionTitle(text: "Also nearby")
            ForEach(stops.dropFirst(), id: \.id) { s in
                StopCard(stop: s, max: 1, hero: false, guide: guide)
            }
            if guide {
                Text("Leave times use a walking estimate (80 m a minute) and live bus times. Allow extra time.")
                    .font(Typo.footnote).foregroundStyle(Palette.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.insetContent)
            }
        }
    }

    @ViewBuilder var soonList: some View {
        if !model.liveLoaded {
            SectionTitle(text: "Arriving soon")
            Card { SkeletonRows(count: 3) }
        } else {
            let soon = soonest
            if soon.isEmpty {
                NoServiceView()
            } else {
                SectionTitle(text: "Arriving soon")
                Card {
                    ForEach(Array(soon.enumerated()), id: \.offset) { item in
                        if item.offset > 0 { RowDivider() }
                        Button { model.push(.stop(item.element.stop)) } label: {
                            SoonRow(stopName: model.staticData.stops[item.element.stop]?.name ?? item.element.stop, a: item.element.a)
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
        }
    }

    /// The next visible arrival per served stop, soonest first (top 6), from the per-poll arrival index.
    var soonest: [(stop: String, a: Arrival)] {
        let hidden = Set(model.hidden), now = model.now
        var all: [(stop: String, a: Arrival)] = []
        for (sid, list) in model.arrivalIndex where !(model.staticData.stopRoutes[sid] ?? []).isEmpty {
            if let a = list.first(where: { $0.t > now - 30 && !hidden.contains($0.rid) }) { all.append((stop: sid, a: a)) }
        }
        return Array(all.sorted { $0.a.t < $1.a.t || ($0.a.t == $1.a.t && $0.stop < $1.stop) }.prefix(6))
    }
}

/// "Routes to station…" (opens the chooser: current location / select a station / type an address or place).
struct PickButton: View {
    @Environment(AppModel.self) private var model
    /// A text button (Current trip's row) instead of a full-width secondary button.
    var text = false
    var body: some View {
        if text {
            Button("Routes to station\u{2026}") { open() }
                .textButtonStyle(font: Typo.rowDetail.weight(.semibold))
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("pickOpen")
        } else {
            Button { open() } label: { Text("Routes to station\u{2026}") }
                .secondaryButtonStyle(full: true)
                .accessibilityIdentifier("pickOpen")
        }
    }

    func open() { model.pickMode = nil; model.push(.pick) }
}

/// Why there are no arrivals (web nearby.js noService): a feed outage is not a service outage, and an empty feed
/// during scheduled service is not "no shuttles running".
struct NoServiceView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.liveOutage {
            EmptyStateView(title: "Live times unavailable",
                           message: "Can't reach the shuttle feed, so we can't tell which shuttles are running. Check with the official service.",
                           icon: Sym.feedError, showOfficial: true, operatorAlerts: true)
        } else if !model.buses.isEmpty {
            EmptyStateView(title: "No upcoming arrivals", message: "No bus on your visible routes has a predicted arrival right now.",
                           icon: "clock", showOfficial: true)
        } else if model.silentService, let why = model.silentText() {
            EmptyStateView(title: "No live locations right now", message: why, icon: Sym.noLive, showOfficial: true, operatorAlerts: true)
        } else {
            EmptyStateView(title: "No shuttles running right now", message: "Check the official schedule for service hours.",
                           icon: "bus", showOfficial: true, operatorAlerts: true)
        }
    }
}

/// A stop with its next arrivals (nearby.js stopCard). With `guide`, each row says when to leave (walking estimate)
/// or that you cannot walk there in time; one more arrival is listed when none of the first can be caught.
struct StopCard: View {
    @Environment(AppModel.self) private var model
    let stop: Geo.NearStop
    let max: Int
    let hero: Bool
    let guide: Bool

    var body: some View {
        let walkM = guide ? TripInfo.stopWalkMin(stop.d) : nil
        let all = model.arrivals(at: stop.id)
        let list = pick(all, walkM)
        Card {
            Button { model.push(.stop(stop.id)) } label: {
                RowLayout(chevron: true) {
                    EmptyView()
                } content: {
                    Text(stop.name).font(hero ? Typo.heroTitle : Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                    Text(Self.walkLine(stop.d)).font(Typo.rowDetail).foregroundStyle(Palette.label2)
                } trailing: { EmptyView() }
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityHint("Opens the stop")
            if !model.liveLoaded {
                RowDivider(inset: Space.insetContent)
                SkeletonRows(count: hero ? 2 : 1)
            } else if list.isEmpty {
                RowDivider(inset: Space.insetContent)
                HStack(spacing: Space.s2) {
                    Text(model.liveOutage ? "Live times unavailable" : model.silentService ? "No live times right now" : "No upcoming arrivals")
                        .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        ForEach((model.staticData.stopRoutes[stop.id] ?? []).filter { !model.hidden.contains($0) }.prefix(5), id: \.self) {
                            RouteBadge(route: model.route($0), rid: $0, size: .small)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, Space.insetContent)
                .padding(.vertical, Space.s3)
            } else {
                ForEach(list, id: \.self) { a in
                    RowDivider(inset: a == list.first ? Space.insetContent : Space.separatorInset)
                    if let w = walkM {
                        let c = TripInfo.catchNote(a.t, walkMin: w, now: model.now)
                        ArrivalButton(a: a, sub: c.text, miss: c.kind == .miss, aria: c.aria)
                    } else {
                        ArrivalButton(a: a)
                    }
                }
            }
        }
    }

    /// "2 min walk, 146 m" (one middle dot per line at most: a comma here, spec 10.8).
    static func walkLine(_ d: Double) -> String {
        "\(TripInfo.mins(Geo.walkMin(d * Geo.walkDetour))) min walk, \(Int(JS.round(d))) m"
    }

    /// The first `max`, plus one more when none of those can be caught on foot (nearby.js pickArrivals). The hero
    /// card keeps its 3 rows: its last row becomes the first bus you can still catch.
    func pick(_ all: [Arrival], _ walkM: Double?) -> [Arrival] {
        var list = Array(all.prefix(max))
        guard let w = walkM, !list.isEmpty, all.count > max else { return list }
        func miss(_ a: Arrival) -> Bool { TripInfo.catchNote(a.t, walkMin: w, now: model.now).kind == .miss }
        guard list.allSatisfy(miss) else { return list }
        if hero {
            if let next = all[max...].first(where: { !miss($0) }) { list[list.count - 1] = next }
        } else {
            list.append(all[max])
        }
        return list
    }
}

/// "Arriving soon" row: route badge, stop name, route, ETA.
struct SoonRow: View {
    @Environment(AppModel.self) private var model
    let stopName: String
    let a: Arrival
    var body: some View {
        let m = Swift.max(0, TimeFmt.minsUntil(a.t, from: model.now))
        RowLayout {
            RouteBadge(route: model.route(a.rid), rid: a.rid)
        } content: {
            Text(stopName).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)   // wrap, never cut a stop name
            Text(model.route(a.rid)?.long ?? "").font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(1)
        } trailing: {
            EtaView(t: a.t, now: model.now, stale: model.isStale).frame(minWidth: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route \(model.shortName(a.rid)) at \(stopName), \(m < 1 ? "arriving now" : "in \(m) minutes")\(model.isStale ? ", estimate" : "")")
    }
}

/// Favorites: up to 3 favorite stations with their next visible arrival, and "All favorites".
struct FavoritesCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let ids = model.routeState.favStops.filter { model.staticData.stops[$0] != nil }
        if !ids.isEmpty {
            SectionTitle(text: "Favorites") {
                Button("All favorites") { model.select(.myroutes) }.textButtonStyle(font: Typo.sectionTitle)
            }
            Card {
                ForEach(Array(ids.prefix(CurrentTripView.favMax).enumerated()), id: \.element) { item in
                    if item.offset > 0 { RowDivider() }
                    row(item.element)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Favorite stations")
        }
    }

    func row(_ id: String) -> some View {
        let name = model.staticData.stops[id]?.name ?? id
        let a = model.liveLoaded ? model.arrivals(at: id).first : nil
        let unknown = model.liveOutage || model.silentService
        let m = a.map { Swift.max(0, TimeFmt.minsUntil($0.t, from: model.now)) } ?? 0
        let label = a.map { "Favorite \(name): route \(model.shortName($0.rid)) \(m < 1 ? "arriving now" : "in \(m) minutes")\(model.isStale ? ", estimate" : "")" }
            ?? "Favorite \(name): \(unknown ? "live times unavailable" : model.liveLoaded ? "no upcoming arrivals" : "loading")"
        return Button { model.push(.stop(id)) } label: {
            RowLayout {
                if let a { RouteBadge(route: model.route(a.rid), rid: a.rid) }
                else { Image(systemName: "star.fill").font(.system(size: IconSize.status)).foregroundStyle(Palette.star).accessibilityHidden(true) }
            } content: {
                Text(name).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                if let a { Text(model.route(a.rid)?.long ?? "").font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(1) }
            } trailing: {
                if let a { EtaView(t: a.t, now: model.now, stale: model.isStale).frame(minWidth: 64, alignment: .trailing) }
                else {
                    Text(unknown ? "No live times" : model.liveLoaded ? "No buses soon" : "").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                }
            }
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

/// Service alerts row (spec 10.18; web alerts.js alertBanner): "Service alert: <first title>" on one line in `warnBg`,
/// opens Alerts. At accessibility text sizes it wraps instead of truncating. Not color alone: the warning icon and the
/// words "Service alert(s)" carry the state.
struct AlertsBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if model.liveLoaded, let b = LiveText.alertBanner(model.activeAlerts) {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            Button { model.push(.alerts) } label: {
                HStack(spacing: Space.s3) {
                    Image(systemName: Sym.alert).font(.system(size: IconSize.status)).foregroundStyle(Palette.warn).accessibilityHidden(true)
                    (Text(b.head + ": ").fontWeight(.semibold).foregroundStyle(Palette.label) + Text(b.line).foregroundStyle(Palette.label))
                        .font(Typo.rowDetail)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Palette.label2).accessibilityHidden(true)
                }
                .padding(.horizontal, Space.insetContent)
                .padding(.vertical, Space.s3)
                .frame(minHeight: Space.rowMin)
                .background(Palette.warnBg, in: shape)
                .contentShape(shape)
            }
            .buttonStyle(ChromePressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(b.head): \(b.line). Open alerts")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("alertBanner")
        }
    }
}
