import SwiftUI
import StraightBussingKit

/// Active service alerts (ui/views/alerts.js; docs/DESIGN-SPEC.md 10.18): one card per alert with its severity icon,
/// title, the operator's text verbatim (phone numbers as call buttons), affected route badges and the time window,
/// and About at the bottom. Opened from the Current trip alert row, the status banner or My Routes.
struct AlertsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if !model.liveLoaded {
                    Card { SkeletonRows(count: 2) }
                    Hint("Checking for service alerts\u{2026}")
                } else {
                    let act = model.activeAlerts
                    if act.isEmpty {
                        EmptyStateView(title: "No active alerts", message: "Service changes will show up here.", icon: "checkmark.circle")
                    } else {
                        ForEach(act) { a in AlertRow(alert: a) }
                    }
                    if model.liveFailed {
                        InlineBanner(kind: .warn, icon: Sym.feedError, text: "Alerts may be out of date: the shuttle feed is not responding.")
                    }
                }
                Card {
                    Button { model.push(.about) } label: {
                        RowLayout(chevron: true) {
                            Image(systemName: "info.circle").font(.system(size: IconSize.status)).foregroundStyle(Palette.label2)
                                .accessibilityHidden(true)
                        } content: {
                            Text("About this app").font(Typo.body).foregroundStyle(Palette.label)
                            Text("Unofficial. Privacy, theme, official contact").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                        } trailing: { EmptyView() }
                    }
                    .buttonStyle(RowButtonStyle())
                }
                .padding(.top, Space.s2)
            }
            .padding(.horizontal, Space.insetContent)
            .padding(.top, Space.s1)
            .padding(.bottom, Space.s6)
        }
        .reportsSheetScroll()
        .accessibilityIdentifier("alertsView")
    }
}

/// One alert. `plain`: inside a List row (the row is the card already).
struct AlertRow: View {
    @Environment(AppModel.self) private var model
    let alert: ServiceAlert
    /// tel: URLs offered elsewhere on the screen (the no-bus help's call buttons): no second button for them here.
    var hideCalls: Set<String> = []
    var plain = false
    var body: some View {
        let inner = VStack(alignment: .leading, spacing: Space.s1) {
            content
            // the operator's number (e.g. "please contact 773-655-9934") one tap away, under the text
            AlertPhoneLinks(text: alert.description, indent: 29, hiding: hideCalls)
        }
        if plain { inner.padding(.vertical, Space.s2) } else { Card(padded: true) { inner } }
    }

    /// Icon, title, body, route badges and time window, read as one sentence.
    var content: some View {
        let severe = LiveText.isSevere(alert)
        let title = alert.header.isEmpty ? "Service alert" : alert.header
        let rids = Arrivals.alertRouteIds(alert, routes: model.staticData.routes)   // Passio's own ids too (DC-009)
        let when = LiveText.alertWindow(alert, now: model.now)
        return HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Image(systemName: severe ? Sym.alert : "info.circle")
                .font(.system(size: IconSize.status, weight: .semibold)).foregroundStyle(severe ? Palette.warn : Palette.label2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).font(Typo.rowTitle).foregroundStyle(Palette.label).fixedSize(horizontal: false, vertical: true)
                if !alert.description.isEmpty && alert.description != alert.header {
                    Text(alert.description).font(Typo.body).foregroundStyle(Palette.label).fixedSize(horizontal: false, vertical: true)
                }
                if !rids.isEmpty || !when.isEmpty {
                    FlowLayout(spacing: Space.s1, lineSpacing: Space.s1) {
                        ForEach(rids, id: \.self) { RouteBadge(route: model.route($0), rid: $0, size: .small) }
                        if !when.isEmpty { Text(when).font(Typo.footnote).foregroundStyle(Palette.label2).padding(.leading, rids.isEmpty ? 0 : 4) }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(severe: severe, title: title, rids: rids, when: when))
    }

    /// The VoiceOver sentence (its own function: as one inline expression, Xcode 26's type checker gives up).
    func spoken(severe: Bool, title: String, rids: [String], when: String) -> String {
        var parts: [String] = [(severe ? "Important: " : "") + title]
        if !alert.description.isEmpty { parts.append(alert.description) }
        if !rids.isEmpty { parts.append("Routes " + rids.map(model.shortName).joined(separator: ", ")) }
        if !when.isEmpty { parts.append(when) }
        return parts.joined(separator: ". ")
    }
}

/// Call buttons for the phone numbers in an alert (web alerts.js alertBodyHTML: tel links, 44 pt targets). Borderless,
/// so in a Settings row only the button calls, never a tap on the alert text.
struct AlertPhoneLinks: View {
    let text: String
    var indent: CGFloat = 0
    /// Numbers (tel: URLs) that already have a call button on the screen.
    var hiding: Set<String> = []
    var body: some View {
        let links = LiveText.phoneLinks(text).filter { !hiding.contains($0.url) }
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(links, id: \.url) { l in
                    if let url = URL(string: l.url) {
                        Link(destination: url) {
                            Label("Call \(l.shown)", systemImage: "phone.fill")
                                .frame(minHeight: Space.tap).contentShape(Rectangle())
                        }
                        .textButtonStyle(font: Typo.rowDetail.weight(.semibold))
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Call \(l.shown)")
                        .accessibilityHint("The number given in the service alert")
                    }
                }
            }
            .padding(.leading, indent)
        }
    }
}

/// The operator's active alerts in full where no bus is reporting (feed down, empty feed while routes are
/// scheduled, nothing running; web alerts.js operatorAlertsHTML): the operator posts what to do then (for example
/// a number to call when buses do not show), next to our official contact. Up to 2, then "All N service alerts".
/// The operator's words are shown as they are. `untiedOnly` (route detail): only alerts tied to no known route
/// (`Arrivals.alertRouteIds`), since the route lists its own under Schedule changes.
struct OperatorAlerts: View {
    @Environment(AppModel.self) private var model
    var untiedOnly = false
    /// Numbers with their own call button on the screen (`NoBusHelp`): not repeated in the alert cards.
    var hideCalls: Set<String> = []
    /// Inside a List row: the alerts without their own cards.
    var plain = false
    static let maxShown = 2

    /// The alerts shown in full (the first `maxShown` active ones; `untiedOnly`: those tied to no known route).
    static func shown(_ active: [ServiceAlert], untiedOnly: Bool, routes: [String: Route]) -> [ServiceAlert] {
        Array(untied(active, untiedOnly, routes).prefix(maxShown))
    }
    static func untied(_ active: [ServiceAlert], _ untiedOnly: Bool, _ routes: [String: Route]) -> [ServiceAlert] {
        active.filter { !untiedOnly || Arrivals.alertRouteIds($0, routes: routes).isEmpty }
    }

    var body: some View {
        let act = Self.untied(model.activeAlerts, untiedOnly, model.staticData.routes)
        if !act.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("From the shuttle operator").font(Typo.sectionTitle).foregroundStyle(Palette.label2)
                    .padding(.leading, plain ? 0 : Space.insetContent)
                    .padding(.top, plain ? Space.s2 : Space.s2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(act.prefix(Self.maxShown)) { a in AlertRow(alert: a, hideCalls: hideCalls, plain: plain) }
                if act.count > Self.maxShown {
                    Button("All \(act.count) service alerts") { model.openAlerts() }
                        .textButtonStyle(font: Typo.sectionTitle)
                        .buttonStyle(.borderless)   // in a Routes list row: only the button opens Alerts
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Service alerts from the shuttle operator")
            .accessibilityIdentifier("operatorAlerts")
        }
    }
}

/// Where no bus is reporting (feed down, silent scheduled service, nothing running): the operator's alerts in full
/// (their words as they are, "UGo" included), then whom to call (owner decision 2026-10-11). A number in those alerts
/// is the primary call, labeled for its purpose ("Call bus route help: 773-655-9934", the number as written there),
/// and 773.702.8181 the secondary "Safety or urgent" call; with no number there, 773.702.8181 stays the primary call.
/// The number always comes from the live feed (Kit `LiveText.operatorPhone`), never from the app, so it stays current.
struct NoBusHelp: View {
    @Environment(AppModel.self) private var model
    var untiedOnly = false
    var body: some View {
        let phone = LiveText.operatorPhone(OperatorAlerts.shown(model.activeAlerts, untiedOnly: untiedOnly,
                                                                routes: model.staticData.routes))
        VStack(spacing: Space.s3) {
            // the operator's number is the primary call below: no second button for it (or ours) in the alert card
            OperatorAlerts(untiedOnly: untiedOnly, hideCalls: Set([phone?.url, OfficialContact.telURL].compactMap { $0 }))
            OfficialContact(operatorPhone: phone)
        }
    }
}
