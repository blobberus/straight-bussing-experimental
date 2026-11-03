import SwiftUI
import StraightBussingKit

/// "Routes to station…" (ui/views/pick.js): first asks how to find the station (current location / select a
/// station / type an address or place); NOTHING is highlighted until you choose. Then the stops within 1.5 km (or
/// the matching stations) are listed and ring-highlighted on the map; choosing one shows only the routes serving
/// it on the list and map ("Routes to <station>"). Works without location permission.
struct PickView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var places = PlaceUI()
    @State private var anchor: Endpoint?
    @State private var waiting = false

    static let radiusM = 1500.0

    struct Key: Equatable { var q: String; var exact: Bool; var mode: PickMode? }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let mode = model.pickMode {
                    head(mode)
                    Card {
                        Toggle(isOn: Binding(get: { model.pickOnly }, set: { model.pickOnly = $0 })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Only show the chosen station's routes").font(Typo.body).foregroundStyle(Palette.label)
                                Text("Hides other routes on the map until you clear the station").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                            }
                        }
                        .tint(Palette.tint)
                        .padding(.horizontal, Space.insetContent)
                        .padding(.vertical, Space.s3)
                        .frame(minHeight: Space.tap)
                    }
                    list(mode)
                    otherModes(mode)
                } else {
                    Hint("Find the station first. Nothing is shared until you choose.")
                    chooser
                }
            }
            .padding(.horizontal, Space.insetContent)
            .padding(.top, Space.s1)
            .padding(.bottom, Space.s6)
        }
        .reportsSheetScroll()
        .accessibilityIdentifier("pickView")
        .onAppear { highlight(fit: true) }
        .onChange(of: highlightKey) { _, _ in highlight(fit: false) }
        .onChange(of: fitKey) { _, _ in highlight(fit: true) }
        .task(id: Key(q: query, exact: places.exact, mode: model.pickMode)) {
            guard model.pickMode == .addr, anchor == nil else { return }
            await PlaceSearchFlow.run(query, exact: places.exact, model: model, update: { places = $0 }, current: { places })
        }
    }

    // MARK: Modes

    var chooser: some View {
        Card {
            modeRow(.loc, "Use current location", "Stops within 1.5 km of you", "location")
            RowDivider()
            modeRow(.sel, "Select a station", "Search by station name", "bus")
            RowDivider()
            modeRow(.addr, "Type an address or place", "Find stops near a building or street", "mappin")
        }
    }

    func modeRow(_ m: PickMode, _ title: String, _ sub: String, _ icon: String) -> some View {
        Button { setMode(m) } label: {
            RowLayout(chevron: true) {
                Image(systemName: icon).font(.system(size: IconSize.row)).foregroundStyle(Palette.tint).accessibilityHidden(true)
            } content: {
                Text(title).font(Typo.rowTitle).foregroundStyle(Palette.label)
                Text(sub).font(Typo.rowDetail).foregroundStyle(Palette.label2)
            } trailing: { EmptyView() }
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityIdentifier("pick.\(m.rawValue)")
    }

    func setMode(_ m: PickMode) {
        query = ""; places = PlaceUI(); anchor = nil
        model.pickMode = m
        if m == .loc && model.user == nil {
            waiting = true
            model.locate()
        }
    }

    @ViewBuilder func head(_ mode: PickMode) -> some View {
        switch mode {
        case .sel:
            SearchField(placeholder: "Search station name", text: $query, identifier: "pickQuery") {
                if let first = items.first { model.chooseStation(first.id) }
            }
        case .addr:
            if let a = anchor {
                Card {
                    RowLayout {
                        IconCircle(symbol: "mappin", size: 32)
                    } content: {
                        Text("Stops within 1.5 km of").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                        Text(a.label).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                    } trailing: {
                        Button("Change") { anchor = nil; query = "" }.textButtonStyle(font: Typo.sectionTitle)
                    }
                }
            } else {
                SearchField(placeholder: "Address, building or place", text: $query, identifier: "pickQuery") {
                    if let p = places.items.first { anchor = Endpoint(label: p.label, coord: p.coord, sub: p.sub) }
                }
                PhotonNote()
            }
        case .loc:
            Hint("Nearest stops within 1.5 km of you. Tap one to see its routes.")
        }
    }

    /// Stops to list / highlight for the mode (pick.js pickItems).
    var items: [Geo.NearStop] {
        let S = model.staticData
        switch model.pickMode {
        case .loc?: return model.user.map { StationSearch.near(S, $0, maxM: Self.radiusM) } ?? []
        case .addr?: return anchor.map { StationSearch.near(S, $0.coord, maxM: Self.radiusM) } ?? []
        case .sel?:
            return StationSearch.match(S.stops, stopRoutes: S.stopRoutes, query, max: 40).map { m in
                Geo.NearStop(id: m.id, name: m.name, lat: m.coord.lat, lon: m.coord.lon, d: model.user.map { Geo.hav($0, m.coord) } ?? -1)
            }
        case nil: return []
        }
    }

    @ViewBuilder func list(_ mode: PickMode) -> some View {
        if mode == .addr && anchor == nil {
            PlaceList(state: places, typed: query, errorTitle: "Could not search places right now",
                      errorBody: "Check your connection, or select a station by name.",
                      onPick: { p in anchor = Endpoint(label: p.label, coord: p.coord, sub: p.sub) },
                      onExact: { on in places.fix = on ? places.assumed : nil; places.exact = on })
        } else if mode == .loc && model.user == nil {
            if waiting && model.locState != .denied || model.locState == .asking {
                Hint("Finding your location\u{2026}")
            } else {
                EmptyStateView(title: "Location unavailable", message: "You can still find a station without sharing your location.",
                               icon: "location.slash")
                modeButton(.sel, "Select a station", primary: true)
                modeButton(.addr, "Type an address or place", primary: false)
            }
        } else if items.isEmpty {
            if mode == .sel {
                EmptyStateView(title: "No matching stations", message: "Check the spelling, or type an address instead.", icon: "magnifyingglass")
                modeButton(.addr, "Type an address or place", primary: false)
            } else {
                EmptyStateView(title: "No stops within 1.5 km of \(mode == .addr ? anchor?.label ?? "this place" : "you")",
                               message: "Try another place or select a station by name.", icon: "mappin.slash")
                modeButton(.sel, "Select a station", primary: true)
            }
        } else {
            Card {
                ForEach(Array(items.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 { RowDivider(inset: Space.insetContent) }
                    let s = item.element
                    Button { model.chooseStation(s.id) } label: {
                        RowLayout(chevron: true) {
                            EmptyView()
                        } content: {
                            Text(s.name).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                            Text((s.d >= 0 ? Self.walkShort(s.d) + " \u{00B7} " : "") + (model.staticData.stopRoutes[s.id] ?? []).map(model.shortName).joined(separator: ", "))
                                .font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(2)
                        } trailing: { EmptyView() }
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
        }
    }

    /// "2 min walk (119 m)": the walk without a middle dot, so the routes after it make one dot per line.
    static func walkShort(_ d: Double) -> String {
        "\(TripInfo.mins(Geo.walkMin(d * Geo.walkDetour))) min walk (\(Int(JS.round(d))) m)"
    }

    func modeButton(_ m: PickMode, _ title: String, primary: Bool) -> some View {
        Group {
            if primary {
                Button { setMode(m) } label: { Text(title) }.primaryButtonStyle(full: true)
            } else {
                Button { setMode(m) } label: { Text(title) }.secondaryButtonStyle(full: true)
            }
        }
    }

    func otherModes(_ cur: PickMode) -> some View {
        let label: [PickMode: String] = [.loc: "Use my location", .sel: "Select a station", .addr: "Type an address"]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s4) {
                ForEach([PickMode.loc, .sel, .addr].filter { $0 != cur }, id: \.self) { m in
                    Button(label[m] ?? "") { setMode(m) }.textButtonStyle(font: Typo.rowDetail.weight(.semibold))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach([PickMode.loc, .sel, .addr].filter { $0 != cur }, id: \.self) { m in
                    Button(label[m] ?? "") { setMode(m) }.textButtonStyle(font: Typo.rowDetail.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, Space.s1)
    }

    // MARK: Map highlight

    /// What is highlighted: nothing until a mode has something to show (the chooser highlights nothing).
    var highlightIds: [String] {
        let show = model.pickMode == .loc || (model.pickMode == .addr && anchor != nil) || (model.pickMode == .sel && !query.trimmingCharacters(in: .whitespaces).isEmpty)
        return show ? Array(items.prefix(12).map(\.id)) : []
    }
    var highlightKey: [String] { highlightIds }
    var fitKey: String { "\(model.pickMode?.rawValue ?? "")|\(anchor?.label ?? "")|\(model.user != nil)" }

    func highlight(fit: Bool) {
        let ids = highlightIds
        if model.pickHighlights != ids { model.pickHighlights = ids }
        if model.user != nil { waiting = false }
        guard fit, !ids.isEmpty else { return }
        var pts = ids.compactMap { model.staticData.stops[$0]?.coord }
        if model.pickMode == .addr, let a = anchor { pts.append(a.coord) }
        if model.pickMode == .loc, let u = model.user { pts.append(u) }
        model.fit(pts)
    }
}
