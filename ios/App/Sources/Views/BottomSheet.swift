import SwiftUI
import StraightBussingKit

/// Custom bottom sheet (the web's ui/sheet.js; docs/DESIGN-SPEC.md 10.6, docs/DESIGN-SPEC-GLASS.md 8.8), owner spec
/// 2026-10-12: two resting states. Collapsed it is an inset glass card floating above the bottom row (grab bar +
/// header, whose right side keeps the one-line answer such as the next bus), 12 pt from both sides with 28 pt corners;
/// expanded it is the opaque full-width `bgSheet` sheet of the first redesign, below the top rows, with the bottom row
/// floating over its end. Between the two the card turns opaque and full width by a third of the way (`mSheetGlass`:
/// an opaque layer fades in over the glass, the inset shrinks to 0; the body below the header fades in with it and
/// takes no taps while collapsed, so the map around the card stays usable). The lower-right group (Lines by Time,
/// Locate, the compass) rides 8 pt above the sheet's top edge and fades out by p 0.30 (`mRide`).
///
/// The whole header strip drags it (from just above the card's top edge through the grab bar and the header; a drag
/// that starts on Back still drags, a tap there still goes back). While the finger is down the sheet follows it 1:1
/// (rubber band past the ends); on release it goes the way the finger last moved (Kit `SheetMotion`). A tap on the
/// grab bar toggles, a tap on a collapsed header expands. The settle is a spring that starts at the finger's speed.
/// Laid out once at full height and slid with an offset; the content's bottom inset and the map padding (`onSettled`)
/// change only after the spring finishes, so nothing re-lays out while it moves. VoiceOver adjusts it (Collapsed /
/// Expanded); Reduce Motion: a 150 ms ease, no spring.
struct BottomSheet<Header: View, Content: View, Accessory: View>: View {
    @Binding var detent: Detent
    /// The expanded height: from 8 pt below the top rows to the bottom of the screen (or the keyboard).
    let available: CGFloat
    /// Room under the collapsed card: the floating bottom row, its inset and the 8 pt gap (0 while the keyboard is up).
    let bottomReserve: CGFloat
    var header: Header
    var content: Content
    /// What rides on the sheet's top trailing corner (the lower-right group).
    var accessory: Accessory
    /// The state the sheet came to rest in and its visible height from the bottom of the screen (the map padding
    /// follows it, RootView).
    var onSettled: (Detent, CGFloat) -> Void
    /// The content's bottom inset follows this, not `detent`: it changes after the spring has settled.
    @State private var insetDetent: Detent
    /// The header's measured height in the collapsed card: collapsed = grab bar + this, so large text keeps the header.
    @State private var headerH: CGFloat = Space.sheetHeaderMin
    /// Finger travel since the drag began (positive = down).
    @State private var drag: CGFloat = 0
    @State private var tracking = false
    @State private var motion = SheetMotion()
    /// The release spring (carries the finger's velocity) until it settles; nil = the default spring.
    @State private var settle: Animation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(detent: Binding<Detent>, available: CGFloat, bottomReserve: CGFloat = 0,
         onSettled: @escaping (Detent, CGFloat) -> Void = { _, _ in },
         @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        _detent = detent
        self.available = available
        self.bottomReserve = bottomReserve
        self.onSettled = onSettled
        self.header = header()
        self.content = content()
        self.accessory = accessory()
        _insetDetent = State(initialValue: detent.wrappedValue)
    }

    /// The expanded sheet: 28 pt top corners (`rGlass`); its bottom corners sit off screen.
    static var shape: UnevenRoundedRectangle { UnevenRoundedRectangle(topLeadingRadius: Radius.glass, topTrailingRadius: Radius.glass, style: .continuous) }
    /// The collapsed card: 28 pt on all four corners.
    static var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.glass, style: .continuous) }
    /// The grab bar's zone: 6 pt above the 5 pt bar, 5 under it.
    static var grabH: CGFloat { 16 }

    static func height(for d: Detent, available: CGFloat, headerH: CGFloat, reserve: CGFloat = 0) -> CGFloat {
        switch d {
        case .peek: return min(available, grabH + headerH + reserve)
        case .full: return available
        }
    }

    func h(_ d: Detent) -> CGFloat { Self.height(for: d, available: available, headerH: headerH, reserve: bottomReserve) }
    var defaultAnimation: Animation { reduceMotion ? Motion.reduced : Motion.sheet }

    /// How far the sheet is open: 0 collapsed, 1 expanded (follows the finger while it is down).
    static func progress(visible: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        guard high - low > 1 else { return 1 }
        return min(1, max(0, (visible - low) / (high - low)))
    }

    var body: some View {
        let low = h(.peek)
        let visible = CGFloat(SheetSnap.rubberBand(Double(h(detent) - drag), min: Double(low), max: Double(available)))
        let p = Self.progress(visible: visible, low: low, high: available)
        // the card turns opaque and full width by p 0.35; the lower-right group is gone by p 0.30
        let solid = min(1, p / 0.35)
        let inset = Space.insetChrome * (1 - solid)
        let ride = 1 - min(1, max(0, (p - 0.10) / 0.20))
        let anim = settle ?? defaultAnimation
        VStack(spacing: 0) {
            // the header strip: one hit shape over the card, from 14 pt above its edge down to the header's end
            VStack(spacing: 0) {
                grabber
                header
                    .environment(\.onGlass, true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { v in
                        // measured in the collapsed card (its width): an expanded header never moves the card's height
                        if solid == 0 && !tracking && abs(v - headerH) > 0.5 { headerH = v }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if detent == .peek { setDetent(.full) } }
            }
            .contentShape(TopExtendedRect(extra: 14))
            // wins over the buttons and the scroll view under it: a drag that starts anywhere on the strip moves the
            // sheet (a plain tap still reaches Back, Edit map order, New)
            .highPriorityGesture(stripDrag)
            .padding(.horizontal, inset)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // the part below the screen in the settled state, then the floating bottom row: every row can still
                // scroll into view above the tab bar
                .safeAreaPadding(.bottom, available - h(insetDetent) + (bottomReserve > 0 ? bottomReserve + Space.s3 : 0))
                .modifier(SoftBottomEdge())
                .contentShape(Rectangle())
                // collapsed: the body is not there (transparent, no taps, nothing to read); it fades in with the card
                .opacity(solid)
                .allowsHitTesting(solid > 0.05)
                .accessibilityHidden(solid == 0)
        }
        .frame(height: available, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(Self.shape)
        // the card's glass and the opaque sheet sit behind the clipped content: their shadows are never cut, and a
        // shadow on a filled shape is cheap on every drag frame (a shadow on content renders the sheet offscreen)
        .background(alignment: .top) { sheetBackground(solid: solid, inset: inset) }
        .overlay(alignment: .topTrailing) {
            accessory
                .padding(.trailing, Space.insetChrome)
                .alignmentGuide(.top) { d in d[.bottom] + Space.gapChrome }
                .opacity(ride)
                .allowsHitTesting(ride > 0.5)
                .accessibilityHidden(ride < 0.5)
        }
        .offset(y: available - visible)
        .animation(tracking ? nil : anim, value: drag)
        .animation(anim, value: detent)
        // what slides below the sheet's slot stays hidden (the screen edge); room above for the rubber band past
        // expanded and for the lower-right group
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
        .onChange(of: bottomReserve) { _, _ in if !tracking { onSettled(detent, h(detent)) } }
        .sensoryFeedback(.selection, trigger: detent)
    }

    /// Collapsed: the glass card (header height). Expanded: the opaque sheet with e2 (spec 8: light = a soft upward
    /// shadow plus a faint edge line; dark = a 0.5 pt light top border). In between the opaque layer fades in over
    /// the glass and both widen from the 12 pt inset to the screen's width.
    @ViewBuilder func sheetBackground(solid: CGFloat, inset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if solid < 1 {
                Color.clear
                    .frame(height: Self.grabH + headerH)
                    .sbGlass(in: Self.cardShape)
            }
            opaqueSheet.opacity(solid)
        }
        .padding(.horizontal, inset)
        .allowsHitTesting(false)
    }

    @ViewBuilder var opaqueSheet: some View {
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

    /// The grab bar: 36 x 5 in `labelGlass2` at 60% (it sits on glass when collapsed), 6 pt from the top (the strip
    /// around it drags too). A tap toggles.
    var grabber: some View {
        Capsule()
            .fill(Palette.labelGlass2.opacity(0.6))
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

/// The expanded sheet's end under the floating bottom row (spec 8.8): iOS 26 draws its soft scroll edge there; iOS 17
/// to 25 get a 24 pt fade from clear to `bgSheet` at 0.9 drawn by RootView behind the bar instead.
struct SoftBottomEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content
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

/// The sheet's header (spec 10.6, DESIGN-SPEC-GLASS 8.10): optional Back (a 44 pt `fill` circle with
/// `chevron.backward` in `label`), the title (`sheetTitle`, up to 2 lines), and one trailing summary or action (a
/// `fill` capsule: the header is the collapsed glass card, where tint text is not allowed). The collapsed header
/// carries the one-line answer (the next bus, the best option, the trip's current step with Arriving In), so the main
/// tasks work with the map visible. Secondary text in `labelGlass2`. A hairline appears under it when the content
/// scrolls under it.
struct SheetHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(SheetScroll.self) private var scroll
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let back = !model.path.isEmpty
        let trip = model.page == nil && model.tab == .current && model.activeTrip != nil ? model.tripFollow : nil
        Group {
            if typeSize.isAccessibilitySize {
                // accessibility sizes (spec 13.7): the title gets the whole width (never broken inside a word), the
                // summary or action goes under it
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(alignment: .center, spacing: Space.s2) {
                        if back { backButton }
                        title(trip, lines: 3)
                        Spacer(minLength: 0)
                    }
                    trailing(trip)
                        .padding(.leading, back ? Space.tap + Space.s2 : 0)
                }
                .padding(.vertical, Space.s1)
            } else {
                HStack(alignment: .center, spacing: Space.s2) {
                    if back { backButton }
                    title(trip, lines: 2)
                    Spacer(minLength: Space.s2)
                    trailing(trip)
                }
            }
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

    var backButton: some View {
        Button { model.back() } label: {
            Image(systemName: "chevron.backward").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.label)
                .frame(width: Space.tap, height: Space.tap)
                .background(Palette.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(ChromePressStyle())
        .accessibilityLabel("Back")
        .accessibilityIdentifier("backButton")
    }

    @ViewBuilder func title(_ trip: TripFollow?, lines: Int) -> some View {
        if let p = trip, model.detent == .peek {
            // a trip in progress, collapsed (spec 10.6, O3): the current step and the trip, Arriving In on the right
            let step = TripText.nowCard(p, routes: model.staticData.routes, now: model.now, you: model.tripYou).prim
            VStack(alignment: .leading, spacing: 2) {
                Text(step).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(lines)
                    .accessibilityIdentifier("sheetTitle")
                    .accessibilityAddTraits(.isHeader)
                Text("Trip to \(p.to)").font(Typo.rowDetail).foregroundStyle(Palette.labelGlass2).lineLimit(1)
            }
            .padding(.vertical, Space.s2)
        } else {
            Text(model.title)
                .font(Typo.sheetTitle)
                .foregroundStyle(Palette.label)
                .lineLimit(lines)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sheetTitle")
                .padding(.vertical, Space.s2)
        }
    }

    @ViewBuilder func trailing(_ trip: TripFollow?) -> some View {
        switch model.page {
        case .stop(let id):
            if let a = model.arrivals(at: id).first {
                NextBusSummary(rid: a.rid, t: a.t, prefix: "Next bus")
            }
        case .route(let rid):
            Text(routeStatus(rid)).font(Typo.rowDetail).foregroundStyle(Palette.labelGlass2).lineLimit(1).fixedSize()
        case .directions:
            if let r = model.dir.result, r.options.indices.contains(model.dir.selected) {
                let m = r.options[model.dir.selected].totalMin
                (Text("\(m) min").font(Typo.etaRow) + Text(" est.").font(Typo.footnote).foregroundStyle(Palette.labelGlass2))
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
                .buttonStyle(FillCapsuleStyle())
                .fixedSize()
        case nil where model.tab == .myroutes:
            if !model.routeState.customRoutes.isEmpty {
                Button { model.push(.editCustom(nil)) } label: {
                    Label("New", systemImage: "plus").labelStyle(.titleAndIcon)
                }
                    .buttonStyle(FillCapsuleStyle())
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
    @Environment(\.onGlass) private var onGlass
    var body: some View {
        let parts = Self.split(text, onGlass: onGlass)
        VStack(alignment: .trailing, spacing: 0) {
            if let cap = parts.caption {
                Text(cap).font(Typo.caption).foregroundStyle(Palette.secondary(onGlass: onGlass))
            }
            parts.value
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.replacingOccurrences(of: "Arriving In:", with: "Arriving in"))
        .accessibilityIdentifier("arrivingIn")
    }

    /// On glass (the collapsed card) secondary text is `labelGlass2` and "Now" is never green text (spec 5.3).
    static func split(_ s: String, onGlass: Bool = false) -> (caption: String?, value: Text) {
        let second = Palette.secondary(onGlass: onGlass)
        func value(_ v: String) -> Text {
            if v.hasSuffix(" est.") {
                return Text(String(v.dropLast(5))).font(Typo.etaRow).foregroundStyle(second)
                    + Text(" est.").font(Typo.footnote).foregroundStyle(second)
            }
            let live = !v.hasPrefix("~")
            return Text(v).font(Typo.etaRow).foregroundStyle(v == "Now" && live && !onGlass ? Palette.live : live ? Palette.label : second)
        }
        if s.hasPrefix("Arriving In: ") { return ("Arriving In", value(String(s.dropFirst("Arriving In: ".count)))) }
        if s.hasPrefix("Walk ") { return ("Walk", value(String(s.dropFirst(5)))) }
        return (nil, Text(s).font(Typo.rowDetail.weight(.semibold)).foregroundStyle(second))
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
