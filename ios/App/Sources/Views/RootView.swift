import Combine
import SwiftUI
import UIKit
import StraightBussingKit

/// The map screen (docs/DESIGN-SPEC.md 10.1 to 10.7, 10.19): the full-screen map; floating over it the search capsule
/// with Lines by Time and Settings (in Directions it turns into the Start / Destination card, in place), one status
/// banner when the feed needs a warning, the demo chip, the trip / filter chip and the locate button; the opaque bottom
/// sheet with two resting states (owner 2026-10-12) on the bottom bar; toasts just above the sheet.
struct RootView: View {
    @Environment(AppModel.self) private var model
    /// Measured height of the floating chrome the expanded sheet stays below (search bar or Directions card, status
    /// banner, demo chip): a long warning, large text or the Directions card makes it taller.
    @State private var chromeH: CGFloat = 48
    /// Measured height of the bottom bar (49 pt, more with larger text).
    @State private var tabH: CGFloat = Space.tabBar
    /// The keyboard is up: the bottom bar steps aside so the sheet keeps its room for suggestions.
    @State private var keyboardUp = false
    /// The sheet's settled visible height: the map's bottom padding follows it, so the map never re-centers while the
    /// sheet is still moving (owner 2026-10-12: no hitch).
    @State private var settledSheetH: CGFloat = 0
    /// Directions' typed text, focus and suggestions, shared by the top card and the sheet below it.
    @State private var dirUI = DirectionsUI()
    /// Whether the sheet's content has scrolled under its header (the header hairline, spec 10.6).
    @State private var sheetScroll = SheetScroll()
    @Namespace private var searchNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let inDirections = model.page == .directions
            // On the Routes list the list's own bar says the same thing with the same button (one action per intent).
            let chip = TripChip.shows(model) && model.detent != .full && !(model.tab == .routes && model.page == nil) && !inDirections
            let topReserved: CGFloat = Space.s2 + chromeH + Space.s2
            let barH: CGFloat = keyboardUp ? 0 : tabH
            let available = max(200, geo.size.height - barH - topReserved)
            // the trip chip sits under the measured chrome: the follow camera keeps you out from under it too
            let mapRects = MapRects.of(geo, chromeH: chromeH + (chip ? 36 + Space.gapChrome : 0), sheetH: settledSheetH, tabH: barH)
            let showLocate = model.detent != .full
            ZStack(alignment: .bottom) {
                // The inset is applied here, not passed in: MapScreen has no inputs, so a settled sheet only
                // relayouts the map instead of re-running its body.
                MapScreen()
                    .safeAreaPadding(.bottom, settledSheetH + barH)
                    .ignoresSafeArea()
                VStack(spacing: Space.gapChrome) {
                    VStack(spacing: Space.gapChrome) {
                        // the bar and the card are one element that changes shape (matchedGeometryEffect; Reduce
                        // Motion: a crossfade)
                        if inDirections {
                            DirectionsCard()
                                .modifier(SearchMorphEffect(ns: searchNS, on: !reduceMotion))
                                .transition(.opacity)
                        } else {
                            SearchBar()
                                .modifier(SearchMorphEffect(ns: searchNS, on: !reduceMotion))
                                .transition(.opacity)
                        }
                        StatusBanner()
                        if model.simulating {
                            HStack(alignment: .top, spacing: Space.gapChrome) {
                                DemoChip()
                                Spacer(minLength: 0)
                                if showLocate { LocateButton() }
                            }
                        }
                    }
                    .animation(Motion.pick(Motion.morph, reduce: reduceMotion), value: inDirections)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                        if abs(h - chromeH) > 0.5 { withAnimation(Motion.quick) { chromeH = h } }
                    }
                    if chip || (showLocate && !model.simulating) {
                        HStack(alignment: .top, spacing: Space.gapChrome) {
                            if chip { TripChip() }
                            Spacer(minLength: 0)
                            if showLocate && !model.simulating { LocateButton() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.insetChrome)
                .padding(.top, Space.s2)
                // pinned to the screen's width: a too-wide child (very large text) can never widen its siblings
                .frame(width: geo.size.width)
                VStack(spacing: 0) {
                    BottomSheet(detent: $model.detent, available: available, onSettled: { d, h in
                        if abs(h - settledSheetH) > 0.5 {
                            settledSheetH = h
                            model.sheetSettled(d)
                        }
                    }) {
                        SheetHeader()
                    } content: {
                        SheetContent()
                    }
                    if !keyboardUp {
                        TabBar()
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                                if abs(h - tabH) > 0.5 { tabH = h }
                            }
                    }
                }
                .frame(width: geo.size.width)
            }
            // just above the collapsed sheet, or above the bottom bar when the sheet is expanded; never over the search
            // bar, the sheet title or Settings (spec 10.19)
            .overlay(alignment: .bottom) {
                ToastBanner()
                    .padding(.horizontal, Space.insetChrome)
                    .padding(.bottom, (model.detent == .peek ? settledSheetH : 0) + barH + Space.s3)
            }
            // the trip's follow camera keeps its frame inside what the rider can see of the map
            .onChange(of: mapRects, initial: true) { _, r in
                let cam = model.mapCamera
                cam.safeRect = r.safe
                if cam.visibleRect != r.visible { cam.visibleRect = r.visible }
            }
        }
        .environment(dirUI)
        .environment(sheetScroll)
        .onChange(of: model.page) { _, _ in sheetScroll.scrolled = false }
        // a light tap when a trip starts or ends (spec 9: Start), none for live updates
        .sensoryFeedback(.impact(weight: .light), trigger: model.activeTrip != nil)
        .onChange(of: model.tab) { _, _ in sheetScroll.scrolled = false }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .onChange(of: model.mapCovered) { _, _ in model.mapCoverChanged() }   // no bus glides behind a sheet
        .sheet(isPresented: $model.showTimePick) { TimePickView(start: model.routeState.timeView?.at ?? Date().timeIntervalSince1970) }
        .sheet(isPresented: $model.showLiveActivityPreview) {
            NavigationStack { LiveActivityPreviewView() }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible, presenting: model.confirmDelete) { c in
            Button("Delete", role: .destructive) { model.deleteCustomConfirmed(c) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This custom route will be removed from My Routes. This can\u{2019}t be undone.")
        }
        // the rider asked for their location and it is off: one tap to the switch in iOS Settings
        .alert("Location is off", isPresented: $model.showLocationOff) {
            Button("Open Settings") { AppModel.openAppSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To see stops near you and walk from where you are, allow location for Straight Bussing in iOS Settings. It stays on your iPhone.")
        }
    }

    var deleteTitle: String { "Delete \u{201C}\(model.confirmDelete?.name ?? "")\u{201D}?" }
    var deleteBinding: Binding<Bool> {
        Binding(get: { model.confirmDelete != nil }, set: { if !$0 { model.confirmDelete = nil } })
    }
}

/// Whether the expanded sheet's content has scrolled under its header: the header shows a hairline then (spec 10.6).
@MainActor @Observable
final class SheetScroll {
    var scrolled = false
}

extension View {
    /// Report this scroll view's offset to the sheet header (iOS 18+; on iOS 17 the hairline stays off). With
    /// `-scrollend` (CI) the page opens scrolled to its end.
    func reportsSheetScroll() -> some View { modifier(SheetScrollReporter()) }
}

struct SheetScrollReporter: ViewModifier {
    @Environment(SheetScroll.self) private var scroll
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        reporting(content.defaultScrollAnchor(model.config.scrollEnd ? .bottom : nil))
    }

    @ViewBuilder func reporting(_ content: some View) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self, of: { g in g.contentOffset.y + g.contentInsets.top > 1 }) { _, v in
                if scroll.scrolled != v { scroll.scrolled = v }
            }
        } else {
            content
        }
    }
}

/// The search bar and the Directions card are one element that changes shape (owner 2026-10-12, like Google Maps):
/// a matched geometry between them; Reduce Motion: none (they crossfade).
struct SearchMorphEffect: ViewModifier {
    let ns: Namespace.ID
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.matchedGeometryEffect(id: "searchCard", in: ns) } else { content }
    }
}

/// Floating search capsule (spec 10.1): 48 tall, system material, the magnifier and "Search for a destination" in
/// `label2`, then Lines by Time and Settings as 44 pt icon buttons. A tap opens Directions: the capsule turns into the
/// Start / Destination card in place, keyboard on Destination. Text stops growing at xxxLarge; at accessibility sizes
/// the placeholder shortens to "Search".
struct SearchBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The search part is held down: the whole capsule takes `fillPressed` over its material (spec 10.1).
    @State private var pressed = false
    var body: some View {
        HStack(spacing: 0) {
            Button { model.dirActiveTo = true; model.openDirections() } label: {
                HStack(spacing: Space.s3) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(Palette.label2)
                        .accessibilityHidden(true)
                    Text(typeSize.isAccessibilitySize ? "Search" : "Search for a destination")
                        .font(Typo.body).foregroundStyle(Palette.label2).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Space.insetContent)
                .frame(minHeight: Space.searchHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(CapsulePressStyle(pressed: $pressed))
            .accessibilityIdentifier("searchBar")
            .accessibilityLabel("Search for a destination")
            Button { model.showTimePick = true } label: {
                Image(systemName: "clock").font(.title3).foregroundStyle(Palette.label).frame(width: Space.tap, height: Space.tap)
            }
            .buttonStyle(ChromePressStyle())
            .accessibilityIdentifier("timeButton")
            .accessibilityLabel("Lines by Time")
            .accessibilityHint("Check which lines the timetable has running at a time you pick")
            .accessibilityShowsLargeContentViewer { Label("Lines by Time", systemImage: "clock") }
            Button { model.showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).foregroundStyle(Palette.label).frame(width: Space.tap, height: Space.tap)
            }
            .buttonStyle(ChromePressStyle())
            .accessibilityIdentifier("settingsButton")
            .accessibilityLabel("Settings")
            .accessibilityShowsLargeContentViewer { Label("Settings", systemImage: "gearshape") }
            .padding(.trailing, 2)
        }
        .frame(minHeight: Space.searchHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().fill(pressed ? Palette.fillPressed : Color.clear).allowsHitTesting(false) }
        .animation(Motion.press, value: pressed)
        .elevation(.floating, in: Capsule())
        // map chrome: grows with text size, but not so far that it hides the map (the sheet holds the content)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The search capsule's press: reports the pressed state so the whole capsule, not only the text, takes the tint.
struct CapsulePressStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, v in pressed = v }
    }
}

/// Press feedback on floating chrome: opacity .6 (text and icon buttons, spec 9 `mPress`).
struct ChromePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// The status banner (spec 10.3; web main.js renderPill): stale or failed live data is always flagged and a fresh empty
/// feed says whether the schedule has routes in service (ship checklist item 1). One banner at a time, full width,
/// opaque `warnBg` (delayed, out of date, no live locations, no shuttles) or `dangerBg` (unreachable), same words as
/// the web, the first sentence Semibold. A change is announced once.
///
/// Its action (Retry, See alert) sits on the LEADING side in a fixed slot (owner 2026-11-03: "move the retry button to
/// the left side of the notification so if the user spams it while on a route, it doesn't shift and accidentally cancel
/// their current trip"): the slot has a fixed size and sits at the banner's top-leading corner, so neither a text
/// change nor a state change moves it; while a Retry poll runs it shows progress in the same place; when the feed
/// comes back right after a tap the banner keeps its place for 2.5 s after the last tap ("Live data is back.", taps
/// absorbed; Kit `RetryHold`), so the trip chip with its Show all (which ends the trip) and the sheet cannot slide up
/// under the finger. On the leading side a missed tap lands on the chip's label, never on its trailing Show all.
struct StatusBanner: View {
    @Environment(AppModel.self) private var model
    /// The live banner's last height: the held banner keeps it, so nothing below moves when the feed comes back.
    @State private var liveHeight: CGFloat = 0
    /// The action slot: a fixed size (scales with Dynamic Type, never with the text or the state).
    @ScaledMetric(relativeTo: .subheadline) private var slotW: CGFloat = 84

    var body: some View {
        let _ = model.retryHoldTick   // the hold ended: look again
        if !model.simulating, let s = model.retryHold.shown(model.statusPill, now: Date().timeIntervalSince1970) {
            banner(s)
        }
    }

    @ViewBuilder func banner(_ s: RetryHold.Shown) -> some View {
        let p = s.pill
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let hasSlot = p.retry || p.alert
        let parts = s.recovered ? (lead: "Live data is back.", rest: "") : Self.split(p.text)
        HStack(alignment: .top, spacing: Space.s3) {
            if hasSlot { slot(s).frame(width: min(slotW, 120), height: Space.tap) }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Image(systemName: s.recovered ? "checkmark.circle.fill" : icon(p))
                    .font(.system(size: IconSize.status, weight: .semibold))
                    .foregroundStyle(s.recovered ? Palette.live : p.kind == .err ? Palette.danger : Palette.warn)
                    .accessibilityHidden(true)
                (Text(parts.lead).fontWeight(.semibold) + Text(parts.rest.isEmpty ? "" : " " + parts.rest))
                    .font(Typo.rowDetail).foregroundStyle(Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, hasSlot ? Space.s3 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityHidden(s.recovered && hasSlot)   // the slot says it then
            Spacer(minLength: 0)
        }
        .padding(.leading, hasSlot ? Space.s1 : Space.insetContent)
        .padding(.trailing, Space.insetContent)
        .padding(.vertical, hasSlot ? 0 : Space.s3)
        .frame(maxWidth: .infinity, minHeight: s.recovered ? max(Space.tap, liveHeight) : Space.tap, alignment: .topLeading)
        .background(s.recovered ? Palette.chromeSolid : p.kind == .err ? Palette.dangerBg : Palette.warnBg, in: shape)
        .contentShape(shape)
        // the held banner absorbs taps (each extends the hold) instead of letting them reach what is under it
        .onTapGesture { if s.recovered { model.retryFeed() } }
        .elevation(.floating, in: shape)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
            if !s.recovered && abs(h - liveHeight) > 0.5 { liveHeight = h }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusPill")
        .onAppear { AccessibilityNotification.Announcement(s.recovered ? parts.lead : p.text).post() }
        .onChange(of: s) { _, v in AccessibilityNotification.Announcement(v.recovered ? "Live data is back." : v.pill.text).post() }
    }

    /// The fixed leading slot: Retry (progress while its poll runs), See alert, or, once the feed is back, a check mark
    /// in the same button frame whose tap only keeps the banner in place (no poll).
    @ViewBuilder func slot(_ s: RetryHold.Shown) -> some View {
        let p = s.pill
        if s.recovered {
            // the same control in the same place: a tap only keeps the banner (retryFeed polls nothing then)
            Button { model.retryFeed() } label: {
                Image(systemName: "checkmark").font(.system(size: IconSize.status, weight: .semibold)).foregroundStyle(Palette.live)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChromePressStyle())
            .accessibilityLabel("Live data is back")
            .accessibilityIdentifier("bannerRetry")
        } else if p.retry {
            Button { model.retryFeed() } label: {
                ZStack {
                    if model.retrying {
                        ProgressView().controlSize(.small).tint(Palette.tint)
                    } else {
                        Text("Retry").lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .font(Typo.sectionTitle)
                .foregroundStyle(Palette.tint)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Palette.bgCard, in: Capsule())
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(ChromePressStyle())
            .accessibilityLabel(model.retrying ? "Retrying" : "Retry loading live data")
            .accessibilityIdentifier("bannerRetry")
        } else if p.alert {
            // no bus is reporting and the operator posted an alert: it may say why (rider safety)
            Button { model.openAlerts() } label: {
                Text("See alert").lineLimit(1).minimumScaleFactor(0.8)
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.tint)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Palette.bgCard, in: Capsule())
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChromePressStyle())
            .accessibilityLabel("Read the service alert")
            .accessibilityIdentifier("pillAlert")
        }
    }

    /// The first sentence (Semibold) and the rest.
    static func split(_ s: String) -> (lead: String, rest: String) {
        guard let r = s.range(of: ". ") else { return (s, "") }
        return (String(s[..<r.lowerBound]) + ".", String(s[r.upperBound...]))
    }

    func icon(_ p: LiveText.Pill) -> String {
        switch p.kind {
        case .err: return Sym.feedError
        case .warn: return model.staleLevel == .fresh ? Sym.noLive : Sym.delayed
        case .info: return "bus"
        }
    }
}

/// "Simulated buses" (spec 10.3 chip): the Settings switch is on (never in `-demo`). Quiet, yet never mistaken for live
/// service (the flask and the words); a tap opens Settings at the switch to turn it off.
struct DemoChip: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.openSimulatedSetting() } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: Sym.simulated).font(.system(size: IconSize.inline, weight: .semibold)).accessibilityHidden(true)
                Text(AppModel.simulatedPillText).font(Typo.footnote.weight(.semibold)).lineLimit(1)
                Image(systemName: "info.circle").font(.system(size: IconSize.inline, weight: .semibold)).foregroundStyle(Palette.tint)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.label)
            .padding(.horizontal, Space.s3)
            .frame(minHeight: 32)
            .background(.regularMaterial, in: Capsule())
            .elevation(.floating, in: Capsule())
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChromePressStyle())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("Simulated buses, not real shuttles")
        .accessibilityHint("Opens Settings to turn simulated buses off")
        .accessibilityIdentifier("simulatedPill")
    }
}

/// The trip and filter chip (spec 10.5, web ui/contextbar.js): why the map shows fewer routes than usual, with a
/// one-tap way out. Route badges (up to 3, then "+N"), the label, then Show all / Clear. Only the label truncates.
struct TripChip: View {
    @Environment(AppModel.self) private var model
    static let maxBadges = 3

    static func shows(_ m: AppModel) -> Bool {
        (m.routeState.journey.map { !$0.rids.isEmpty } ?? false) || m.routeState.timeView != nil
            || RouteVisibility.activeCustomRoute(m.routeState) != nil
    }

    var body: some View {
        let s = model.routeState
        if let j = s.journey, !j.rids.isEmpty {
            let label = j.kind == .plan ? "Trip to \(model.activeTrip?.label ?? j.label)" : "Routes to \(j.label)"
            chip(rids: j.rids, label: label, action: "Show all", spoken: "Only showing routes for \(label)",
                 hint: "Shows every route on the map again") { model.endJourney() }
        } else if let tv = s.timeView {
            chip(rids: tv.rids, label: tv.name, action: "Clear", spoken: "Showing \(tv.name)",
                 hint: "Clear \(tv.name), show your usual routes") { model.apply(Custom.clearTimeView(model.routeState)) }
        } else if let c = RouteVisibility.activeCustomRoute(s) {
            chip(rids: c.rids, label: c.name, action: "Clear", spoken: "My route: \(c.name)",
                 hint: "Clear my route \(c.name), show your usual routes") { model.apply(Custom.clearCustom(model.routeState)) }
        }
    }

    func chip(rids all: [String], label: String, action: String, spoken: String, hint: String, run: @escaping () -> Void) -> some View {
        let rids = all.filter { model.route($0) != nil }
        return HStack(spacing: Space.s2) {
            HStack(spacing: 2) {
                ForEach(rids.prefix(Self.maxBadges), id: \.self) { RouteBadge(route: model.route($0), rid: $0, size: .small) }
                if rids.count > Self.maxBadges {
                    Text("+\(rids.count - Self.maxBadges)").font(Typo.caption).foregroundStyle(Palette.label2).padding(.leading, 2)
                }
            }
            .fixedSize()
            .accessibilityHidden(true)
            Text(label).font(Typo.footnote.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                .accessibilityLabel(spoken)
            Button(action, action: run)
                .font(Typo.footnote.weight(.semibold))
                .foregroundStyle(Palette.tint)
                .padding(.horizontal, Space.s2)
                .frame(minHeight: 36)
                .contentShape(Rectangle().inset(by: -4))
                .fixedSize()
                .accessibilityHint(hint)
        }
        .padding(.leading, Space.s3)
        .padding(.trailing, Space.s1)
        .frame(minHeight: 36)
        .background(.regularMaterial, in: Capsule())
        .elevation(.floating, in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contextBar")
    }
}

/// Toast (spec 10.19): bus alerts when system notifications are not allowed, and short confirmations. A capsule in
/// `bgInverse` just above the sheet, up to 2 lines; a tap dismisses it; read out.
struct ToastBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let transition: AnyTransition = reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        VStack(spacing: 0) {
            if let text = model.toast {
                Button { model.dismissToast() } label: {
                    HStack(alignment: .center, spacing: Space.s2) {
                        Image(systemName: model.toastIcon).font(.system(size: IconSize.inline, weight: .semibold)).accessibilityHidden(true)
                        Text(text).font(Typo.rowDetail.weight(.semibold)).multilineTextAlignment(.leading).lineLimit(2)
                    }
                    .foregroundStyle(Palette.labelInverse)
                    .padding(.horizontal, Space.s5)
                    .padding(.vertical, Space.s3)
                    .frame(minHeight: Space.tap)
                    .frame(maxWidth: 360)
                    .background(Palette.bgInverse, in: Capsule())
                    .elevation(.overlay, in: Capsule())
                }
                .buttonStyle(ChromePressStyle())
                .accessibilityLabel(text)
                .accessibilityHint("Dismisses the message")
                .accessibilityIdentifier("busAlertBanner")
                .transition(transition)
            }
        }
        .animation(reduceMotion ? Motion.quick : Motion.standard, value: model.toast)
    }
}

/// Locate button (spec 10.4): a 44 pt circle of system material; `location`, filled while the trip camera follows
/// you; during a trip a tap re-centers on you. Denied location: the button stays and opens the way to iOS Settings.
struct LocateButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let trip = model.activeTrip != nil
        let following = trip && model.mapCamera.follow
        Button {
            if trip { model.recenterTrip(); return }
            if model.locState == .denied && !model.config.demo { model.showLocationOff = true; return }
            model.locate()
        } label: {
            Image(systemName: following ? "location.fill" : "location")
                .font(.system(size: IconSize.row, weight: .medium))
                .foregroundStyle(Palette.tint)
                .frame(width: Space.tap, height: Space.tap)
                .background(.regularMaterial, in: Circle())
                .elevation(.floating, in: Circle())
        }
        .buttonStyle(ChromePressStyle())
        .accessibilityLabel(trip ? "Show me on my trip" : "Show my location")
        .accessibilityValue(trip ? (following ? "Following the trip" : "Not following") : "")
        .accessibilityIdentifier("locateButton")
        .accessibilityShowsLargeContentViewer { Label("Show my location", systemImage: "location") }
    }
}

/// Bottom bar (spec 10.7): Current trip / Routes / My Routes, equal width, opaque `bgSheet` with a hairline on top. The
/// selected item is the filled glyph and `tint` for icon and label (and the selected trait), never a capsule indicator.
/// Labels stop growing at xxxLarge; touch and hold shows the large content viewer.
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                let on = model.tab == t
                Button { model.select(t) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: on ? t.iconSelected : t.icon)
                            .font(.system(size: 21, weight: .regular))
                            .frame(height: 26)
                        Text(t.title).font(Typo.tabLabel).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: Space.tabBar)
                    .foregroundStyle(on ? Palette.tint : Palette.label2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityIdentifier("tab.\(t.rawValue)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityShowsLargeContentViewer {
                    Label(t.title, systemImage: on ? t.iconSelected : t.icon)
                }
            }
        }
        .padding(.top, 1)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Palette.bgSheet, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.separator).frame(height: 1 / max(1, displayScale)).accessibilityHidden(true)
        }
    }
}

extension AppModel {
    /// This app's page in iOS Settings (location, notifications).
    static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
