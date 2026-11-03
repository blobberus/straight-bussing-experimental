import SwiftUI
import StraightBussingKit

/// Stop detail (ui/views/stop.js; docs/DESIGN-SPEC.md 10.14 "place details for a station"): the address and walk, the
/// routes at this stop as badges (each opens its route), Directions (the one primary action) / From here / Favorite in
/// one row, live arrivals (route badge, name, the source mark, ETA; each opens its route), hidden routes counted with
/// Show, and the freshness line. The header's right side keeps the next arrival.
struct StopDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let stopId: String
    static let maxArrivals = 10

    var body: some View {
        if let stop = model.staticData.stops[stopId] {
            content(stop)
        } else {
            VStack(spacing: Space.s3) {
                EmptyStateView(title: "Stop not found", message: "This stop is not in the current schedule.", icon: "mappin.slash")
                Button { model.popToRoot(); model.select(.current) } label: { Text("Back to Current trip") }
                    .secondaryButtonStyle(full: true)
            }
            .padding(Space.insetContent)
        }
    }

    func content(_ stop: Stop) -> some View {
        let hidden = Set(model.hidden)
        var all: [String] = []
        for r in model.staticData.stopRoutes[stopId] ?? [] where !all.contains(r) { all.append(r) }
        let shown = all.filter { !hidden.contains($0) }, hid = all.filter { hidden.contains($0) }
        let arrivals = Array(model.arrivals(at: stopId).prefix(Self.maxArrivals))
        let address = model.staticData.addresses[stopId]?.address
        let walk = model.user.map { u -> String in "\(TripInfo.mins(Geo.walkMin(Geo.hav(u, stop.coord) * Geo.walkDetour))) min walk" }
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text([address ?? "Address not available", walk].compactMap { $0 }.joined(separator: ", "))
                        .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    if shown.isEmpty {
                        Text(all.isEmpty ? "No routes listed for this stop." : "None of your visible routes stop here.")
                            .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                    } else {
                        // the badge is the visual; 10 pt around it is its 44 pt hit area
                        FlowLayout(spacing: 0, lineSpacing: 0) {
                            ForEach(shown, id: \.self) { rid in
                                Button { model.push(.route(rid)) } label: {
                                    RouteBadge(route: model.route(rid), rid: rid)
                                        .padding(.vertical, 10).padding(.trailing, Space.s2)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(ChromePressStyle())
                                .accessibilityLabel("Route \(model.longName(rid))")
                                .accessibilityHint("Opens the route")
                            }
                        }
                        .padding(.vertical, -6)
                    }
                }
                .padding(.horizontal, Space.s1)
                // one row sized by the words, the leftover shared (web .v-stopacts); a narrow phone wraps the last one;
                // accessibility sizes stack all three, Directions first
                if typeSize.isAccessibilitySize {
                    VStack(spacing: Space.s2) { actionButtons(stop) }
                } else {
                    FillRowLayout { actionButtons(stop) }
                }
                SectionTitle(text: "Arrivals")
                if !model.liveLoaded {
                    Card { SkeletonRows(count: 3) }
                } else if arrivals.isEmpty {
                    emptyArrivals(shown: shown)
                } else {
                    Card {
                        ForEach(Array(arrivals.enumerated()), id: \.offset) { item in
                            if item.offset > 0 { RowDivider() }
                            ArrivalButton(a: item.element)
                        }
                    }
                }
                if !hid.isEmpty {
                    let n = "+\(hid.count) hidden route\(hid.count > 1 ? "s" : "") also stop\(hid.count > 1 ? "" : "s") here"
                    if model.routeState.journey != nil {
                        Text("\(n) (hidden during your trip).").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                            .padding(.horizontal, Space.insetContent)
                    } else {
                        HStack {
                            Text("\(n).").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                            Spacer()
                            Button("Show") { model.unhideRoutes(at: stopId) }.secondaryButtonStyle(compact: true)
                                .accessibilityLabel("Show the hidden routes that stop here")
                        }
                        .padding(.leading, Space.insetContent)
                    }
                }
                Text(LiveText.updatedText(lastOk: model.lastOk, failed: model.liveFailed, level: model.staleLevel, now: model.now))
                    .font(Typo.footnote.weight(model.staleLevel == .err ? .semibold : .regular))
                    .foregroundStyle(model.staleLevel == .err ? Palette.warn : Palette.label2)
                    .padding(.horizontal, Space.insetContent)
            }
            .padding(.horizontal, Space.insetContent)
            .padding(.top, Space.s1)
            .padding(.bottom, Space.s6)
        }
        .reportsSheetScroll()
    }

    /// "Directions" (to this stop; the primary action), "From here" and "Favorite" (spec 10.14): one row, stacked when
    /// a label would not fit (larger text), Primary first.
    @ViewBuilder func actionButtons(_ stop: Stop) -> some View {
        let fav = model.isFav(stopId)
        Button { model.directionsTo(stopId: stopId) } label: {
            Text("Directions").lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle(hPad: Space.s3))
        .accessibilityLabel("Directions to \(stop.name)")
        .accessibilityIdentifier("stopDirections")
        Button { model.directionsFrom(stopId: stopId) } label: {
            Text("From here").lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle(hPad: Space.s3))
        .accessibilityLabel("Directions from \(stop.name)")
        Button { model.toggleFavorite(stopId) } label: {
            HStack(spacing: 6) {
                Image(systemName: fav ? "star.fill" : "star").foregroundStyle(Palette.star)
                Text(fav ? "Favorited" : "Favorite").lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle(hPad: Space.s3))
        .accessibilityLabel(fav ? "Remove from favorites" : "Add to favorites")
        .accessibilityValue(fav ? "Favorited" : "")
        .accessibilityIdentifier("favButton")
    }

    /// Why there is no time (stop.js): feed outage, silent scheduled service at this stop, nothing predicted.
    @ViewBuilder func emptyArrivals(shown: [String]) -> some View {
        let running = !model.buses.isEmpty
        let silent = !running && model.silentService
        let here = silent ? model.silentText(among: Set(shown)) : nil
        if model.liveOutage {
            EmptyStateView(title: "Live times unavailable", message: "Can't reach the shuttle feed, so we can't tell when the next bus comes.",
                           icon: Sym.feedError, showOfficial: true, operatorAlerts: true)
        } else if let here {
            EmptyStateView(title: "No live times right now", message: here, icon: Sym.noLive, showOfficial: true, operatorAlerts: true)
        } else {
            EmptyStateView(title: "No upcoming arrivals",
                           message: running ? "Nothing is predicted at this stop right now." : silent ? "No visible route at this stop is scheduled right now." : "No shuttles are running right now.",
                           icon: "clock", showOfficial: !running, operatorAlerts: !running)
        }
    }
}
