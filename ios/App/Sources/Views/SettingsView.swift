import SwiftUI
import UIKit
import StraightBussingKit

/// Settings (top-right gear, ui/views/settings.js): appearance, service alerts, bus alerts ("notify me when my bus
/// is near <station>": station, routes, 2 stops / 1 stop / N min, in-app banner + system notifications), the
/// iPhone-only Live Activity switch + preview, simulated buses (demo, for App Review and screenshots at night),
/// privacy with the privacy policy link, About, feedback and last the Credits (expands in place).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Settings > Credits: collapsed every time Settings opens, never stored (web settings.js creditsHTML).
    @State private var creditsOpen = false
    static let minuteChoices = [0, 2, 5, 10]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    feedbackSection
                    Group {
                        Section { ThemePicker() } header: { ListHeader("Appearance") }
                        locationSection
                        alertsSection
                        busAlerts
                        Section {
                            Toggle("Trip status on Lock Screen", isOn: Binding(get: { model.notify.liveActivity },
                                                                               set: { v in model.updateNotify { $0.liveActivity = v } }))
                            NavigationLink("Preview Live Activity") { LiveActivityPreviewView() }
                        } header: {
                            ListHeader("iPhone app")
                        } footer: {
                            Text("A Live Activity shows your bus on the Lock Screen and in the Dynamic Island: stops away, the arrival time and the next stops. Times are whole minutes, never seconds; from iOS 18 the minutes count down on their own. It updates while the app is open; locked-phone updates need a push server (planned), so 2 minutes after the last update it says the data is delayed.")
                                .font(Typo.footnote).foregroundStyle(Palette.label2)
                        }
                        demoSection
                        Section {
                            Text("No account, no ads, no tracking. Your live location is never sent anywhere; the only location data that leaves this iPhone is the start and end of a walking leg, rounded to about 10 m, sent to Apple Maps for sidewalk directions. Station and place search run on this iPhone; only when that finds fewer than 5 matches (or you tap \u{201C}Search for \u{2026} instead\u{201D}) is the typed text sent to photon.komoot.io. Downloads: the public shuttle feed, Apple Maps and schedule updates from blobberus.github.io (public files, nothing about you).")
                                .font(Typo.rowDetail).foregroundStyle(Palette.label)
                                .padding(.vertical, Space.s1)
                            Link(destination: SiteLinks.privacy) {
                                Label("Privacy policy", systemImage: "hand.raised")
                            }
                            .accessibilityHint("Opens the privacy policy in Safari")
                            .accessibilityIdentifier("privacyPolicyLink")
                        } header: {
                            ListHeader("Privacy")
                        }
                        Section {
                            NavigationLink {
                                AboutView().navigationTitle("About")
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("About this app")
                                    Text("Unofficial. Privacy, official contact").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                                }
                            }
                            Link(destination: SiteLinks.supportContact) {
                                Label("Contact support", systemImage: "questionmark.bubble")
                            }
                            .accessibilityHint("Opens the support form in Safari")
                            .accessibilityIdentifier("supportContactLink")
                        } header: {
                            ListHeader("Help")
                        }
                        creditsSection
                    }
                    .listRowBackground(Palette.bgCard)
                }
                .tint(Palette.tint)
                .scrollContentBackground(.hidden)
                .background(Palette.bgSheet)
                .task {
                    // the "Simulated buses" pill (and `-screen settingsdemo`): open at the Demo section
                    guard model.settingsAtDemo else { return }
                    model.settingsAtDemo = false
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    proxy.scrollTo("demoToggle", anchor: .top)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // iOS 26: the tinted checkmark (DESIGN-SPEC-GLASS 9.8), named "Done"; swipe down also closes. Earlier iOS:
                // the word, as their own sheets do.
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { SheetActionLabel(text: "Done", symbol: "checkmark") }
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("settingsDone")
                }
            }
        }
    }

    // MARK: Beta feedback

    /// The beta feedback card, first in Settings (owner 2026-11-02, web settings.js feedbackHTML: "the beta feedback
    /// should also be more prominent"): the tinted card, the ask, and Give feedback as the screen's primary button. The
    /// form opens in Safari; nothing is sent until the rider submits it there.
    var feedbackSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .center, spacing: Space.s3) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: IconSize.status, weight: .semibold))
                        .foregroundStyle(Palette.onFill)
                        .frame(width: 36, height: 36)
                        .background(Palette.tintFill, in: Circle())
                        .accessibilityHidden(true)
                    Text("Your feedback would be very helpful.").font(Typo.rowTitle).foregroundStyle(Palette.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link(destination: SiteLinks.feedback) {
                    HStack(spacing: Space.s2) {
                        Text("Give feedback")
                        Image(systemName: "arrow.up.right.square").font(.system(size: IconSize.inline, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .primaryButtonStyle(full: true)
                .accessibilityHint("Opens the feedback form in Safari")
                .accessibilityIdentifier("feedbackLink")
            }
            .padding(.vertical, Space.s2)
            .listRowBackground(Palette.tintBg)
        } header: {
            ListHeader("Beta feedback")
        } footer: {
            Text("This is a beta. Tell us what works and what does not.").font(Typo.footnote).foregroundStyle(Palette.label2)
        }
    }

    // MARK: Credits

    /// One credit line; with a URL the line is a link that opens in Safari.
    struct CreditItem {
        let text: String
        var url: URL? = nil
    }

    struct CreditGroup {
        let group: String
        let items: [CreditItem]
    }

    /// Settings > Credits (owner 2026-10-16: "At the very bottom of the settings menu, create a button that will expand
    /// a list of Credits ... App made by blobberus; any APIs used or data sources used for the maps and the search
    /// function; bus data collection source. Do not credit UChicago or the administration here."). Only what this app
    /// uses: Apple Maps draws the map and walks (the web's OpenFreeMap / Leaflet / OSRM lines are web only); the names
    /// on the map and the on-device place list come from OpenStreetMap; Photon; Passio's public feeds. Same facts as
    /// AboutView's credits; web settings.js CREDITS.
    static let credits: [CreditGroup] = [
        CreditGroup(group: "App", items: [
            CreditItem(text: "App made by blobberus", url: URL(string: "https://github.com/blobberus")),
        ]),
        CreditGroup(group: "Maps", items: [
            CreditItem(text: "Map and walking routes: Apple Maps (MapKit)."),
            CreditItem(text: "Building and place names on the map: OpenStreetMap contributors, ODbL.",
                       url: URL(string: "https://www.openstreetmap.org/copyright")),
        ]),
        CreditGroup(group: "Search", items: [
            CreditItem(text: "Places searched on this iPhone: a list built from OpenStreetMap data with the Overpass API.",
                       url: URL(string: "https://overpass-api.de")),
            CreditItem(text: "More places: Photon by komoot, on OpenStreetMap data.", url: URL(string: "https://photon.komoot.io")),
        ]),
        CreditGroup(group: "Bus data", items: [
            CreditItem(text: "Live bus positions, arrival predictions and service alerts: Passio's public GTFS-Realtime feeds."),
            CreditItem(text: "Routes, stops and timetables: Passio's public GTFS schedule."),
            // owner 2026-10-16: no data repo link for now (web settings.js CREDITS)
            CreditItem(text: "Data collection: the same public feeds, read every 10 seconds. Data research is currently in progress."),
        ]),
    ]

    /// The last section: a "Credits" row that expands the list below it.
    var creditsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $creditsOpen) {
                ForEach(Self.credits, id: \.group) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(g.group).font(Typo.sectionTitle).foregroundStyle(Palette.label)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(g.items, id: \.text) { item in
                            if let url = item.url {
                                Link(destination: url) {
                                    Text(item.text).font(Typo.rowDetail).multilineTextAlignment(.leading)
                                }
                                .accessibilityHint("Opens in Safari")
                            } else {
                                Text(item.text).font(Typo.rowDetail).foregroundStyle(Palette.label2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Credits")
                    Text("Maps, search and bus data sources").font(Typo.footnote).foregroundStyle(Palette.label2)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("creditsToggle")
        }
    }

    // MARK: Location

    /// "Share location" (owner 2026-10-12): the when-in-use permission, its state, and the way to change it. The app
    /// can ask once; after that only iOS Settings can change it.
    var locationSection: some View {
        Section {
            HStack {
                Label("Share location", systemImage: model.locState == .granted ? "location.fill" : "location")
                Spacer()
                Text(Self.locationStateText(model.locState)).foregroundStyle(Palette.label2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("shareLocationState")
            switch model.locState {
            case .unknown:
                Button("Allow location") { model.locate() }
                    .accessibilityHint("Asks iOS for your location while the app is open")
                    .accessibilityIdentifier("shareLocationAllow")
            case .asking:
                Text("Waiting for your answer\u{2026}").foregroundStyle(Palette.label2)
            case .granted:
                Button("Change in iOS Settings") { AppModel.openAppSettings() }
                    .accessibilityIdentifier("shareLocationSettings")
            case .denied:
                Button("Open Settings") { AppModel.openAppSettings() }
                    .accessibilityHint("Location is not allowed for Straight Bussing. Opens iOS Settings")
                    .accessibilityIdentifier("shareLocationSettings")
            }
        } header: {
            ListHeader("Location")
        } footer: {
            Text("Straight Bussing does not collect your location. It stays on your iPhone to find nearby stops; for walking directions only a rounded start and end point goes to Apple Maps, and nothing is stored.")
                .foregroundStyle(Palette.label2)
        }
    }

    static func locationStateText(_ s: LocationProvider.State) -> String {
        switch s {
        case .granted: return "On"
        case .denied: return "Not allowed"
        case .asking: return "Asking"
        case .unknown: return "Off"
        }
    }

    // MARK: Simulated buses

    /// "Simulated buses (demo)" (App Review guideline 2.1: reviewers may open the app when no shuttle runs). Off by
    /// default, never saved; while on, the status pill says "Simulated buses" and live data is neither shown nor
    /// mixed in. The switch shows the session's switch state, also under `-demo` (which simulates without a label).
    var demoSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.simulating }, set: { model.setSimulatedBuses($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Simulated buses (demo)")
                    Text("Made-up buses for trying every feature when no shuttle runs").font(Typo.footnote).foregroundStyle(Palette.label2)
                }
            }
            .id("demoToggle")
            .accessibilityIdentifier("simulatedBuses")
        } header: {
            ListHeader("Demo")
        } footer: {
            Text("While this is on, the status pill on the map reads \u{201C}\(AppModel.simulatedPillText)\u{201D} (tap it to come back here), a Live Activity says \u{201C}Simulated (demo)\u{201D}, no live data is shown or mixed in, a started trip ends and bus alerts pause. It turns off when the app restarts or after 15 minutes in the background.")
                .foregroundStyle(Palette.label2)
        }
    }

    // MARK: Service alerts

    var alertsSection: some View {
        let alerts = model.activeAlerts
        return Section {
            if !model.liveLoaded {
                Text("Checking for service alerts\u{2026}").foregroundStyle(Palette.label2)
            } else if alerts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No active alerts")
                    OfficialContact()
                }
            }
            ForEach(alerts) { a in
                VStack(alignment: .leading, spacing: 3) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.header.isEmpty ? "Service alert" : a.header).font(Typo.sectionTitle)
                        if !a.description.isEmpty { Text(a.description).font(Typo.footnote).foregroundStyle(Palette.label2) }
                        let when = LiveText.alertPeriod(a, now: model.now)
                        if !when.isEmpty { Text(when).font(Typo.footnote).foregroundStyle(Palette.label2) }
                    }
                    .accessibilityElement(children: .combine)
                    AlertPhoneLinks(text: a.description)   // a number in the alert is a call button (web b3ad52c)
                }
            }
            if model.liveLoaded && model.liveFailed {
                Label("Alerts may be out of date: the shuttle feed is not responding.", systemImage: "exclamationmark.triangle")
                    .font(Typo.footnote).foregroundStyle(Palette.warn)
            }
        } header: {
            HStack {
                ListHeader("Service alerts")
                if model.liveLoaded && !alerts.isEmpty { Text("\(alerts.count) active").foregroundStyle(Palette.warn) }
            }
        }
    }

    // MARK: Bus alerts

    /// Switch sub-lines (web settings.js TWO_SUB / ONE_SUB / TRIP_SUB): the same choices time the trip alerts.
    static let twoSub = "On a trip, also 2 stops before you get off"
    static let oneSub = "Also when your stop is next. On a trip, also 1 stop before you get off"
    static let tripSub = "Before your bus comes and before you get off, while a trip is in progress."
    static let busAlertsIntro = "Notify me when my bus is near a station, and on a trip before my bus comes and before I get off. Times are estimates from live predictions."

    var busAlerts: some View {
        let n = model.notify
        let stop = n.stopId.flatMap { model.staticData.stops[$0] }
        return Section {
            Text(Self.busAlertsIntro).font(Typo.rowDetail).foregroundStyle(Palette.label2)
            Toggle(isOn: Binding(get: { model.notify.trip }, set: { model.setTripAlerts($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trip alerts")
                    Text(Self.tripSub).font(Typo.footnote).foregroundStyle(Palette.label2)
                }
            }
            .accessibilityIdentifier("tripAlerts")
            if model.feedSimulated && model.activeTrip != nil && n.trip {
                Label("Bus alerts are paused while simulated buses are on.", systemImage: "pause.circle")
                    .font(Typo.footnote).foregroundStyle(Palette.label2)
            } else if let line = Notify.tripStatusLine(model.activeTrip != nil ? model.tripFollow : nil, prefs: n, live: model.live, now: model.now) {
                Text(line).font(Typo.footnote).foregroundStyle(Palette.label2)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("tripAlertsNow")
            }
            NavigationLink {
                StationPicker()
            } label: {
                HStack {
                    Text("Station")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(stop?.name ?? "Choose").foregroundStyle(Palette.label2).lineLimit(1)
                        if let id = n.stopId, let addr = model.staticData.addresses[id]?.address {
                            Text(addr).font(Typo.footnote).foregroundStyle(Palette.label2).lineLimit(1)
                        }
                    }
                }
            }
            .accessibilityHint(stop == nil ? "Choose a station" : "Change the station")
            if let id = n.stopId, stop != nil { routesRows(id) }
            // when to alert: the station's alerts and the trip alerts alike, so they show without a station too
            Toggle(isOn: Binding(get: { model.notify.twoStops }, set: { v in model.updateNotify { $0.twoStops = v } })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("2 stops away")
                    Text(Self.twoSub).font(Typo.footnote).foregroundStyle(Palette.label2)
                }
            }
            Toggle(isOn: Binding(get: { model.notify.oneStop }, set: { v in model.updateNotify { $0.oneStop = v } })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("1 stop away")
                    Text(Self.oneSub).font(Typo.footnote).foregroundStyle(Palette.label2)
                }
            }
            Picker("When the bus is", selection: Binding(get: { model.notify.minutes }, set: { v in model.updateNotify { $0.minutes = v } })) {
                ForEach(Self.minuteChoices, id: \.self) { m in Text(m == 0 ? "Off" : "\(m) min away").tag(m) }
            }
            Toggle(isOn: Binding(get: { model.notify.inApp }, set: { v in model.updateNotify { $0.inApp = v } })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("In-app alerts while open")
                    Text("A banner at the top of the app").font(Typo.footnote).foregroundStyle(Palette.label2)
                }
            }
            if let id = n.stopId, stop != nil { status(id) }
            if n.trip || stop != nil { permissionRow }
            if stop != nil {
                // the system destructive red is 3.6:1 on the row; the token red passes in both themes
                Button("Turn off bus alerts") { model.turnOffBusAlerts() }
                    .tint(Palette.danger)
                    .accessibilityIdentifier("busAlertsOff")
            }
        } header: {
            ListHeader("Bus alerts")
        } footer: {
            Text("If live data goes down, you get one \u{201C}Live data delayed\u{201D} alert instead of silence. Alerts work only while the app is open; lock-screen alerts need a push server (planned).")
                .foregroundStyle(Palette.label2)
        }
    }

    /// The routes watched at the station (any visible route by default; at least one stays on).
    @ViewBuilder func routesRows(_ stopId: String) -> some View {
        let serve = model.staticData.stopRoutes[stopId] ?? []
        let watched = Set(Notify.watchedRoutes(model.notify, staticData: model.staticData, hidden: model.hidden))
        let hidden = Set(model.hidden)
        Text(model.notify.rids.isEmpty ? "Routes (any visible route)" : "Routes").font(Typo.sectionTitle).foregroundStyle(Palette.label2)
        ForEach(serve, id: \.self) { rid in
            Toggle(isOn: Binding(get: { watched.contains(rid) }, set: { _ in model.toggleAlertRoute(rid) })) {
                HStack(spacing: 8) {
                    RouteBadge(route: model.route(rid), rid: rid)
                    Text(model.longName(rid))
                    if hidden.contains(rid) { Text("hidden").font(Typo.footnote).foregroundStyle(Palette.label2) }
                }
            }
        }
        if !model.notify.rids.isEmpty {
            Button("Use any visible route") { model.updateNotify { $0.rids = [] } }
        }
    }

    /// One-glance status of the nearest bus for the station (settings.js statusHTML).
    @ViewBuilder func status(_ stopId: String) -> some View {
        if model.simulating {
            Label("Bus alerts are paused while simulated buses are on.", systemImage: "pause.circle")
                .font(Typo.footnote).foregroundStyle(Palette.label2)
        } else if model.tripAlertsRunning {
            Label(Notify.tripPausedText, systemImage: "pause.circle")
                .font(Typo.footnote).foregroundStyle(Palette.label2)
                .accessibilityIdentifier("stationPausedForTrip")
        } else if model.liveLoaded && (model.staleLevel == .err || model.staleLevel == .old) {
            Label("Live data is unavailable, so bus alerts are paused.", systemImage: "exclamationmark.triangle")
                .font(Typo.footnote).foregroundStyle(Palette.warn)
        } else if let first = Notify.stopsAway(staticData: model.staticData, live: model.live, stopId: stopId,
                                                rids: Notify.watchedRoutes(model.notify, staticData: model.staticData, hidden: model.hidden),
                                                now: model.now).first {
            let away = first.stopsAway == 0 ? "Your stop is next" : "\(first.stopsAway) stop\(first.stopsAway == 1 ? "" : "s") away"
            let when = Notify.minutesText(first.etaS, now: model.now)
            HStack(spacing: 8) {
                RouteBadge(route: model.route(first.rid), rid: first.rid)
                VStack(alignment: .leading, spacing: 1) {
                    Text(away + (when.isEmpty ? "" : " \u{00B7} " + when)).font(Typo.sectionTitle)
                    Text("Next stop: \(first.nextStopName). From live predictions.").font(Typo.footnote).foregroundStyle(Palette.label2)
                }
            }
            .accessibilityElement(children: .combine)
        } else if model.liveLoaded {
            Text("No bus is heading there right now.").font(Typo.footnote).foregroundStyle(Palette.label2)
        }
    }

    /// Notification permission for the chosen station's alerts. Without it, alerts still show as an in-app banner.
    @ViewBuilder var permissionRow: some View {
        switch model.notifPermission {
        case .granted:
            Label("Alerts arrive as notifications while the app is open.", systemImage: "bell.badge")
                .font(Typo.footnote).foregroundStyle(Palette.label2)
        case .denied:
            VStack(alignment: .leading, spacing: 3) {
                Label("Notifications are off", systemImage: "bell.slash").font(Typo.sectionTitle)
                Text("Notifications for Straight Bussing are turned off in iOS Settings, so alerts show as a banner inside the app while it is open.")
                    .font(Typo.footnote).foregroundStyle(Palette.label2)
            }
            .accessibilityElement(children: .combine)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
        case .unknown:
            Button("Allow notifications") { model.requestNotifPermission() }
                .accessibilityHint("Without notifications, alerts show as a banner inside the app.")
        }
    }
}

/// Auto / Light / Dark (web ui/theme.js), in Settings and About.
struct ThemePicker: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Picker("Theme", selection: Binding(get: { model.theme }, set: { model.setTheme($0) })) {
            Text("Auto").tag("auto")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Appearance")
        // a selection tick on a segmented change (spec 9 haptics); none for live updates
        .sensoryFeedback(.selection, trigger: model.theme)
    }
}

/// Choose the station for bus alerts (favorites, the nearest station, then search; settings.js stationHTML).
struct StationPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let S = model.staticData
        let q = query.trimmingCharacters(in: .whitespaces)
        let results = q.isEmpty ? [] : StationSearch.settings(S.stops, stopRoutes: S.stopRoutes, q)
        let near = model.user.flatMap { Geo.nearestStops(S.stops, $0, max: 1, maxM: 1500, routeStops: S.routeStops).first }
        List {
            if q.isEmpty {
                let favs = model.routeState.favStops.filter { S.stops[$0] != nil }
                if !favs.isEmpty {
                    Section(header: ListHeader("Favorites")) { ForEach(favs, id: \.self) { id in row(id, S.stops[id]?.name ?? id, sub: nil) } }
                }
                if let near {
                    Section { row(near.id, near.name, sub: "Nearest station \u{00B7} \(TripInfo.mins(near.d / Geo.walkMetersPerMin)) min walk") }
                }
                let all = S.stops.values.filter { !(S.stopRoutes[$0.id] ?? []).isEmpty }.sorted { $0.name < $1.name }
                Section(header: ListHeader("Stations")) { ForEach(all) { s in row(s.id, s.name, sub: nil) } }
            } else if results.isEmpty {
                Text("No stations match.").foregroundStyle(Palette.label2)
            } else {
                Section(header: ListHeader("Matching stations")) { ForEach(results, id: \.id) { m in row(m.id, m.name, sub: nil) } }
            }
            if model.notify.stopId != nil {
                Section { Button("Cancel") { dismiss() } }
            }
        }
        .searchable(text: $query, prompt: "Station name")
        .navigationTitle("Station")
    }

    func row(_ id: String, _ name: String, sub: String?) -> some View {
        Button {
            model.setAlertStation(id)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(Palette.label)
                    if let sub { Text(sub).font(Typo.footnote).foregroundStyle(Palette.label2) }
                    HStack(spacing: 3) {
                        ForEach(model.staticData.stopRoutes[id] ?? [], id: \.self) { RouteBadge(route: model.route($0), rid: $0, size: .small) }
                    }
                }
                Spacer()
                if model.notify.stopId == id { Image(systemName: "checkmark").foregroundStyle(Palette.tint).accessibilityLabel("Selected") }
            }
            .frame(minHeight: 44)
        }
    }
}
