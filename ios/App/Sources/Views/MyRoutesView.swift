import SwiftUI
import StraightBussingKit

/// My Routes tab (ui/views/myroutes.js): custom route sets (tap = show on the map / stop showing; swipe left or
/// long-press = Details / Edit / Delete, a full swipe never runs an action, Delete asks first), favorite stations
/// with their next bus (Edit = reorder / remove), Service alerts and About (Settings is the gear in the search
/// bar, which is on screen too: one entry per intent). "New" is in the sheet header once a custom route exists.
struct MyRoutesView: View {
    @Environment(AppModel.self) private var model
    @State private var favEdit = false

    var body: some View {
        let s = model.routeState
        let favs = s.favStops.filter { model.staticData.stops[$0] != nil }
        List {
            Section {
                if s.customRoutes.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HStack(alignment: .top, spacing: Space.s3) {
                            IconCircle(symbol: "bookmark")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save the routes you ride").font(Typo.rowTitle).foregroundStyle(Palette.label)
                                Text("Group routes into a named set, like your commute, and show just those on the map with one tap.")
                                    .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button { model.push(.editCustom(nil)) } label: {
                            Label("New custom route", systemImage: "plus")
                        }
                        .primaryButtonStyle(full: true)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("newCustomEmpty")
                    }
                    .padding(.vertical, Space.s2)
                }
                ForEach(s.customRoutes) { c in
                    CustomRouteRow(c: c, active: s.activeCustom == c.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Trailing edge: first button sits at the edge -> reads Details | Edit | Delete.
                            Button { model.requestDelete(c, from: "list") } label: { Text("Delete") }
                                .tint(Palette.dangerFill)
                            Button { model.push(.editCustom(c.id)) } label: { Text("Edit") }
                                .tint(Palette.tintFill)
                            Button { model.push(.customRoute(c.id)) } label: { Text("Details") }
                                .tint(Palette.neutralFill)
                        }
                        .contextMenu {
                            Button { model.push(.customRoute(c.id)) } label: { Label("Details", systemImage: "info.circle") }
                            Button { model.push(.editCustom(c.id)) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { model.requestDelete(c, from: "list") } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            } header: {
                ListHeader("Custom routes")
            } footer: {
                if !s.customRoutes.isEmpty {
                    Text("Tap a custom route to show it on the map. Swipe left or touch and hold for details, edit or delete.")
                        .font(Typo.footnote).foregroundStyle(Palette.label2)
                }
            }
            .listRowBackground(Palette.bgCard)

            Section {
                if favs.isEmpty {
                    HStack(alignment: .top, spacing: Space.s3) {
                        Image(systemName: "star").font(.system(size: IconSize.row)).foregroundStyle(Palette.star)
                            .frame(minWidth: Space.leadingSlot).accessibilityHidden(true)
                        Text("Open a station on the map and tap Favorite. It will show up here with its next bus.")
                            .font(Typo.rowDetail).foregroundStyle(Palette.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Space.s2)
                }
                ForEach(favs, id: \.self) { id in FavoriteRow(id: id, editing: favEdit) }
                    .onMove { from, to in model.moveFavorites(from: from, to: to) }
                    .onDelete { idx in for i in idx { model.removeFavorite(favs[i]) } }
                    .deleteDisabled(!favEdit)
                    .moveDisabled(!favEdit)
            } header: {
                HStack {
                    ListHeader("Favorite stations")
                    Spacer()
                    if !favs.isEmpty {
                        Button { favEdit.toggle() } label: {
                            Text(favEdit ? "Done" : "Edit").frame(minWidth: Space.tap, minHeight: Space.tap).contentShape(Rectangle())
                        }
                        .font(Typo.sectionTitle).foregroundStyle(Palette.tint).textCase(nil)
                        .accessibilityLabel(favEdit ? "Done editing favorites" : "Edit favorites")
                    }
                }
            }
            .listRowBackground(Palette.bgCard)

            Section {
                let n = model.activeAlerts.count
                Button { model.push(.alerts) } label: {
                    HStack(spacing: Space.s3) {
                        Image(systemName: n > 0 ? Sym.alert : "exclamationmark.triangle").font(.system(size: IconSize.status))
                            .foregroundStyle(n > 0 ? Palette.warn : Palette.label2)
                            .frame(minWidth: Space.leadingSlot).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Service alerts").font(Typo.body).foregroundStyle(Palette.label)
                            Text(n > 0 ? "\(n) active alert\(n == 1 ? "" : "s")" : "None right now").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                        }
                        Spacer()
                        if n > 0 {
                            Text("\(n)").font(Typo.caption).monospacedDigit().foregroundStyle(Palette.onFill)
                                .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22).background(Palette.dangerFill, in: Capsule())
                                .accessibilityHidden(true)
                        }
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Palette.label3).accessibilityHidden(true)
                    }
                    .frame(minHeight: Space.rowMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ChromePressStyle())
                .accessibilityLabel("Service alerts, \(n > 0 ? "\(n) active" : "none right now")")
                Button { model.push(.about) } label: {
                    HStack(spacing: Space.s3) {
                        Image(systemName: "info.circle").font(.system(size: IconSize.status)).foregroundStyle(Palette.label2)
                            .frame(minWidth: Space.leadingSlot).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("About this app").font(Typo.body).foregroundStyle(Palette.label)
                            Text("Unofficial. Privacy, theme, official contact").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Palette.label3).accessibilityHidden(true)
                    }
                    .frame(minHeight: Space.rowMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ChromePressStyle())
            } header: {
                ListHeader("More")
            }
            .listRowBackground(Palette.bgCard)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.top, Space.s2, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .reportsSheetScroll()
        .environment(\.editMode, .constant(favEdit ? .active : .inactive))
        .accessibilityIdentifier("myRoutesList")
    }
}

/// A favorite station with its next visible bus (myroutes.js favRow).
struct FavoriteRow: View {
    @Environment(AppModel.self) private var model
    let id: String
    let editing: Bool
    var body: some View {
        let name = model.staticData.stops[id]?.name ?? id
        let a = model.liveLoaded ? model.arrivals(at: id).first : nil
        let sub = a.map { model.longName($0.rid) } ?? (model.liveOutage ? "Live times unavailable"
            : model.liveLoaded ? "No upcoming buses on your visible routes" : "Waiting for live data")
        let m = a.map { max(0, TimeFmt.minsUntil($0.t, from: model.now)) } ?? 0
        Button { if !editing { model.push(.stop(id)) } } label: {
            HStack(spacing: Space.s3) {
                Group {
                    if let a { RouteBadge(route: model.route(a.rid), rid: a.rid) }
                    else { Image(systemName: "star.fill").font(.system(size: IconSize.status)).foregroundStyle(Palette.star) }
                }
                .frame(minWidth: Space.leadingSlot)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                    Text(sub).font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(1)
                }
                Spacer()
                if let a, !editing { EtaView(t: a.t, now: model.now, stale: model.isStale) }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChromePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + (a.map { ", next bus \(model.longName($0.rid)) in \(m) min" } ?? ", " + sub))
        .accessibilityAddTraits(.isButton)
    }
}

/// Fixed-height row with a check circle (aria-pressed in the web); tap toggles showing it on the map.
struct CustomRouteRow: View {
    @Environment(AppModel.self) private var model
    let c: CustomRoute
    let active: Bool

    var body: some View {
        let rids = c.rids.filter { model.route($0) != nil }
        Button { model.toggleCustom(c) } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(active ? Palette.tint : Palette.label3)
                    .frame(minWidth: Space.leadingSlot)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(c.name).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(1)
                    HStack(spacing: 2) {
                        if rids.isEmpty { Text("No routes").font(Typo.rowDetail).foregroundStyle(Palette.label2) }
                        ForEach(rids.prefix(6), id: \.self) { RouteBadge(route: model.route($0), rid: $0, size: .small) }
                        if rids.count > 6 { Text("+\(rids.count - 6)").font(Typo.caption).foregroundStyle(Palette.label2).padding(.leading, 2) }
                    }
                }
                Spacer()
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChromePressStyle())
        .accessibilityLabel("\(c.name), \(rids.count) route\(rids.count == 1 ? "" : "s"). Show on the map")
        .accessibilityValue(active ? "Shown on the map" : "Not shown")
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("custom.\(c.id)")
    }
}

/// Details of a custom route (myroutes.js renderCustom): showing or not, Show on map / Stop showing, Edit /
/// Delete, its routes with live status, the next bus at the stop nearest you, and Highlight toggles.
struct CustomRouteDetailView: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        let s = model.routeState
        if let c = s.customRoutes.first(where: { $0.id == id }) {
            let on = s.activeCustom == id
            let rids = c.rids.filter { model.route($0) != nil }
            List {
                Section {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        Label(on ? "Showing on the map \u{00B7} \(rids.count) route\(rids.count == 1 ? "" : "s")" : "Not showing on the map \u{00B7} \(rids.count) route\(rids.count == 1 ? "" : "s")",
                              systemImage: on ? "checkmark.circle.fill" : "circle")
                            .font(Typo.rowTitle).foregroundStyle(Palette.label)
                        Button {
                            if on { model.apply(Custom.clearCustom(s)) } else { model.apply(Custom.applyCustom(s, id)); model.fitRoutes(c.rids) }
                        } label: { Text(on ? "Stop showing" : "Show on map") }
                            .primaryButtonStyle(full: true)
                        if on && !Custom.matchesCurrent(s, c) {
                            Text("You changed the visible routes since applying it.").font(Typo.footnote).foregroundStyle(Palette.label2)
                        }
                        HStack(spacing: Space.s2) {
                            Button { model.push(.editCustom(id)) } label: { Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity) }
                                .secondaryButtonStyle()
                            Button { model.requestDelete(c, from: "detail") } label: {
                                Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                            }
                            .secondaryButtonStyle(destructive: true)
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, Space.s2)
                }
                .listRowBackground(Palette.bgCard)
                Section {
                    if rids.isEmpty {
                        Text("None of these routes are in the current schedule. Edit to choose others.").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                    }
                    ForEach(rids, id: \.self) { rid in CustomRouteLine(customId: id, rid: rid, highlighted: c.highlight.contains(rid)) }
                } header: {
                    ListHeader("Routes")
                } footer: {
                    if rids.count > 1 {
                        Text(on ? "Highlight dims the other routes in this set on the map." : "Highlights apply while this custom route is showing.")
                            .font(Typo.footnote).foregroundStyle(Palette.label2)
                    }
                }
                .listRowBackground(Palette.bgCard)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, Space.s2, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .reportsSheetScroll()
        } else {
            VStack(spacing: Space.s3) {
                EmptyStateView(title: "Custom route not found", message: "It may have been deleted.", icon: "bookmark.slash")
                Button { model.popToRoot() } label: { Text("Back to My Routes") }.secondaryButtonStyle(full: true)
            }
            .padding(Space.insetContent)
        }
    }
}

/// A route in a custom route: live status (or when it runs again today, `Schedule.restingText`) + "Hidden on map"
/// when hidden, the next bus at your nearest stop (never for a hidden route), and a Highlight toggle. Every saved
/// route stays listed (owner 2026-10-17; web myroutes.js savedRouteStatus).
struct CustomRouteLine: View {
    @Environment(AppModel.self) private var model
    let customId: String
    let rid: String
    let highlighted: Bool

    /// Next arrival of the route at its stop nearest you (within 1.5 km), or nil without location.
    var nearestNext: (t: Double, stop: String)? {
        guard let u = model.user, model.liveLoaded else { return nil }
        var best: (sid: String, d: Double)? = nil
        for sid in Set(model.staticData.routeStops[rid] ?? []) {
            guard let s = model.staticData.stops[sid] else { continue }
            let d = Geo.hav(u, s.coord)
            if best == nil || d < best!.d { best = (sid, d) }
        }
        guard let b = best, b.d <= 1500, let a = model.arrivals(at: b.sid, routeId: rid).first else { return nil }
        return (a.t, model.staticData.stops[b.sid]?.name ?? b.sid)
    }

    var body: some View {
        let n = model.running(rid)
        let hidden = model.hidden.contains(rid)
        let run = n > 0 ? "\(n) bus\(n == 1 ? "" : "es") running" : model.liveOutage ? "Live status unavailable"
            : Operating.noLiveStatus(rid, buses: model.buses, service: model.staticData.service, now: model.now)
                ?? Schedule.restingText(model.staticData.service, rid, model.now)
        let off = hidden ? (model.routeState.journey != nil ? " \u{00B7} Not on this trip" : " \u{00B7} Hidden on map") : ""
        let next = hidden ? "" : nearestNext.map { ", \(model.isStale ? "~" : "")\(max(0, TimeFmt.minsUntil($0.t, from: model.now))) min at \($0.stop)" } ?? ""
        HStack(spacing: Space.s3) {
            Button { model.push(.route(rid)) } label: {
                HStack(spacing: Space.s3) {
                    RouteBadge(route: model.route(rid), rid: rid, dimmed: hidden).frame(minWidth: Space.leadingSlot)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.longName(rid)).font(Typo.rowTitle).foregroundStyle(hidden ? Palette.label2 : Palette.label)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if n > 0 { LiveDot().alignmentGuide(.firstTextBaseline) { $0[.bottom] } }
                            Text(run + off + next).font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ChromePressStyle())
            Button { model.apply(Custom.toggleHighlight(model.routeState, customId, rid)) } label: {
                VStack(spacing: 2) {
                    Image(systemName: highlighted ? "checkmark.circle.fill" : "circle").font(.system(size: IconSize.row))
                        .foregroundStyle(highlighted ? Palette.tint : Palette.label3)
                    Text("Highlight").font(Typo.caption).foregroundStyle(Palette.label2)
                }
                .frame(minWidth: Space.tap, minHeight: Space.tap)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Highlight \(model.longName(rid))")
            .accessibilityValue(highlighted ? "On" : "Off")
            .accessibilityAddTraits(highlighted ? .isSelected : [])
        }
        .frame(minHeight: 52)
    }
}

/// Create / edit a custom route (myroutes.js renderEditor): name ("My route N" by default) and routes grouped
/// Running now / Scheduled, no live location / Not running; "Choose at least one route." next to the list.
struct CustomRouteEditor: View {
    @Environment(AppModel.self) private var model
    let id: String?
    @State private var name = ""
    @State private var picked: Set<String> = []
    @State private var loaded = false
    @State private var error = ""

    var body: some View {
        let all = model.staticData.routeIds
        let running = all.filter { model.running($0) > 0 }
        let sched = model.liveOutage ? [] : all.filter { !running.contains($0) && Operating.scheduledNoLive($0, buses: model.buses, service: model.staticData.service, now: model.now) }
        let idle = all.filter { !running.contains($0) && !sched.contains($0) }
        List {
            Section {
                TextField("My route", text: $name).font(Typo.body).textInputAutocapitalization(.words)
                    .frame(minHeight: Space.rowMin)
                    .accessibilityIdentifier("customName")
            } header: {
                ListHeader("Name")
            }
            .listRowBackground(Palette.bgCard)
            if !error.isEmpty {
                Section {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Palette.danger).font(Typo.rowDetail.weight(.semibold))
                }
                .listRowBackground(Palette.dangerBg)
            }
            group("Running now", running)
            group("Scheduled, no live location", sched)
            group(model.liveOutage ? "Live status unknown" : "Not running", idle)
            Section {
                HStack(spacing: Space.s2) {
                    Button { model.back() } label: { Text("Cancel").frame(maxWidth: .infinity) }.secondaryButtonStyle()
                    Button { save() } label: { Text("Save").frame(maxWidth: .infinity) }.primaryButtonStyle()
                        .accessibilityIdentifier("customSave")
                }
                .buttonStyle(.borderless)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if let id, let c = model.routeState.customRoutes.first(where: { $0.id == id }) {
                    Button { model.requestDelete(c, from: "edit") } label: {
                        Label("Delete custom route", systemImage: "trash")
                    }
                    .secondaryButtonStyle(destructive: true, full: true)
                    .buttonStyle(.borderless)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.top, Space.s2, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .reportsSheetScroll()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id, let c = model.routeState.customRoutes.first(where: { $0.id == id }) {
                name = c.name
                picked = Set(c.rids)
            } else {
                name = Custom.defaultName(model.routeState)   // never suggest a name already taken
            }
        }
    }

    @ViewBuilder func group(_ title: String, _ rids: [String]) -> some View {
        if !rids.isEmpty {
            Section {
                ForEach(rids, id: \.self) { rid in
                    Button {
                        if picked.contains(rid) { picked.remove(rid) } else { picked.insert(rid) }
                        error = ""
                    } label: {
                        HStack(spacing: Space.s3) {
                            RouteBadge(route: model.route(rid), rid: rid).frame(minWidth: Space.leadingSlot)
                            Text(model.longName(rid)).font(Typo.body).foregroundStyle(Palette.label)
                            Spacer()
                            Image(systemName: picked.contains(rid) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(picked.contains(rid) ? Palette.tint : Palette.label3)
                        }
                        .frame(minHeight: Space.rowMin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ChromePressStyle())
                    .accessibilityValue(picked.contains(rid) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(picked.contains(rid) ? .isSelected : [])
                }
            } header: {
                ListHeader(title)
            }
            .listRowBackground(Palette.bgCard)
        }
    }

    func save() {
        let order = model.staticData.routeIds.filter { picked.contains($0) }
        guard !order.isEmpty else { error = "Choose at least one route."; return }
        if let id, model.routeState.customRoutes.contains(where: { $0.id == id }) {
            model.saveCustomRoute(id: id, name: name, rids: order)
        } else {
            model.createCustomRoute(name: name, rids: order)
        }
    }
}
