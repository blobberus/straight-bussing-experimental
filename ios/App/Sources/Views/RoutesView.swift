import SwiftUI
import StraightBussingKit

/// Routes tab (ui/views/routes.js): Edit map order (header), the custom-route / journey bar ("Make this a custom
/// route", "Showing <name>", "<name>, edited" with Update / Save as new, "Only showing routes for …"), the
/// "Routes to <station>" filter, the visibility actions Show all / Show running / Hide all (three capsule actions, the
/// one matching the current state checked, spec 10.12), then Running / Scheduled, no live location / Not running /
/// Hidden groups with a per-route eye toggle (persisted), official contact at the bottom. A scheduled route with no
/// reporting bus is never "Not running" (rider safety), and a feed outage is "Live status unknown".
struct RoutesView: View {
    @Environment(AppModel.self) private var model
    @State private var naming = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        List {
            // every section's rows on the card color (Group hands the modifier to each section)
            Group {
                if model.editingOrder { orderSection } else { listSections }
            }
            .listRowBackground(Palette.bgCard)
            .listRowSeparatorTint(Palette.separator)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .reportsSheetScroll()
        .environment(\.editMode, .constant(model.editingOrder ? .active : .inactive))
        .accessibilityIdentifier("routesList")
    }

    var orderSection: some View {
        let order = RouteVisibility.drawOrder(model.routeState)
        return Section {
            ForEach(Array(order.enumerated()), id: \.element) { item in
                let rid = item.element
                HStack(spacing: Space.s3) {
                    RouteBadge(route: model.route(rid), rid: rid).frame(minWidth: Space.leadingSlot)
                    Text(model.longName(rid)).font(Typo.body).foregroundStyle(Palette.label)
                }
                .frame(minHeight: Space.rowMin)
                .accessibilityElement(children: .combine)
                .accessibilityValue("Position \(item.offset + 1) of \(order.count)")
                .accessibilityAction(named: "Move up") { model.moveRoute(rid, by: -1) }
                .accessibilityAction(named: "Move down") { model.moveRoute(rid, by: 1) }
            }
            .onMove { from, to in
                guard let i = from.first else { return }
                model.moveRoute(order[i], to: to > i ? to - 1 : to)
            }
            if !model.routeState.routeOrder.isEmpty {
                Button("Reset order") { model.resetMapOrder() }.foregroundStyle(Palette.tint)
            }
        } header: {
            ListHeader("Map order")
        } footer: {
            Text("Drag a route by its handle. Routes higher in this list are drawn on top on the map.")
                .font(Typo.footnote).foregroundStyle(Palette.label2)
        }
        .listRowBackground(Palette.bgCard)
    }

    // MARK: List

    struct Groups { var running: [String] = [], scheduled: [String] = [], idle: [String] = [], hidden: [String] = [] }

    /// Running / scheduled with no live bus ([] in a feed outage) / not running / hidden (routes.js groupRoutes).
    var groups: Groups {
        let hidden = Set(model.hidden), outage = model.liveOutage, svc = model.staticData.service
        var g = Groups()
        for id in model.routeList() {
            if hidden.contains(id) { g.hidden.append(id) }
            else if model.running(id) > 0 { g.running.append(id) }
            else if !outage && Operating.scheduledNoLive(id, buses: model.buses, service: svc, now: model.now) { g.scheduled.append(id) }
            else { g.idle.append(id) }
        }
        return g
    }

    /// The operator's number from its alerts (shown with no bus reporting; NoBusHelp does the same).
    var operatorCall: LiveText.PhoneLink? {
        LiveText.operatorPhone(OperatorAlerts.shown(model.activeAlerts, untiedOnly: false, routes: model.staticData.routes))
    }

    /// No bus is reporting and the list opens with why (the operator's alerts and whom to call): the end-of-list
    /// contact uses the operator's number first then, so the screen has one set of call buttons.
    var noBusHelpShown: Bool {
        model.routeState.routeFilter == nil && !model.routeList().isEmpty
            && (model.liveOutage || (model.liveLoaded && model.buses.isEmpty))
    }

    @ViewBuilder var listSections: some View {
        let s = model.routeState
        let g = groups
        let total = g.running.count + g.scheduled.count + g.idle.count + g.hidden.count
        topBar
        if let f = s.routeFilter {
            Section {
                HStack(spacing: Space.s3) {
                    Image(systemName: "bus").font(.system(size: IconSize.row)).foregroundStyle(Palette.label2)
                        .frame(minWidth: Space.leadingSlot).accessibilityHidden(true)
                    Text("Routes to \(f.label)").font(Typo.rowTitle).foregroundStyle(Palette.label)
                    Spacer()
                    Button { model.clearRouteFilter() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: IconSize.row)).foregroundStyle(Palette.label3).tapTarget()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear station filter, show all routes")
                }
                if model.activeTrip == nil {
                    let on = s.journey?.kind == .station
                    Button(on ? "Show all routes" : "Only show these routes") { model.toggleStationJourney() }
                        .foregroundStyle(Palette.tint)
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        if total == 0 {
            Section {
                if s.routeFilter != nil {
                    EmptyStateView(title: "No routes at this station", message: "Clear the filter to see every route.", icon: "bus", inList: true)
                } else {
                    EmptyStateView(title: "No routes", message: "The schedule data did not load. Reload the app.", icon: "bus", inList: true)
                }
            }
        } else {
            let empty = model.liveLoaded && model.buses.isEmpty
            if noBusHelpShown {
                // the operator's alerts stay at the top; whom to call (its number first, then ours, then the official
                // page) is the last section, under every route (owner 2026-10-17; web routes.js listHTML)
                Section {
                    if model.liveOutage {
                        EmptyStateView(title: "Live bus status unavailable", message: "Can't reach the shuttle feed. Routes are listed below for reference.",
                                       icon: Sym.feedError, inList: true)
                    } else if model.silentService {
                        EmptyStateView(title: "No live locations right now",
                                       message: Operating.silentText(g.scheduled, routes: model.staticData.routes, service: model.staticData.service,
                                                                     now: model.now, phone: LiveText.phone),
                                       icon: Sym.noLive, inList: true)
                    } else {
                        EmptyStateView(title: "No shuttles running right now", message: "Routes are listed below for reference.", icon: "bus", inList: true)
                    }
                    // the calls are at the bottom: no second button for them in the alert cards
                    OperatorAlerts(hideCalls: Set([operatorCall?.url, OfficialContact.telURL].compactMap { $0 }), plain: true)
                }
            }
            if s.journey == nil {
                Section {
                    let scope = s.routeFilter != nil ? " at this station" : ""
                    let anyVisible = !(g.running.isEmpty && g.scheduled.isEmpty && g.idle.isEmpty)
                    ViewThatFits(in: .horizontal) {
                        EqualWidthHStack { filterButtons(scope: scope, allShown: g.hidden.isEmpty, noneShown: !anyVisible) }
                        VStack(spacing: 0) { filterButtons(scope: scope, allShown: g.hidden.isEmpty, noneShown: !anyVisible) }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            if !g.running.isEmpty { Section(header: ListHeader("Running")) { ForEach(g.running, id: \.self) { RouteRow(rid: $0, hidden: false) } } }
            if !g.scheduled.isEmpty { Section(header: ListHeader("Scheduled, no live location")) { ForEach(g.scheduled, id: \.self) { RouteRow(rid: $0, hidden: false) } } }
            if !g.idle.isEmpty {
                Section(header: ListHeader(model.liveOutage ? "Live status unknown" : "Not running")) {
                    ForEach(g.idle, id: \.self) { RouteRow(rid: $0, hidden: false).opacity(empty ? 0.75 : 1) }
                }
            }
            if !g.hidden.isEmpty { Section(header: ListHeader(s.journey != nil ? "Not on this trip" : "Hidden")) { ForEach(g.hidden, id: \.self) { RouteRow(rid: $0, hidden: true) } } }
        }
        Section {
            // one set of call buttons per screen, at the bottom (with no bus reporting: the operator's number first)
            OfficialContact(operatorPhone: noBusHelpShown ? operatorCall : nil)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } footer: {
            Text("Unofficial app. Schedules come from the published GTFS feed; live positions from the public shuttle feed.")
                .font(Typo.footnote).foregroundStyle(Palette.label2)
        }
    }

    /// Show all / Show running / Hide all: three actions; the one the list already matches is checked, none is disabled.
    @ViewBuilder func filterButtons(scope: String, allShown: Bool, noneShown: Bool) -> some View {
        Button("Show all") { model.showAllRoutes() }
            .buttonStyle(CapsuleButtonStyle(current: allShown))
            .accessibilityLabel("Show all routes\(scope)")
            .accessibilityAddTraits(allShown ? .isSelected : [])
        // owner 2026-10-17: only the lines operating now; with none it says so (an on-screen message)
        Button("Show running") { model.showRunningRoutes() }
            .buttonStyle(CapsuleButtonStyle(current: model.onlyRunningShown))
            .accessibilityLabel("Show running routes only\(scope)")
            .accessibilityAddTraits(model.onlyRunningShown ? .isSelected : [])
            .accessibilityHint(model.onlyRunningShown ? "Only running routes are shown" : "")
            .accessibilityIdentifier("routes.showRunning")
        Button("Hide all") { model.hideAllRoutes() }
            .buttonStyle(CapsuleButtonStyle(current: noneShown))
            .accessibilityLabel("Hide all routes\(scope)")
            .accessibilityAddTraits(noneShown ? .isSelected : [])
    }

    /// The custom-route / journey bar above the list (routes.js topBarHTML).
    @ViewBuilder var topBar: some View {
        let s = model.routeState
        if let j = s.journey {
            Section {
                HStack {
                    Text("Only showing routes for \(j.label)").font(Typo.rowDetail).foregroundStyle(Palette.label)
                    Spacer()
                    Button("Show all") { model.endJourney() }.buttonStyle(.borderless).font(Typo.sectionTitle).foregroundStyle(Palette.tint)
                }
                .frame(minHeight: Space.rowMin)
                .accessibilityElement(children: .contain)
            }
        } else if naming {
            Section(header: ListHeader("Name this custom route")) {
                TextField("My route", text: $draft)
                    .font(Typo.body)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit(saveName)
                    .frame(minHeight: Space.rowMin)
                    .accessibilityIdentifier("routesName")
                HStack(spacing: Space.s2) {
                    Button("Cancel") { naming = false; draft = "" }.secondaryButtonStyle()
                    Spacer()
                    Button("Save") { saveName() }.primaryButtonStyle()
                }
                .buttonStyle(.borderless)
            }
        } else if let tv = s.timeView {
            Section {   // Lines by Time (TimePickView): a temporary custom route, never saved
                HStack {
                    (Text("Showing ") + Text(tv.name).fontWeight(.semibold)).font(Typo.rowDetail).foregroundStyle(Palette.label)
                    Spacer()
                    Button("Clear") { model.apply(Custom.clearTimeView(model.routeState)) }.buttonStyle(.borderless)
                        .font(Typo.sectionTitle).foregroundStyle(Palette.tint)
                        .accessibilityLabel("Clear \(tv.name), show your usual routes")
                }
                .frame(minHeight: Space.rowMin)
                .accessibilityElement(children: .contain)
            }
        } else if let c = RouteVisibility.activeCustomRoute(s) {
            Section {
                HStack {
                    if Custom.matchesCurrent(s, c) {
                        (Text("Showing ") + Text(c.name).fontWeight(.semibold)).font(Typo.rowDetail).foregroundStyle(Palette.label)
                    } else {
                        (Text(c.name).fontWeight(.semibold) + Text(" \u{00B7} edited")).font(Typo.rowDetail).foregroundStyle(Palette.label)
                    }
                    Spacer()
                    Button("Clear") { model.apply(Custom.clearCustom(model.routeState)) }.buttonStyle(.borderless)
                        .font(Typo.sectionTitle).foregroundStyle(Palette.tint)
                        .accessibilityLabel("Clear \(c.name), show your usual routes")
                }
                .frame(minHeight: Space.rowMin)
                if !Custom.matchesCurrent(s, c) {
                    HStack(spacing: Space.s2) {
                        Button("Update") { model.updateActiveCustomToVisible() }.secondaryButtonStyle()
                            .accessibilityLabel("Update \(c.name)")
                        Spacer()
                        Button("Save as new") { startNaming() }.secondaryButtonStyle()
                    }
                    .buttonStyle(.borderless)
                }
            }
        } else if !s.hiddenRoutes.isEmpty && !Custom.visibleRids(s).isEmpty {
            Section {
                Button { startNaming() } label: {
                    Label("Make this a custom route", systemImage: "bookmark")
                        .font(Typo.button).foregroundStyle(Palette.tint)
                        .frame(maxWidth: .infinity, minHeight: Space.rowMin, alignment: .leading)
                }
                .accessibilityIdentifier("makeCustom")
            }
        }
    }

    func startNaming() {
        draft = Custom.defaultName(model.routeState)
        naming = true
        nameFocused = true
    }

    func saveName() {
        model.saveVisibleAsCustom(name: draft)
        naming = false
        draft = ""
        nameFocused = false
    }
}

/// A route row: badge, name, whether it runs (the live dot and the words; also for a hidden route, owner 2026-10-17),
/// and the eye that shows or hides it.
struct RouteRow: View {
    @Environment(AppModel.self) private var model
    let rid: String
    let hidden: Bool

    var body: some View {
        let r = model.route(rid)
        let n = model.running(rid)
        // hidden only by the trip / station journey: no eye (the journey bar has Show all)
        let tripOff = hidden && model.routeState.journey != nil && !model.routeState.hiddenRoutes.contains(rid)
        HStack(spacing: Space.s3) {
            Button { model.push(.route(rid)) } label: {
                HStack(spacing: Space.s3) {
                    RouteBadge(route: r, rid: rid, dimmed: hidden).frame(minWidth: Space.leadingSlot)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.longName(rid)).font(Typo.rowTitle).foregroundStyle(hidden ? Palette.label2 : Palette.label)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if n > 0 { LiveDot().alignmentGuide(.firstTextBaseline) { $0[.bottom] } }
                            Text(subtitle(n, tripOff: tripOff)).font(Typo.rowDetail)
                                .foregroundStyle(n > 0 && !hidden ? Palette.live : Palette.label2).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.s1)
                .contentShape(Rectangle())
            }
            .buttonStyle(ChromePressStyle())
            if !tripOff {
                Button { model.toggleRouteHidden(rid) } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye").font(.system(size: IconSize.row))
                        .foregroundStyle(hidden ? Palette.label2 : Palette.tint).tapTarget()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(hidden ? "Show route \(r?.short ?? "") \(model.longName(rid))" : "Hide route \(r?.short ?? "") \(model.longName(rid))")
                .accessibilityValue(hidden ? "Hidden" : "Shown")
                .accessibilityIdentifier("eye.\(rid)")
            }
        }
        .frame(minHeight: Space.rowMin)
    }

    /// Whether the route runs, also for a hidden one (owner 2026-10-17: a grayed line must still say if it is
    /// running; web routes.js row), then why it is grayed.
    func subtitle(_ n: Int, tripOff: Bool) -> String {
        let live = liveStatus(n)
        if tripOff { return "\(live) \u{00B7} Not part of this trip" }
        if hidden { return "\(live) \u{00B7} Hidden from map and times" }
        return live
    }

    func liveStatus(_ n: Int) -> String {
        if n > 0 { return "\(n) bus\(n == 1 ? "" : "es") running" }
        if model.liveOutage { return "Live status unknown" }   // a feed outage is not "not running"
        if let s = Operating.noLiveStatus(rid, buses: model.buses, service: model.staticData.service, now: model.now) { return s }
        // iOS adds today's hours to "Not running" (one glance without opening the route)
        if let h = Schedule.hoursOn(model.staticData.service, rid, model.now), h.first != nil { return "Not running \u{00B7} Today \(h.label)" }
        return "Not running"
    }
}
