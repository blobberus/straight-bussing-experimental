import MapKit
import SwiftUI
import StraightBussingKit

extension LatLon {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

// MARK: Route badge (spec 10.9)

/// Route badge: the short name on the route color in a 6 pt rounded rectangle, 24 tall in rows and 20 tall inline.
/// Never truncated (longer names widen it; over 5 characters it drops to 10 pt). A route color under 3:1 against the
/// card gets a 1 pt inside ring, same shape either way. Hidden route: 40% opacity with "Hidden" in the row text.
struct RouteBadge: View {
    enum Size { case regular, small }
    let route: Route?
    var rid: String = ""
    var size: Size = .regular
    var dimmed = false
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let raw = route?.chipText ?? rid
        let text = raw.isEmpty ? "Bus" : raw
        let shape = RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
        let base: CGFloat = text.count > 5 ? 10 : (size == .regular ? 12 : 11)
        let s = min(scale, 1.8)
        let ring = Color.contrast(hex: route?.color, against: scheme == .dark ? 0x2C2C2E : 0xFCFCFD) < 3
        Text(text)
            .font(.system(size: base * s, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size == .regular ? 6 : 5)
            .frame(minWidth: (size == .regular ? 32 : 28) * min(s, 1.4), minHeight: (size == .regular ? 24 : 20) * s)
            .foregroundStyle(Color.badgeText(hex: route?.color))
            .background(Color(hex: route?.color), in: shape)
            .overlay { if ring { shape.strokeBorder(Palette.badgeRing, lineWidth: 1) } }
            .opacity(dimmed ? 0.4 : 1)
            .accessibilityLabel("Route \(route?.displayName ?? rid)")
    }
}

// MARK: ETA notation (spec 10.10)

/// One ETA: numeral + " min" on its baseline ("4 min"); "Now" in `live` under a minute; a clock time at 60 minutes or
/// more; stale = "~" and `label2`. `hero` is the once-per-screen 34 pt numeral. Live numbers change without animation.
struct EtaView: View {
    enum Size { case row, hero }
    let t: Double
    let now: Double
    var stale = false
    var size: Size = .row
    /// An estimate (not a live prediction): "est." follows and "Now" is never claimed.
    var estimate = false

    var body: some View {
        let m = TimeFmt.minsUntil(t, from: now)
        let numFont = size == .hero ? Typo.etaHero : Typo.etaRow
        let unitFont = size == .hero ? Typo.etaUnitHero : Typo.etaUnitRow
        let dim = stale || estimate
        let n = max(1, m)
        let spoken: String = m < 1 && !estimate ? "Arriving now"
            : m >= 60 ? "at " + TimeFmt.clock(t)
            : "\(n) minute\(n == 1 ? "" : "s")" + (dim ? ", estimate" : "")
        Group {
            if m < 1 && !estimate {
                Text(stale ? "~Now" : "Now")
                    .font(size == .hero ? Typo.etaHero : Typo.etaRow)
                    .foregroundStyle(stale ? Palette.label2 : Palette.live)
            } else if m >= 60 {
                Text(TimeFmt.clock(t)).font(size == .hero ? Typo.heroTitle : Typo.rowTitle).monospacedDigit()
                    .foregroundStyle(dim ? Palette.label2 : Palette.label)
            } else {
                Text((dim ? "~" : "") + "\(max(1, m))").font(numFont).foregroundStyle(dim ? Palette.label2 : Palette.label)
                    + Text(" min").font(unitFont).fontWeight(size == .hero ? .semibold : .regular).foregroundStyle(Palette.label2)
                    + Text(estimate ? " est." : "").font(Typo.footnote).foregroundStyle(Palette.label2)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// Live state dot (8 pt): green live, gold delayed, a hollow ring when only the last known prediction is left. The
/// words next to it carry the state; the dot is decorative.
struct LiveDot: View {
    var level: StaleLevel = .fresh
    var body: some View {
        Group {
            switch level {
            case .fresh: Circle().fill(Palette.liveMark)
            case .late: Circle().fill(Palette.warn)
            default: Circle().strokeBorder(Palette.label2, lineWidth: 1.5)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}

/// The source mark under a row title: "Live" in `live` with the dot, "Live, delayed" / "Last known" in `label2`, then
/// optional detail ("Bus 1624", "Leave in 3 min, est.").
struct SourceLine: View {
    let level: StaleLevel
    var extra: String? = nil
    var strong = false
    var body: some View {
        let lbl = LiveText.liveLabel(level)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            LiveDot(level: level).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            (Text(lbl.text).foregroundStyle(level == .fresh ? Palette.live : Palette.label2)
                + Text(extra.map { " \u{00B7} " + $0 } ?? "").foregroundStyle(strong ? Palette.label : Palette.label2))
                .font(Typo.rowDetail)
                .lineLimit(2)
        }
    }
}

// MARK: Rows and cards (spec 10.8)

/// A row: 40 pt leading slot (badge or icon), 12 gap, the text column, the trailing value; 16 / 12 padding, 44 pt
/// minimum. At accessibility text sizes the leading badge goes above the title and the trailing value under the text.
struct RowLayout<Leading: View, Content: View, Trailing: View>: View {
    var chevron = false
    var vertical: CGFloat = Space.s3
    @ViewBuilder var leading: Leading
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ax = typeSize.isAccessibilitySize
        let hasLeading = Leading.self != EmptyView.self
        HStack(alignment: .center, spacing: Space.s3) {
            if ax {
                VStack(alignment: .leading, spacing: Space.s2) {
                    if hasLeading { leading }
                    VStack(alignment: .leading, spacing: 2) { content }
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if hasLeading { leading.frame(minWidth: Space.leadingSlot) }
                VStack(alignment: .leading, spacing: 2) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            if chevron {
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Palette.label3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.insetContent)
        .padding(.vertical, vertical)
        .frame(minHeight: Space.rowMin)
        .contentShape(Rectangle())
    }
}

/// Grouped card (spec 10.8): `bgCard`, 14 pt corners, no shadow, no border. Rows bring their own padding;
/// `padded` gives free content the 16 pt inset.
struct Card<Content: View>: View {
    var padded = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padded ? Space.insetContent : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Row separator: a hairline under the text (68 pt in), full width at accessibility sizes.
struct RowDivider: View {
    var inset: CGFloat = Space.separatorInset
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 1 / max(1, displayScale))
            .padding(.leading, typeSize.isAccessibilitySize ? Space.insetContent : inset)
            .accessibilityHidden(true)
    }
}

/// Label above a group of rows (spec 10.8): `sectionTitle` in `label2`, sentence case, aligned with the card's
/// content; 24 above it and 8 to its card inside a 12 pt stack. Optional trailing text action.
struct SectionTitle<Trailing: View>: View {
    let text: String
    var trailing: Trailing

    init(text: String) where Trailing == EmptyView {
        self.text = text
        self.trailing = EmptyView()
    }

    init(text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(text).font(Typo.sectionTitle).foregroundStyle(Palette.label2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s2)
            trailing
        }
        .padding(.leading, Space.insetContent)
        .padding(.top, Space.s3)
        .padding(.bottom, -Space.s1)
    }
}

/// A List / Form section header in the spec's section title role (sentence case; the system header gray is 3.3:1 on
/// the light sheet).
struct ListHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typo.sectionTitle).foregroundStyle(Palette.label2).textCase(nil)
    }
}

/// An inline status note inside the sheet (spec 10.18 / 13.8): `warnBg` (warnings, missed bus, coverage) or
/// `dangerBg` (feed error), the status icon, `rowDetail` text with an optional Semibold lead.
struct InlineBanner: View {
    enum Kind { case warn, danger, info }
    var kind: Kind = .warn
    var icon: String = Sym.alert
    var lead: String? = nil
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Image(systemName: icon).font(.system(size: IconSize.status, weight: .semibold))
                .foregroundStyle(kind == .danger ? Palette.danger : kind == .warn ? Palette.warn : Palette.tint)
                .accessibilityHidden(true)
            (Text(lead.map { $0 + " " } ?? "").fontWeight(.semibold) + Text(text))
                .font(Typo.rowDetail).foregroundStyle(Palette.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.insetContent)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, minHeight: Space.rowMin, alignment: .leading)
        .background(kind == .danger ? Palette.dangerBg : kind == .warn ? Palette.warnBg : Palette.tintBg,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A symbol in a tinted circle (place summary, walk-first card, next-step card).
struct IconCircle: View {
    let symbol: String
    var size: CGFloat = 36
    var fill: Color = Palette.tintBg
    var color: Color = Palette.tint
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: IconSize.status, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: Arrivals

/// One arrival row (spec 10.14): route badge, route name, the source mark (+ bus or walking guidance), the ETA.
/// `sub` replaces "Bus N" with walking guidance ("Leave in 3 min, est."); `miss` = cannot walk there in time (said in
/// words, the ETA struck through, never color alone). VoiceOver reads one sentence.
struct ArrivalRow: View {
    @Environment(AppModel.self) private var model
    let a: Arrival
    var sub: String? = nil
    var miss = false
    var aria: String? = nil
    var chevron = false

    var body: some View {
        let lbl = LiveText.liveLabel(model.staleLevel)
        let m = TimeFmt.minsUntil(a.t, from: model.now)
        let when = m < 1 ? "arriving now" : "arrives in \(m) minute\(m == 1 ? "" : "s")"
        RowLayout(chevron: chevron) {
            RouteBadge(route: model.route(a.rid), rid: a.rid)
        } content: {
            Text(model.longName(a.rid)).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
            SourceLine(level: model.staleLevel, extra: sub ?? a.bus.map { "Bus \($0)" }, strong: miss)
        } trailing: {
            EtaView(t: a.t, now: model.now, stale: model.isStale)
                .strikethrough(miss)
                .opacity(miss ? 0.55 : 1)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route \(model.shortName(a.rid)), \(model.longName(a.rid)), \(when), \(lbl.spoken)\(aria.map { ", " + $0 } ?? "")")
    }
}

/// An arrival row that opens its route.
struct ArrivalButton: View {
    @Environment(AppModel.self) private var model
    let a: Arrival
    var sub: String? = nil
    var miss = false
    var aria: String? = nil
    var body: some View {
        Button { model.push(.route(a.rid)) } label: { ArrivalRow(a: a, sub: sub, miss: miss, aria: aria) }
            .buttonStyle(RowButtonStyle())
            .accessibilityHint("Opens the route")
    }
}

// MARK: Loading and empty states (spec 10.20)

/// Loading rows shaped like the rows they stand in for (badge, two text bars, ETA) in `fill`; a slow 0.6 to 1 pulse,
/// static under Reduce Motion. Never a spinner on a blank sheet. VoiceOver reads one "Loading live data".
struct SkeletonRows: View {
    var count = 3
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                if i > 0 { RowDivider() }
                HStack(spacing: Space.s3) {
                    RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).frame(width: 32, height: 24)
                        .frame(width: Space.leadingSlot)
                    VStack(alignment: .leading, spacing: Space.s2) {
                        RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).frame(width: 150, height: 12)
                        RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).frame(width: 96, height: 10)
                    }
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: Radius.tag, style: .continuous).frame(width: 44, height: 20)
                }
                .foregroundStyle(Palette.fill)
                .padding(.horizontal, Space.insetContent)
                .frame(minHeight: 60)
            }
        }
        .opacity(reduceMotion ? 1 : (on ? 1 : 0.6))
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: on)
        .onAppear { if !reduceMotion { on = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading live data")
    }
}

/// Empty / error state inside a card (spec 10.20): a 28 pt icon in `label3`, the title, the text, centered. What to do
/// next comes right under the card (never a dead end): the official contact, or where no bus reports the operator's
/// alerts in full and whom to call.
struct EmptyStateView: View {
    let title: String
    let message: String
    var icon: String? = nil
    var showOfficial = false
    /// No bus is reporting (feed down, silent scheduled service, nothing running): the operator's own alerts in full
    /// come next, before our official contact (web operatorAlertsHTML).
    var operatorAlerts = false
    /// Inside a List row (the row is the card already).
    var inList = false

    var body: some View {
        VStack(spacing: Space.s3) {
            if inList { core } else { Card(padded: true) { core } }
            if operatorAlerts && showOfficial {
                NoBusHelp()   // the operator's number, if its alert gives one, is the primary call
            } else if operatorAlerts {
                OperatorAlerts()
            } else if showOfficial {
                OfficialContact()
            }
        }
    }

    var core: some View {
        VStack(spacing: Space.s2) {
            if let icon {
                Image(systemName: icon).font(.system(size: 28, weight: .regular)).foregroundStyle(Palette.label3)
                    .accessibilityHidden(true)
                    .padding(.bottom, 2)
            }
            Text(title).font(Typo.rowTitle).foregroundStyle(Palette.label).multilineTextAlignment(.center)
            Text(message).font(Typo.rowDetail).foregroundStyle(Palette.label2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s2)
        .accessibilityElement(children: .combine)
    }
}

/// Pages on the project site (GitHub Pages): the privacy policy (App Review 5.1.1 asks for an in-app link) and
/// the support page.
enum SiteLinks {
    static let privacy = URL(string: "https://blobberus.github.io/straight-bussing/privacy.html")!
    static let support = URL(string: "https://blobberus.github.io/straight-bussing/support.html")!
    /// Beta feedback form (owner 2026-10-13, Google Forms): opened in Safari from Settings > Beta feedback; nothing is
    /// sent by the app, only the rider's own Submit there.
    static let feedback = URL(string: "https://forms.gle/zK4hi2UfYsrXURR97")!
}

/// Official service contact (shown in About and empty/error states). Where no bus reports and the operator's live
/// alert gives a number (`operatorPhone`, from `NoBusHelp`), that number is the one primary call, labeled for its
/// purpose, and 773.702.8181 becomes the secondary "Safety or urgent" call. Otherwise 773.702.8181 is primary.
struct OfficialContact: View {
    var operatorPhone: LiveText.PhoneLink? = nil
    /// 773.702.8181 as a tel: URL (the same form `LiveText.phoneLinks` makes, so alert cards can skip it).
    static let telURL = "tel:+17737028181"

    var body: some View {
        VStack(spacing: Space.s2) {
            if let p = operatorPhone, let url = URL(string: p.url) {
                Link(destination: url) { OperatorCallLabel(number: p.shown) }
                    .primaryButtonStyle(full: true)
                    .accessibilityLabel("Call bus route help, \(p.shown)")
                    .accessibilityHint("The number in the shuttle operator's alert")
                    .accessibilityIdentifier("callOperator")
                Link(destination: URL(string: Self.telURL)!) {
                    Label("Safety or urgent: \(LiveText.phone)", systemImage: "phone.fill")
                }
                .secondaryButtonStyle(full: true)
                .accessibilityLabel("Safety or urgent: call \(LiveText.phone)")
                .accessibilityIdentifier("callOfficial")
            } else {
                Link(destination: URL(string: Self.telURL)!) {
                    Label("Call \(LiveText.phone)", systemImage: "phone.fill")
                }
                .primaryButtonStyle(full: true)
                .accessibilityIdentifier("callOfficial")
            }
            Link(destination: URL(string: "https://safety-security.uchicago.edu/Transportation")!) {
                HStack(spacing: Space.s1) {
                    Text("Official transportation page")
                    Image(systemName: "arrow.up.right.square").font(.system(size: IconSize.inline)).accessibilityHidden(true)
                }
            }
            .textButtonStyle(font: Typo.rowDetail.weight(.semibold))
            .accessibilityHint("Opens in Safari")
        }
    }
}

/// "Call bus route help: 773-655-9934" on one line, or the purpose over the number when it does not fit (large
/// text, narrow phones): a primary button never wraps mid-label.
struct OperatorCallLabel: View {
    let number: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Label("Call bus route help: \(number)", systemImage: "phone.fill")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: Space.s2) {
                Image(systemName: "phone.fill")
                VStack(spacing: 1) {
                    Text("Call bus route help")
                    Text(number).font(Typo.rowDetail).monospacedDigit()
                }
                .multilineTextAlignment(.center)
            }
        }
    }
}
