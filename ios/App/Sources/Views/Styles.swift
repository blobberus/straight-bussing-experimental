import SwiftUI
import UIKit

/// Button styles, layouts and symbol names shared by every screen (docs/DESIGN-SPEC.md 10.11, 10.12). One primary
/// button per screen; a second action of equal weight uses Secondary. Press feedback `Motion.press`: filled buttons
/// opacity .85 and scale .98, text and icon buttons opacity .6; Reduce Motion: opacity only. Disabled: 45%.

/// Primary: white on `tintFill` (4.7:1 in both themes), 50 tall when full width, 44 inline.
struct PrimaryButtonStyle: ButtonStyle {
    var full = false
    /// Side padding (12 for buttons that share a row by their words, spec 10.14).
    var hPad: CGFloat = Space.s4
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .font(Typo.button)
            .foregroundStyle(Palette.onFill)
            .multilineTextAlignment(.center)
            .padding(.horizontal, hPad)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: full ? .infinity : nil, minHeight: full ? 50 : Space.tap)
            .background(Palette.tintFill, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Secondary: `tint` (or `danger`) text on the neutral `fill` (5.0:1 / 4.7:1 or more), same sizes as Primary.
/// `compact`: 36 pt tall visual with the 44 pt hit area kept (End trip, header actions).
struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false
    var full = false
    var compact = false
    /// Side padding of the regular size (12 for buttons that share a row by their words).
    var hPad: CGFloat = Space.s4
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .font(compact ? Typo.sectionTitle : Typo.button)
            .foregroundStyle(destructive ? Palette.danger : Palette.tint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, compact ? Space.s3 : hPad)
            .padding(.vertical, compact ? Space.s1 : Space.s2)
            .frame(maxWidth: full ? .infinity : nil, minHeight: compact ? 36 : (full ? 50 : Space.tap))
            .background(configuration.isPressed ? Palette.fillPressed : Palette.fill, in: shape)
            .padding(.vertical, compact ? 4 : 0)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Text button: `tint` label, no fill, 44 pt tall hit area (header actions, inline links).
struct TextButtonStyle: ButtonStyle {
    var font: Font = Typo.button
    var color: Color = Palette.tint
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(color)
            .frame(minWidth: Space.tap, minHeight: Space.tap)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A capsule action of the Routes filter (Show all / Show running / Hide all): three actions, not a segmented
/// state; the one that matches the current state shows a check mark and `label` text. 36 visual, 44 hit.
struct CapsuleButtonStyle: ButtonStyle {
    var current = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s1) {
            if current {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
            }
            configuration.label.lineLimit(1)
        }
        // footnote Semibold: the three actions fit one row at 393 pt (a stacked column of capsules read as a menu)
        .font(Typo.footnote.weight(.semibold))
        .foregroundStyle(current ? Palette.label : Palette.tint)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(configuration.isPressed ? Palette.fillPressed : Palette.fill, in: Capsule())
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
        .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A tappable row: the pressed state is `fillPressed` behind the whole row (spec 10.8).
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.fillPressed : Color.clear)
            .contentShape(Rectangle())
    }
}

extension View {
    func primaryButtonStyle(full: Bool = false) -> some View { buttonStyle(PrimaryButtonStyle(full: full)) }
    func secondaryButtonStyle(destructive: Bool = false, full: Bool = false, compact: Bool = false) -> some View {
        buttonStyle(SecondaryButtonStyle(destructive: destructive, full: full, compact: compact))
    }
    func textButtonStyle(font: Font = Typo.button, color: Color = Palette.tint) -> some View {
        buttonStyle(TextButtonStyle(font: font, color: color))
    }
    /// Large tap target (44 pt).
    func tapTarget() -> some View { frame(minWidth: Space.tap, minHeight: Space.tap).contentShape(Rectangle()) }
}

/// Buttons in one row share the width equally (spec 10.11); `ViewThatFits` falls back to a stack when the widest label
/// times the count does not fit, so a label never wraps or truncates in a row.
struct EqualWidthHStack: Layout {
    var spacing: CGFloat = Space.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let n = CGFloat(subviews.count)
        let need = (sizes.map(\.width).max() ?? 0) * n + spacing * (n - 1)
        let h = sizes.map(\.height).max() ?? 0
        if let w = proposal.width, w.isFinite, w >= need { return CGSize(width: w, height: h) }
        return CGSize(width: need, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let n = CGFloat(subviews.count)
        let w = max(0, (bounds.width - spacing * (n - 1)) / n)
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? bounds.height
        var x = bounds.minX
        for s in subviews {
            s.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
            x += w + spacing
        }
    }
}

/// Buttons sized by their words that share the leftover width (CSS `flex: 1 1 auto` with wrapping, the web's stop
/// actions): each line holds as many buttons as fit at their natural width, then every button on the line grows by the
/// same amount to fill it. A narrow phone wraps the last one to a second line; no label is ever cut.
struct FillRowLayout: Layout {
    var spacing: CGFloat = Space.s2
    var lineSpacing: CGFloat = Space.s2

    func lines(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var out: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            if !out[out.count - 1].isEmpty && x + spacing + size.width > width {
                out.append([])
                x = 0
            }
            x += (out[out.count - 1].isEmpty ? 0 : spacing) + size.width
            out[out.count - 1].append((i, size))
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let ls = lines(subviews, width: width)
        var h: CGFloat = 0, w: CGFloat = 0
        for (k, l) in ls.enumerated() where !l.isEmpty {
            h += (l.map(\.size.height).max() ?? 0) + (k > 0 ? lineSpacing : 0)
            w = max(w, l.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(l.count - 1))
        }
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for l in lines(subviews, width: bounds.width) where !l.isEmpty {
            let lh = l.map(\.size.height).max() ?? 0
            let used = l.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(l.count - 1)
            let extra = max(0, (bounds.width - used) / CGFloat(l.count))
            var x = bounds.minX
            for item in l {
                let w = item.size.width + extra
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: lh))
                x += w + spacing
            }
            y += lh + lineSpacing
        }
    }
}

/// Wrapping row of small items (route badges on a stop, chips in Lines by Time).
struct FlowLayout: Layout {
    var spacing: CGFloat = Space.s2
    var lineSpacing: CGFloat = Space.s2

    func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rs = rows(subviews, width: width)
        var h: CGFloat = 0, w: CGFloat = 0
        for (k, r) in rs.enumerated() where !r.isEmpty {
            h += (r.map(\.size.height).max() ?? 0) + (k > 0 ? lineSpacing : 0)
            w = max(w, r.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, r.count - 1)))
        }
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in rows(subviews, width: bounds.width) where !r.isEmpty {
            let rh = r.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in r {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (rh - item.size.height) / 2), anchor: .topLeading,
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rh + lineSpacing
        }
    }
}

/// SF Symbol names (spec section 5: one glyph per meaning). Symbols newer than the deployment target fall back.
enum Sym {
    static func pick(_ name: String, _ fallback: String) -> String { UIImage(systemName: name) != nil ? name : fallback }

    static let routes = "point.topleft.down.to.point.bottomright.curvepath"
    static let routesFill = pick("point.topleft.down.to.point.bottomright.curvepath.fill", routes)
    static let simulated = pick("flask", "testtube.2")
    static let noLive = "antenna.radiowaves.left.and.right.slash"
    static let delayed = "clock.badge.exclamationmark"
    static let feedError = "wifi.slash"
    static let alert = "exclamationmark.triangle.fill"
    static let walk = "figure.walk"
    static let directions = "arrow.turn.up.right"
}
