import SwiftUI
import StraightBussingKit

/// Custom bottom sheet resting on the bottom bar (the web's ui/sheet.js; docs/DESIGN-SPEC.md 10.6), owner spec
/// 2026-10-12: two resting states, collapsed (grab bar + header, whose right side keeps the one-line answer such as
/// the next bus) and expanded. Opaque `bgSheet` with 20 pt top corners and the sheet elevation (a soft shadow in light
/// mode, a hairline top border in dark mode). The whole header strip drags it (from just above the sheet's top edge
/// through the grab bar and the header; a drag that starts on Back still drags, a tap there still goes back). While the
/// finger is down the sheet follows it 1:1 (rubber band past the ends); on release it goes the way the finger last
/// moved (Kit `SheetMotion`). A tap on the grab bar toggles, a tap on a collapsed header expands. The settle is a spring
/// that starts at the finger's speed. Laid out once at full height and slid with an offset; the content's bottom inset
/// and the map padding (`onSettled`) change only after the spring finishes, so nothing re-lays out while it moves.
/// VoiceOver adjusts it (Collapsed / Expanded); Reduce Motion: a 150 ms ease, no spring.
struct BottomSheet<Header: View, Content: View>: View {
    @Binding var detent: Detent
    let available: CGFloat
    var header: Header
    var content: Content
    /// The state the sheet came to rest in and its visible height (the map padding follows it, RootView).
    var onSettled: (Detent, CGFloat) -> Void
    /// The content's bottom inset follows this, not `detent`: it changes after the spring has settled.
    @State private var insetDetent: Detent
    /// The header's measured height: collapsed = grab bar + this, so large text keeps the whole header.
    @State private var headerH: CGFloat = Space.sheetHeaderMin
    /// Finger travel since the drag began (positive = down).
    @State private var drag: CGFloat = 0
    @State private var tracking = false
    @State private var motion = SheetMotion()
    /// The release spring (carries the finger's velocity) until it settles; nil = the default spring.
    @State private var settle: Animation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(detent: Binding<Detent>, available: CGFloat, onSettled: @escaping (Detent, CGFloat) -> Void = { _, _ in },
         @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        _detent = detent
        self.available = available
        self.onSettled = onSettled
        self.header = header()
        self.content = content()
        _insetDetent = State(initialValue: detent.wrappedValue)
    }

    static var shape: UnevenRoundedRectangle { UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous) }
    /// The grab bar's zone: 6 pt above the 5 pt bar, 5 under it.
    static var grabH: CGFloat { 16 }

    static func height(for d: Detent, available: CGFloat, headerH: CGFloat) -> CGFloat {
        switch d {
        case .peek: return min(available, grabH + headerH)
        case .full: return available
        }
    }

    func h(_ d: Detent) -> CGFloat { Self.height(for: d, available: available, headerH: headerH) }
    var defaultAnimation: Animation { reduceMotion ? Motion.reduced : Motion.sheet }

    var body: some View {
        let visible = CGFloat(SheetSnap.rubberBand(Double(h(detent) - drag), min: Double(h(.peek)), max: Double(available)))
        let anim = settle ?? defaultAnimation
        VStack(spacing: 0) {
            // the header strip: one full-width hit shape, from 14 pt above the sheet's edge down to the header's end
            VStack(spacing: 0) {
                grabber
                header
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { v in
                        if abs(v - headerH) > 0.5 { headerH = v }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if detent == .peek { setDetent(.full) } }
            }
            .contentShape(TopExtendedRect(extra: 14))
            // wins over the buttons and the scroll view under it: a drag that starts anywhere on the strip moves the
            // sheet (a plain tap still reaches Back, Edit map order, New)
            .highPriorityGesture(stripDrag)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // the part below the screen in the settled state: every row can still scroll into view
                .safeAreaPadding(.bottom, available - h(insetDetent))
        }
        .frame(height: available, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(Self.shape)
        // The elevation belongs to the background shape, not to the clipped content: a shadow on content makes
        // SwiftUI render the whole sheet offscreen on every drag frame; on a filled shape it is cheap.
        .background { sheetBackground }
        .offset(y: available - visible)
        .animation(tracking ? nil : anim, value: drag)
        .animation(anim, value: detent)
        // what slides below the sheet's slot stays hidden (the bottom bar and the screen edge); room above for the
        // rubber band past expanded
        .mask(alignment: .bottom) { Rectangle().frame(height: available + 400) }
        .onAppear { onSettled(detent, h(detent)) }
        // a state set from elsewhere (a page push, a tab switch, a tap on the map): the inset and the map follow
        // once the spring has settled
        .onChange(of: detent) { _, d in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                if detent == d && !tracking { settled(d) }
            }
        }
        .onChange(of: headerH) { _, _ in if !tracking { onSettled(detent, h(detent)) } }
        .sensoryFeedback(.selection, trigger: detent)
    }

    /// e2 (spec 8): light = a soft upward shadow plus a faint edge line; dark = a 0.5 pt light top border.
    @ViewBuilder var sheetBackground: some View {
        if scheme == .dark {
            Self.shape.fill(Palette.bgSheet)
                .overlay(alignment: .top) {
                    Self.shape.stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        } else {
            Self.shape.fill(Palette.bgSheet)
                .shadow(color: Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.12), radius: 0, y: -1)
                .shadow(color: Palette.shadow.opacity(0.10), radius: 14, y: -8)
        }
    }

    func settled(_ d: Detent) {
        if insetDetent != d { insetDetent = d }
        onSettled(d, h(d))
    }

    func setDetent(_ d: Detent) {
        guard d != detent else { return }
        detent = d
    }

    /// The grab bar: 36 x 5 in `label3` at 60%, 6 pt from the top (the strip around it drags too). A tap toggles.
    var grabber: some View {
        Capsule()
            .fill(Palette.label3.opacity(0.6))
            .frame(width: 36, height: 5)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, minHeight: Self.grabH, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { setDetent(detent == .peek ? .full : .peek) }
            .accessibilityElement()
            .accessibilityLabel("Resize panel")
            .accessibilityValue(detent == .peek ? "Collapsed" : "Expanded")
            .accessibilityIdentifier("sheetGrabber")
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: setDetent(.full)
                case .decrement: setDetent(.peek)
                @unknown default: break
                }
            }
    }

    /// Global coordinates: the sheet moves under the finger, so a local translation would feed back.
    var stripDrag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { v in
                if !tracking {
                    tracking = true
                    settle = nil
                    motion.begin(at: Double(v.startLocation.y))
                }
                motion.track(Double(v.location.y))
                drag = v.translation.height
            }
            .onEnded { v in
                motion.track(Double(v.location.y))
                release(translation: v.translation.height, velocityDown: v.velocity.height)
            }
    }

    /// The way the finger last moved decides (Kit `SheetMotion`); the spring starts at the finger's speed and the
    /// inset and the map follow only after it settled.
    func release(translation: CGFloat, velocityDown: CGFloat) {
        let visible = Double(h(detent) - translation)
        let target: Detent
        switch motion.outcome {
        case .expand: target = .full
        case .collapse: target = .peek
        case .tap: target = detent
        }
        let v0 = SheetSnap.initialVelocity(visible: visible, target: Double(h(target)), velocityDown: Double(velocityDown))
        let anim: Animation = reduceMotion ? Motion.reduced
            : .interpolatingSpring(Spring(duration: 0.4, bounce: 0.04), initialVelocity: v0)
        settle = anim
        withAnimation(anim) {
            tracking = false
            drag = 0
            detent = target
        } completion: {
            if !tracking {
                settle = nil
                settled(target)
            }
        }
    }
}

/// A rectangle that reaches `extra` points above the view: the sheet's top edge is part of the drag strip.
struct TopExtendedRect: Shape {
    var extra: CGFloat
    func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.minX, y: r.minY - extra, width: r.width, height: r.height + extra))
    }
}

/// The sheet's header (spec 10.6): optional Back (44 pt, `chevron.backward` in `tint`), the title (`sheetTitle`, up to
/// 2 lines), and one trailing summary or action. The collapsed header carries the one-line answer (the next bus, the
/// best option, the trip's current step with Arriving In), so the main tasks work with the map visible. A hairline
/// appears under it when the content scrolls under it.
struct SheetHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(SheetScroll.self) private var scroll
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let back = !model.path.isEmpty
        let trip = model.page == nil && model.tab == .current && model.activeTrip != nil ? model.tripFollow : nil
        HStack(alignment: .center, spacing: Space.s2) {
            if back {
                Button { model.back() } label: {
                    Image(systemName: "chevron.backward").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.tint)
                        .frame(width: Space.tap, height: Space.tap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ChromePressStyle())
                .accessibilityLabel("Back")
                .accessibilityIdentifier("backButton")
            }
            if let p = trip, model.detent == .peek {
                // a trip in progress, collapsed (spec 10.6, O3): the current step and the trip, Arriving In on the right
                let step = TripText.nowCard(p, routes: model.staticData.routes, now: model.now, you: model.tripYou).prim
                VStack(alignment: .leading, spacing: 2) {
                    Text(step).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                        .accessibilityIdentifier("sheetTitle")
                        .accessibilityAddTraits(.isHeader)
                    Text("Trip to \(p.to)").font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(1)
                }
                .padding(.vertical, Space.s2)
            } else {
                Text(model.title)
                    .font(Typo.sheetTitle)
                    .foregroundStyle(Palette.label)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("sheetTitle")
                    .padding(.vertical, Space.s2)
            }
            Spacer(minLength: Space.s2)
            trailing(trip)
        }
        .padding(.leading, back ? Space.s1 : Space.insetContent)
        .padding(.trailing, Space.insetContent)
        .frame(minHeight: Space.sheetHeaderMin)
        .overlay(alignment: .bottom) {
            if scroll.scrolled && model.detent == .full {
                Rectangle().fill(Palette.separator).frame(height: 1 / max(1, displayScale)).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder func trailing(_ trip: TripFollow?) -> some View {
        switch model.page {
        case .stop(let id):
            if let a = model.arrivals(at: id).first {
                NextBusSummary(rid: a.rid, t: a.t, prefix: "Next bus")
            }
        case .route(let rid):
            Text(routeStatus(rid)).font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(1).fixedSize()
        case .directions:
            if let r = model.dir.result, r.options.indices.contains(model.dir.selected) {
                let m = r.options[model.dir.selected].totalMin
                (Text("\(m) min").font(Typo.etaRow) + Text(" est.").font(Typo.footnote).foregroundStyle(Palette.label2))
                    .foregroundStyle(Palette.label)
                    .fixedSize()
                    .accessibilityLabel("Selected option about \(m) minutes, estimate")
            }
        case nil where model.tab == .current:
            if let p = trip {
                if model.detent == .peek { ArrivingIn(text: TripText.arrivingIn(p, now: model.now)) }
            } else if let n = model.nearbyNext {
                // the next bus at the nearest stop, one glance (web metaNearby)
                NextBusSummary(rid: n.rid, t: n.t, prefix: "Next bus at the nearest stop")
            }
        case nil where model.tab == .routes:
            Button(model.editingOrder ? "Done" : "Edit map order") { model.editingOrder.toggle() }
                .textButtonStyle(font: Typo.sectionTitle)
                .fixedSize()
        case nil where model.tab == .myroutes:
            if !model.routeState.customRoutes.isEmpty {
                Button { model.push(.editCustom(nil)) } label: { Label("New", systemImage: "plus") }
                    .textButtonStyle(font: Typo.sectionTitle)
                    .fixedSize()
                    .accessibilityLabel("New custom route")
                    .accessibilityIdentifier("newCustom")
            }
        default:
            EmptyView()
        }
    }

    /// "2 buses" / "Not running" (a scheduled route without a reporting bus is never "Not running": rider safety).
    func routeStatus(_ rid: String) -> String {
        let n = model.running(rid)
        if n > 0 { return "\(n) bus\(n == 1 ? "" : "es")" }
        if model.liveOutage { return "Status unknown" }
        if Operating.scheduledNoLive(rid, buses: model.buses, service: model.staticData.service, now: model.now) { return "No live location" }
        return "Not running"
    }
}

/// The next bus as one glance: a 20 pt badge, the ETA and the live dot (spec 10.6).
struct NextBusSummary: View {
    @Environment(AppModel.self) private var model
    let rid: String
    let t: Double
    let prefix: String
    var body: some View {
        let m = TimeFmt.minsUntil(t, from: model.now)
        let when: String = m < 1 ? "now" : (model.isStale ? "about " : "") + "\(m) min"
        let spoken: String = prefix + ": " + model.shortName(rid) + ", " + when + ", " + LiveText.liveLabel(model.staleLevel).spoken
        HStack(spacing: Space.s2) {
            RouteBadge(route: model.route(rid), rid: rid, size: .small)
            EtaView(t: t, now: model.now, stale: model.isStale)
            LiveDot(level: model.staleLevel)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// "Arriving In" over "12 min" (owner wording 2026-10-30, Kit `TripText.arrivingIn`): the walk on walking legs
/// ("Walk" over "2 min"), the estimate with "est.".
struct ArrivingIn: View {
    let text: String
    var body: some View {
        let parts = Self.split(text)
        VStack(alignment: .trailing, spacing: 0) {
            if let cap = parts.caption {
                Text(cap).font(Typo.caption).foregroundStyle(Palette.label2)
            }
            parts.value
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.replacingOccurrences(of: "Arriving In:", with: "Arriving in"))
        .accessibilityIdentifier("arrivingIn")
    }

    static func split(_ s: String) -> (caption: String?, value: Text) {
        func value(_ v: String) -> Text {
            if v.hasSuffix(" est.") {
                return Text(String(v.dropLast(5))).font(Typo.etaRow).foregroundStyle(Palette.label2)
                    + Text(" est.").font(Typo.footnote).foregroundStyle(Palette.label2)
            }
            let live = !v.hasPrefix("~")
            return Text(v).font(Typo.etaRow).foregroundStyle(v == "Now" && live ? Palette.live : live ? Palette.label : Palette.label2)
        }
        if s.hasPrefix("Arriving In: ") { return ("Arriving In", value(String(s.dropFirst("Arriving In: ".count)))) }
        if s.hasPrefix("Walk ") { return ("Walk", value(String(s.dropFirst(5)))) }
        return (nil, Text(s).font(Typo.rowDetail.weight(.semibold)).foregroundStyle(Palette.label2))
    }
}

/// The current page of the selected tab.
struct SheetContent: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        switch model.page {
        case .route(let rid): RouteDetailView(rid: rid)
        case .stop(let id): StopDetailView(stopId: id)
        case .customRoute(let id): CustomRouteDetailView(id: id)
        case .editCustom(let id): CustomRouteEditor(id: id)
        case .about: AboutView()
        case .directions: DirectionsView()
        case .alerts: AlertsView()
        case .pick: PickView()
        case nil:
            switch model.tab {
            case .current: CurrentTripView()
            case .routes: RoutesView()
            case .myroutes: MyRoutesView()
            }
        }
    }
}
