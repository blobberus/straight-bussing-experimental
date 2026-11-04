import Combine
import MapKit
import SwiftUI
import UIKit
import StraightBussingKit

/// The map screen in the glass layout (docs/DESIGN-SPEC-GLASS.md 3, the Apple Maps structure): the full-screen map
/// under everything; the top rows (Row A the status banner when the feed needs a warning, Row B the demo chip and the
/// Settings circle, Row C the trip / filter chip); the sheet (an inset glass card when collapsed, the opaque sheet
/// when expanded) with the lower-right group (Lines by Time over Locate, the compass while the map is rotated) riding
/// on it; the floating bottom row (the glass tab bar and the search circle); toasts just above the card. The map draws
/// under every glass element.
struct RootView: View {
    @Environment(AppModel.self) private var model
    /// Measured height of Row A + Row B (status banner, demo chip, Settings): the expanded sheet starts 8 pt below
    /// them, so a long warning or large text pushes it down instead of covering it.
    @State private var chromeH: CGFloat = Space.chromeButton
    /// Measured height of the tab bar capsule (56).
    @State private var tabH: CGFloat = Space.tabBarH
    /// The keyboard is up: the bottom row steps aside so the sheet keeps its room for suggestions.
    @State private var keyboardUp = false
    /// The sheet's settled visible height, from the bottom of the screen: the map's bottom padding follows it, so the
    /// map never re-centers while the sheet is still moving (owner 2026-10-12: no hitch).
    @State private var settledSheetH: CGFloat = 0
    /// Directions' typed text, focus and suggestions, shared by the card at the top of the sheet and the results.
    @State private var dirUI = DirectionsUI()
    /// Whether the sheet's content has scrolled under its header (the header hairline, spec 10.6).
    @State private var sheetScroll = SheetScroll()
    /// The map's scope: the compass in the lower-right group belongs to the map (MapKit draws no second one).
    @Namespace private var mapNS
    /// Settings and Lines by Time open out of their buttons (`mZoomSheet`, iOS 18 and later).
    @Namespace private var zoomNS
    /// The tab bar's glass and its minimized circle are one glass element (iOS 26 morphs one into the other).
    @Namespace private var glassNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let safeBottom = geo.safeAreaInsets.bottom
            // the sheet and the bottom row reach the screen's bottom edge; with the keyboard up they stop at it
            let ext: CGFloat = keyboardUp ? 0 : safeBottom
            let rowInset = Space.bottomRowInset(safeBottom: safeBottom)
            // under the collapsed card: the bottom row, its inset and the 8 pt gap
            let reserve: CGFloat = keyboardUp ? 0 : rowInset + tabH + Space.gapChrome
            let expanded = model.detent == .full
            let inDirections = model.page == .directions
            // On the Routes list the list's own bar says the same thing with the same button (one action per intent).
            let chip = TripChip.shows(model) && !expanded && !(model.tab == .routes && model.page == nil) && !inDirections
            let available = max(200, geo.size.height + ext - (Space.s2 + chromeH + Space.gapChrome))
            // the trip chip sits under the top rows and the group at the trailing edge: the follow camera keeps you clear
            let mapRects = MapRects.of(geo, topH: chromeH + (chip ? 36 + Space.gapChrome : 0), sheetH: settledSheetH,
                                       trailing: expanded ? 0 : Space.insetChrome + Space.chromeButton + Space.s1)
            ZStack(alignment: .top) {
                // The inset is applied here, not passed in: MapScreen's only input never changes, so a settled sheet
                // only relayouts the map instead of re-running its body.
                MapScreen(scope: mapNS)
                    .safeAreaPadding(.bottom, settledSheetH)
                    .ignoresSafeArea()
                BottomSheet(detent: $model.detent, available: available, bottomReserve: reserve, onSettled: { _, h in
                    if abs(h - settledSheetH) > 0.5 { settledSheetH = h }
                }) {
                    SheetHeader()
                } content: {
                    SheetContent()
                } accessory: {
                    MapControls(mapScope: mapNS, zoomNS: zoomNS)
                }
                // pinned to the screen's width: a too-wide child (very large text) can never widen its siblings
                .frame(width: geo.size.width, height: available)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(keyboardUp ? SafeAreaRegions() : .container, edges: .bottom)
                .accessibilitySortPriority(2)
                if expanded && !keyboardUp {
                    BottomFade(height: rowInset + tabH + 24)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
                topRows(chip: chip, width: geo.size.width)
                    .frame(width: geo.size.width)
                    .accessibilitySortPriority(3)
                if !keyboardUp {
                    bottomRow(narrow: geo.size.width < 360, minimized: expanded && sheetScroll.minimized)
                        .padding(.bottom, rowInset)
                        .frame(width: geo.size.width)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(materialize)
                        .accessibilitySortPriority(1)
                }
            }
            .animation(Motion.pick(Motion.materialize, reduce: reduceMotion), value: keyboardUp)
            // collapsed: leading, 12 above the card, never under the lower-right group; expanded: centered 12 above the
            // tab bar; never over the status banner (DESIGN-SPEC-GLASS 8.13)
            .overlay(alignment: expanded ? .bottom : .bottomLeading) {
                ToastBanner()
                    .frame(maxWidth: expanded ? 360 : max(160, geo.size.width - 2 * Space.insetChrome - Space.chromeButton - Space.gapChrome),
                           alignment: expanded ? .center : .leading)
                    .padding(.horizontal, Space.insetChrome)
                    .padding(.bottom, max(0, (expanded ? reserve - Space.gapChrome : settledSheetH) + Space.s3 - ext))
            }
            // the trip's follow camera keeps its frame inside what the rider can see of the map
            .onChange(of: mapRects, initial: true) { _, r in
                let cam = model.mapCamera
                cam.safeRect = r.safe
                if cam.visibleRect != r.visible { cam.visibleRect = r.visible }
            }
        }
        .mapScope(mapNS)
        .environment(dirUI)
        .environment(sheetScroll)
        .onChange(of: model.page) { _, _ in sheetScroll.reset() }
        // a light tap when a trip starts or ends (spec 9: Start), none for live updates
        .sensoryFeedback(.impact(weight: .light), trigger: model.activeTrip != nil)
        .onChange(of: model.tab) { _, _ in sheetScroll.reset() }
        // collapsing Directions frames the selected option again once the sheet has settled (AppModel.sheetCollapsed);
        // a collapsed sheet has no scrolled content, so the tab bar comes back
        .onChange(of: model.detent) { _, d in
            if d == .peek {
                sheetScroll.reset()
                model.sheetCollapsed()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .sheet(isPresented: $model.showSettings) { SettingsView().sbZoomFrom("settings", in: zoomNS) }
        .onChange(of: model.mapCovered) { _, _ in model.mapCoverChanged() }   // no bus glides behind a sheet
        .sheet(isPresented: $model.showTimePick) {
            TimePickView(start: model.routeState.timeView?.at ?? Date().timeIntervalSince1970)
                .sbZoomFrom("timePick", in: zoomNS)
        }
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

    /// Glass controls appearing and leaving (`mMaterialize`: scale .85 + fade; Reduce Motion: a fade).
    var materialize: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }

    /// Row A (the status banner, opaque, Retry on its leading side), Row B (the demo chip leading, the Settings circle
    /// trailing), Row C (the trip / filter chip, hidden while the sheet is expanded). Under a held banner Rows B and C
    /// keep their place (owner 2026-11-03).
    @ViewBuilder func topRows(chip: Bool, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.gapChrome) {
            VStack(spacing: Space.gapChrome) {
                StatusBanner()
                HStack(alignment: .center, spacing: Space.gapChrome) {
                    if model.simulating { DemoChip().transition(materialize) }
                    Spacer(minLength: 0)
                    SettingsButton(zoomNS: zoomNS)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                if abs(h - chromeH) > 0.5 { withAnimation(Motion.quick) { chromeH = h } }
            }
            if chip {
                TripChip()
                    .frame(maxWidth: max(160, width - 2 * Space.insetChrome - Space.chromeButton - Space.gapChrome), alignment: .leading)
                    .transition(materialize)
            }
        }
        .animation(Motion.pick(Motion.materialize, reduce: reduceMotion), value: chip)
        .animation(Motion.pick(Motion.materialize, reduce: reduceMotion), value: model.simulating)
        .padding(.horizontal, Space.insetChrome)
        .padding(.top, Space.s2)
    }

    /// The bottom row: the glass tab bar from the leading inset to 8 pt before the 56 pt search circle (one glass
    /// container, so on iOS 26 they sample the map together). Minimized (8.9), the bar is a 56 pt circle with the
    /// section's filled glyph at the leading side (on iOS 26 the capsule morphs into it, `mMinimize`; Reduce Motion: a
    /// crossfade); the search circle stays.
    @ViewBuilder func bottomRow(narrow: Bool, minimized: Bool) -> some View {
        let swap: AnyTransition = reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .leading).combined(with: .opacity)
        HStack(alignment: .center, spacing: Space.gapChrome) {
            if minimized {
                MinimizedTabBar { sheetScroll.minimized = false }
                    .sbGlassID("tabs", in: glassNS)
                    .transition(swap)
                Spacer(minLength: 0)
            } else {
                TabBar(narrow: narrow)
                    .sbGlassID("tabs", in: glassNS)
                    .transition(swap)
            }
            SearchCircle()
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
            if abs(h - tabH) > 0.5 { tabH = h }
        }
        .sbGlassContainer(spacing: Space.gapChrome)
        .animation(Motion.pick(Motion.minimize, reduce: reduceMotion), value: minimized)
        .padding(.horizontal, Space.insetChrome)
    }

    var deleteTitle: String { "Delete \u{201C}\(model.confirmDelete?.name ?? "")\u{201D}?" }
    var deleteBinding: Binding<Bool> {
        Binding(get: { model.confirmDelete != nil }, set: { if !$0 { model.confirmDelete = nil } })
    }
}

/// Under the floating bottom row of the expanded sheet, iOS 17 to 25 only (iOS 26 draws the soft scroll edge, spec
/// 8.8): `bgSheet` from clear to 0.9 over 24 pt, then 0.9 to the screen's edge, so rows scrolling under the bar never
/// fight its labels. Takes no taps.
struct BottomFade: View {
    let height: CGFloat
    var body: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            let edge = height > 0 ? min(1, 24 / height) : 0
            LinearGradient(stops: [
                .init(color: Palette.bgSheet.opacity(0), location: 0),
                .init(color: Palette.bgSheet.opacity(0.9), location: edge),
                .init(color: Palette.bgSheet.opacity(0.9), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Settings (DESIGN-SPEC-GLASS 8.2): a 44 pt glass circle at the top right, alone (rare, and riders know it there).
/// Settings opens out of it (iOS 18 and later).
struct SettingsButton: View {
    @Environment(AppModel.self) private var model
    let zoomNS: Namespace.ID
    var body: some View {
        Button { model.showSettings = true } label: {
            Image(systemName: "gearshape").font(.system(size: 20, weight: .regular))
        }
        .buttonStyle(GlassCircleStyle())
        .sbZoomSource("settings", in: zoomNS)
        .accessibilityIdentifier("settingsButton")
        .accessibilityLabel("Settings")
        .accessibilityShowsLargeContentViewer { Label("Settings", systemImage: "gearshape") }
    }
}

/// The lower-right group (DESIGN-SPEC-GLASS 8.4, Apple Maps' Map Modes over location): one 44 x 88 glass capsule with
/// Lines by Time (`clock`) on top and Locate below, a hairline between them; the map's compass 8 pt above it while
/// the map is rotated (a tap turns north up). Rides on the sheet (BottomSheet's accessory).
struct MapControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let mapScope: Namespace.ID
    let zoomNS: Namespace.ID
    var body: some View {
        VStack(spacing: 0) {
            Button { model.showTimePick = true } label: {
                Image(systemName: "clock").font(.system(size: 20, weight: .regular)).foregroundStyle(Palette.label)
                    .frame(width: Space.chromeButton, height: Space.chromeButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChromePressStyle())
            .sbZoomSource("timePick", in: zoomNS)
            .accessibilityIdentifier("timeButton")
            .accessibilityLabel("Lines by Time")
            .accessibilityHint("Check which lines the timetable has running at a time you pick")
            .accessibilityShowsLargeContentViewer { Label("Lines by Time", systemImage: "clock") }
            Rectangle().fill(Palette.separator)
                .frame(height: 1 / max(1, displayScale))
                .padding(.horizontal, Space.s2)
                .accessibilityHidden(true)
            LocateButton()
        }
        .frame(width: Space.chromeButton)
        .sbGlass(in: Capsule(), interactive: true)
        .overlay(alignment: .top) {
            MapCompass(scope: mapScope)
                .alignmentGuide(.top) { d in d[.bottom] + Space.gapChrome }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Search (DESIGN-SPEC-GLASS 8.7): a 56 pt glass circle at the trailing end of the bottom row, the magnifier in
/// `label`, named "Search for a destination". A tap opens Directions with the sheet expanded and the keyboard on
/// Destination (the Directions card sits at the top of the sheet); in Directions already, it goes back to typing the
/// destination.
struct SearchCircle: View {
    @Environment(AppModel.self) private var model
    @Environment(DirectionsUI.self) private var ui
    var body: some View {
        Button {
            if model.page == .directions {
                if model.detent == .peek { model.detent = .full }
                ui.focus = .to
            } else {
                model.dirActiveTo = true
                model.openDirections()
            }
        } label: {
            Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .medium))
        }
        .buttonStyle(GlassCircleStyle(size: Space.searchButton))
        .accessibilityIdentifier("searchBar")
        .accessibilityLabel("Search for a destination")
        .accessibilityShowsLargeContentViewer { Label("Search for a destination", systemImage: "magnifyingglass") }
    }
}

/// Whether the expanded sheet's content has scrolled under its header: the header shows a hairline then (spec 10.6).
/// And whether the tab bar is minimized (DESIGN-SPEC-GLASS 8.9, iOS 26's tab bar, iOS 18 and later): scrolling the
/// content down past 24 pt shrinks it to a circle with the section's glyph; scrolling back up 16 pt, reaching the top,
/// a tap on the circle, or a new page, tab or collapse restores it. Never while VoiceOver runs (every tab stays one
/// swipe away).
@MainActor @Observable
final class SheetScroll {
    var scrolled = false
    var minimized = false
    /// The furthest offset in the current direction (down while restored, up while minimized).
    @ObservationIgnored private var turn: CGFloat = 0

    /// The content's offset from its top, clamped to its end (a bounce at the end is not a turn).
    func offset(_ y: CGFloat) {
        if y <= 24 || UIAccessibility.isVoiceOverRunning {
            turn = y
            if minimized { minimized = false }
            return
        }
        if minimized {
            turn = max(turn, y)
            if y < turn - 16 { minimized = false; turn = y }
        } else {
            turn = min(turn, y)
            if y > turn + 16 { minimized = true; turn = y }
        }
    }

    func reset() {
        turn = 0
        if scrolled { scrolled = false }
        if minimized { minimized = false }
    }
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
        reporting(anchored(content))
    }

    /// `-scrollend` (CI): open at the end, and stay there while the page fills in (live data arrives after the first
    /// layout; iOS 18 can keep the anchor through size changes, iOS 17 only sets the first offset).
    @ViewBuilder func anchored(_ content: Content) -> some View {
        if !model.config.scrollEnd {
            content
        } else if #available(iOS 18.0, *) {
            content.defaultScrollAnchor(.bottom).defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            content.defaultScrollAnchor(.bottom)
        }
    }

    @ViewBuilder func reporting(_ content: some View) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self, of: { g in g.contentOffset.y + g.contentInsets.top > 1 }) { _, v in
                    if scroll.scrolled != v { scroll.scrolled = v }
                }
                .onScrollGeometryChange(for: CGFloat.self, of: { g in SheetScroll.clampedOffset(g) }) { _, y in
                    scroll.offset(y)
                }
        } else {
            content
        }
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
                // recovered: the slot's check mark says it; no second one before the text
                if !(s.recovered && hasSlot) {
                    Image(systemName: s.recovered ? "checkmark.circle.fill" : icon(p))
                        .font(.system(size: IconSize.status, weight: .semibold))
                        .foregroundStyle(s.recovered ? Palette.live : p.kind == .err ? Palette.danger : Palette.warn)
                        .accessibilityHidden(true)
                }
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

/// "Simulated buses" (spec 10.3 chip, DESIGN-SPEC-GLASS 8.3): the Settings switch is on (never in `-demo`). A 32 pt
/// glass capsule in Row B, leading; quiet, yet never mistaken for live service (the flask and the words); a tap opens
/// Settings at the switch to turn it off.
struct DemoChip: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.openSimulatedSetting() } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: Sym.simulated).font(.system(size: IconSize.inline, weight: .semibold)).accessibilityHidden(true)
                Text(AppModel.simulatedPillText).font(Typo.footnote.weight(.semibold)).lineLimit(1)
                Image(systemName: "info.circle").font(.system(size: IconSize.inline, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.label)
            .padding(.horizontal, Space.s3)
            .frame(minHeight: 32)
            .sbGlass(in: Capsule())
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

/// The trip and filter chip (spec 10.5, web ui/contextbar.js, DESIGN-SPEC-GLASS 8.3): why the map shows fewer routes
/// than usual, with a one-tap way out. A 36 pt glass capsule in Row C: route badges (up to 3, then "+N"), the label,
/// then Show all / Clear as a `fill` capsule with `label` text (not tint text on glass, and not prominent: Show all
/// ends a trip). Only the label truncates.
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
                    Text("+\(rids.count - Self.maxBadges)").font(Typo.caption).foregroundStyle(Palette.labelGlass2).padding(.leading, 2)
                }
            }
            .fixedSize()
            .accessibilityHidden(true)
            Text(label).font(Typo.footnote.weight(.semibold)).foregroundStyle(Palette.label).lineLimit(1)
                .accessibilityLabel(spoken)
            Button(action, action: run)
                .buttonStyle(FillCapsuleStyle(compact: true))
                .fixedSize()
                .accessibilityHint(hint)
        }
        .padding(.leading, Space.s3)
        .padding(.trailing, 2)
        .frame(minHeight: 36)
        .sbGlass(in: Capsule())
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

/// Locate (spec 10.4, DESIGN-SPEC-GLASS 8.4): the lower slot of the lower-right group; `location` in `tint`, filled
/// while the trip camera follows you; during a trip a tap re-centers on you. Denied location: the button stays and
/// opens the way to iOS Settings.
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
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Palette.tint)
                .frame(width: Space.chromeButton, height: Space.chromeButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChromePressStyle())
        .accessibilityLabel(trip ? "Show me on my trip" : "Show my location")
        .accessibilityValue(trip ? (following ? "Following the trip" : "Not following") : "")
        .accessibilityIdentifier("locateButton")
        .accessibilityShowsLargeContentViewer { Label("Show my location", systemImage: "location") }
    }
}

/// The floating tab bar (DESIGN-SPEC-GLASS 8.6, iOS 26's tab bar): Current trip / Routes / My Routes in a 56 pt glass
/// capsule, equal widths. The selected item sits on a 48 pt `fill` capsule that slides to the new tab (`mTabPill`;
/// Reduce Motion: it jumps) with its filled glyph in `tint` and its name in `label`; the others in `labelGlass2`.
/// Selection is the capsule and the filled glyph (and the selected trait), never color alone. Names stop growing at
/// xxxLarge and hide at accessibility sizes (and under 360 pt with large text): the icons stay, the names stay in the
/// accessibility labels and the large content viewer (touch and hold).
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNS
    /// The screen is under 360 pt wide.
    var narrow = false

    var body: some View {
        let names = !typeSize.isAccessibilitySize && !(narrow && typeSize > .large)
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                let on = model.tab == t
                Button { model.select(t) } label: {
                    VStack(spacing: 1) {
                        Image(systemName: on ? t.iconSelected : t.icon)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(on ? Palette.tint : Palette.labelGlass2)
                            .frame(height: 24)
                        if names {
                            Text(t.title).font(Typo.tabLabel).lineLimit(1).minimumScaleFactor(0.9)
                                .foregroundStyle(on ? Palette.label : Palette.labelGlass2)
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, minHeight: Space.tabBarH - 8)
                    .background {
                        if on {
                            Capsule().fill(Palette.fill)
                                .matchedGeometryEffect(id: "tabPill", in: pillNS)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(ChromePressStyle())
                .accessibilityLabel(t.title)
                .accessibilityIdentifier("tab.\(t.rawValue)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityShowsLargeContentViewer {
                    Label(t.title, systemImage: on ? t.iconSelected : t.icon)
                }
            }
        }
        .padding(4)
        .frame(minHeight: Space.tabBarH)
        .sbGlass(in: Capsule())
        .animation(reduceMotion ? nil : Motion.tabPill, value: model.tab)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The minimized tab bar (DESIGN-SPEC-GLASS 8.9): a 56 pt glass circle with the selected section's filled glyph in
/// `tint`; a tap brings the whole bar back.
struct MinimizedTabBar: View {
    @Environment(AppModel.self) private var model
    let restore: () -> Void
    var body: some View {
        Button(action: restore) {
            Image(systemName: model.tab.iconSelected).font(.system(size: 20, weight: .regular)).foregroundStyle(Palette.tint)
        }
        .buttonStyle(GlassCircleStyle(size: Space.tabBarH))
        .accessibilityLabel("\(model.tab.title), tab bar")
        .accessibilityHint("Shows all the tabs")
        .accessibilityIdentifier("tabBarMinimized")
        .accessibilityShowsLargeContentViewer { Label(model.tab.title, systemImage: model.tab.iconSelected) }
    }
}

extension SheetScroll {
    /// The offset from the content's top, clamped to its end (iOS 18 scroll geometry).
    @available(iOS 18.0, *)
    nonisolated static func clampedOffset(_ g: ScrollGeometry) -> CGFloat {
        let y = g.contentOffset.y + g.contentInsets.top
        let end = g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom - g.containerSize.height
        return min(y, max(0, end)).rounded()
    }
}

extension AppModel {
    /// This app's page in iOS Settings (location, notifications).
    static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
