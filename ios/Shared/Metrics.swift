import SwiftUI

/// Spacing scale and layout constants (docs/DESIGN-SPEC.md section 3, table 14.3). 4 pt base; no other values in
/// components (a 2 pt hairline gap inside composite marks is allowed). Spacing does not scale with text; heights that
/// hold text are minimums.
enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40

    /// Sheet content left / right padding; card inner padding.
    static let insetContent: CGFloat = 16
    /// Floating controls from the screen edge.
    static let insetChrome: CGFloat = 12
    /// Between floating controls.
    static let gapChrome: CGFloat = 8
    /// Minimum hit area of anything tappable.
    static let tap: CGFloat = 44
    /// One-line row.
    static let rowMin: CGFloat = 44
    /// Width of a row's leading badge or icon column (text starts at 16 + 40 + 12 = 68).
    static let leadingSlot: CGFloat = 40
    /// Row separators start under the text.
    static let separatorInset: CGFloat = 68
    /// The floating search bar.
    static let searchHeight: CGFloat = 48
    /// Sheet header: back + title + trailing (grows with text).
    static let sheetHeaderMin: CGFloat = 56
    /// Bottom bar (plus the bottom safe area).
    static let tabBar: CGFloat = 49

    // Glass redesign (DESIGN-SPEC-GLASS 3, 6)
    /// The floating glass tab bar capsule.
    static let tabBarH: CGFloat = 56
    /// The search circle at the trailing end of the tab bar row.
    static let searchButton: CGFloat = 56
    /// Settings circle, the lower-right group's buttons, the compass.
    static let chromeButton: CGFloat = 44
    /// Bottom edge of the floating bottom row: clears the home indicator on Face ID iPhones, 12 without a safe area.
    static func bottomRowInset(safeBottom: CGFloat) -> CGFloat { max(12, safeBottom - 12) }
}

/// Corner radii (spec section 6): five values, every rounded rectangle drawn `.continuous`. A shape nested in
/// another with inset i takes outer - i (segmented thumb 10 in a 12 track; Directions fields 10 in the 20 card).
enum Radius {
    /// Route badges, small tags, skeleton bars.
    static let tag: CGFloat = 6
    /// Buttons, fields inside the sheet, segmented track, menus.
    static let control: CGFloat = 12
    /// Grouped cards, option cards, in-sheet banners, place summary, the status banner (iOS 26's rounder sections,
    /// DESIGN-SPEC-GLASS 6).
    static let card: CGFloat = 20
    /// The collapsed glass card (all corners), the expanded sheet's top corners, dialogs (DESIGN-SPEC-GLASS `rGlass`).
    static let glass: CGFloat = 28
    /// Older name of the sheet radius: now the glass radius.
    static let sheet: CGFloat = 28
    /// The bus marker on the map (7 at 26 pt tall: the badge's proportion).
    static let busMarker: CGFloat = 7
}

/// Icon sizes (spec section 5).
enum IconSize {
    /// Beside `rowDetail` / `footnote`.
    static let inline: CGFloat = 15
    /// Row and header icons.
    static let row: CGFloat = 20
    /// Status and inline action icons.
    static let status: CGFloat = 17
    /// Bottom bar.
    static let tab: CGFloat = 24
}

/// Motion tokens (spec section 9). Live numbers change without animation. Reduce Motion: pushes and the morph become
/// 150 ms crossfades, the sheet a 150 ms ease, the camera jumps, press feedback is opacity only (`Motion.pick`).
enum Motion {
    /// Press feedback.
    static let press = Animation.easeOut(duration: 0.1)
    /// Toggles, chip state, small crossfades, skeleton to content.
    static let quick = Animation.easeOut(duration: 0.15)
    /// Content swap in the sheet; push to a sub view.
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.25)
    /// Things leaving (exits are faster than entrances).
    static let exit = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.2)
    /// Sheet settle (the release itself starts at the finger's speed, BottomSheet).
    static let sheet = Animation.spring(response: 0.38, dampingFraction: 0.88)
    /// Search bar into the Directions card and back.
    static let morph = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.3)
    /// Map camera moves to a selection.
    static let camera = Animation.easeInOut(duration: 0.6)
    /// What every motion becomes under Reduce Motion.
    static let reduced = Animation.easeInOut(duration: 0.15)
    // Glass redesign (DESIGN-SPEC-GLASS 7)
    /// Glass controls appearing (chips, the compass, the lower-right group, the bottom row after the keyboard).
    static let materialize = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.22)
    /// The selection capsule sliding to another tab.
    static let tabPill = Animation.spring(response: 0.35, dampingFraction: 0.78)
    /// The status banner (Row A) coming and going.
    static let banner = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.25)

    static func pick(_ a: Animation, reduce: Bool) -> Animation { reduce ? reduced : a }
}

/// Elevation levels (spec section 8): e0 inside the sheet (no shadow), e1 floating controls, e2 the sheet, e3 dialogs
/// and the toast. Dark mode trades the shadow for a 0.5 pt light inside border.
enum Elevation {
    case floating, sheet, overlay
}

struct ElevationModifier<S: InsettableShape>: ViewModifier {
    let level: Elevation
    let shape: S
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder func body(content: Content) -> some View {
        if scheme == .dark {
            let bordered = content
                .overlay { shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5).allowsHitTesting(false) }
            if level == .overlay {
                bordered.shadow(color: Palette.shadow.opacity(0.5), radius: 20, y: 10)
            } else {
                bordered
            }
        } else {
            switch level {
            case .floating:
                content
                    .shadow(color: Palette.shadow.opacity(0.10), radius: 1, y: 1)
                    .shadow(color: Palette.shadow.opacity(0.12), radius: 7, y: 4)
            case .sheet:
                content
                    .shadow(color: Palette.shadow.opacity(0.10), radius: 14, y: -8)
            case .overlay:
                content
                    .shadow(color: Palette.shadow.opacity(0.22), radius: 20, y: 10)
            }
        }
    }
}

extension View {
    /// The spec's elevation for this level, drawn around `shape` (the dark-mode border follows the shape).
    func elevation<S: InsettableShape>(_ level: Elevation, in shape: S) -> some View {
        modifier(ElevationModifier(level: level, shape: shape))
    }
}
