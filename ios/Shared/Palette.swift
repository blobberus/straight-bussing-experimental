import SwiftUI
import UIKit

/// Color tokens of the iPhone app: docs/DESIGN-SPEC.md section 4 and the token table 14.1 (the website uses the same
/// values in web/css/tokens.css). Member of the app and the widget extension.
///
/// Color lock: ONE accent (`tint`) for every action, selection and switch; green only for live data (`live` as text,
/// `liveMark` as the dot); `warn` for delayed data, warnings and the favorite star (always with the star shape);
/// `danger` is error text, `dangerFill` the red under white text; route colors are data, never decoration. No pure
/// #000 / #FFF surfaces. Every text pair is at least 4.5:1 in light and dark (spec 4.2), and Increase Contrast gets the
/// stronger `label2`, `tint`, `tintFill` and opaque separators (spec 14.1).
enum Palette {
    /// A light / dark sRGB color with optional Increase Contrast variants.
    static func dynamic(_ light: UInt32, _ dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { t in
            let high = t.accessibilityContrast == .high
            if t.userInterfaceStyle == .dark { return UIColor(rgb: high ? highDark ?? dark : dark) }
            return UIColor(rgb: high ? highLight ?? light : light)
        })
    }

    /// The same with an opacity per appearance (fills, separators, scrims, rings).
    static func dynamicAlpha(_ light: UInt32, _ lightAlpha: CGFloat, _ dark: UInt32, _ darkAlpha: CGFloat,
                             highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { t in
            let high = t.accessibilityContrast == .high
            if t.userInterfaceStyle == .dark {
                if high, let h = highDark { return UIColor(rgb: h) }
                return UIColor(rgb: dark).withAlphaComponent(darkAlpha)
            }
            if high, let h = highLight { return UIColor(rgb: h) }
            return UIColor(rgb: light).withAlphaComponent(lightAlpha)
        })
    }

    static func fixed(_ rgb: UInt32) -> Color { Color(uiColor: UIColor(rgb: rgb)) }

    // MARK: Surfaces

    /// The sheet, the tab bar, Settings and Lines by Time (iOS grouped background; dark is the elevated #1C1C1E).
    static let bgSheet = dynamic(0xF2F2F7, 0x1C1C1E)
    /// Grouped cards and rows on the sheet, option cards (never pure #FFF).
    static let bgCard = dynamic(0xFCFCFD, 0x2C2C2E)
    /// Floating chrome without blur (Reduce Transparency fallback; the chrome itself uses `.regularMaterial`).
    static let chromeSolid = dynamic(0xFCFCFD, 0x2C2C2E)
    /// Toasts.
    static let bgInverse = dynamic(0x2C2C2E, 0xF2F2F7)
    /// Secondary buttons, fields inside the sheet, segmented track, skeletons (= iOS tertiarySystemFill).
    static let fill = dynamicAlpha(0x767680, 0.12, 0x767680, 0.24)
    /// Pressed rows and buttons.
    static let fillPressed = dynamicAlpha(0x767680, 0.20, 0x767680, 0.36)

    // MARK: Text

    static let label = dynamic(0x111114, 0xF5F5F7)
    /// Secondary text, placeholders, section titles: 5.9:1 on the light sheet, 6.3:1 on a dark card.
    static let label2 = dynamic(0x5C5C63, 0xAEAEB2, highLight: 0x3C3C43, highDark: 0xC7C7CC)
    /// Decorative marks only (row chevrons, leg-strip separators); never information.
    static let label3 = dynamic(0x8E8E93, 0x8D8D93)
    /// Text on `bgInverse` (toasts).
    static let labelInverse = dynamic(0xF5F5F7, 0x111114)
    /// Row separators and the header hairline (iOS separator); opaque under Increase Contrast.
    static let separator = dynamicAlpha(0x3C3C43, 0.29, 0x545458, 0.60, highLight: 0xC6C6C8, highDark: 0x38383A)

    // MARK: Accent

    /// The one accent: links, selection, back, switches, selected tab.
    static let tint = dynamic(0x0060CC, 0x64B0FF, highLight: 0x004A9E, highDark: 0x8AC4FF)
    /// Primary button fill, user location dot, walking path (white on it 4.7:1 in both themes).
    static let tintFill = dynamic(0x0071E3, 0x0071E3, highLight: 0x0058B0, highDark: 0x0058B0)
    /// Tinted surfaces: Board here tag, the beta card, icon circles.
    static let tintBg = dynamic(0xD9E7F8, 0x223042)
    /// Text and marks on `tintFill`, `dangerFill` and dark route colors.
    static let onFill = fixed(0xFFFFFF)

    // MARK: Status

    /// Live data as text ("Now", "Live").
    static let live = dynamic(0x157A38, 0x32D74B)
    /// Live data as a mark (the 8 pt live dot).
    static let liveMark = dynamic(0x1E9E4A, 0x32D74B)
    /// Delayed data, warnings, the favorite star.
    static let warn = dynamic(0xA35400, 0xFFB340)
    static let warnBg = dynamic(0xFFF4E0, 0x3A2A10)
    /// Error and destructive text.
    static let danger = dynamic(0xB8261A, 0xFF8C85)
    static let dangerBg = dynamic(0xFDECEB, 0x3A1A18)
    /// Red fills under white text (swipe Delete, count badge, the destination mark): 5.7:1 in both themes.
    static let dangerFill = fixed(0xC4291C)
    /// Neutral fill under white text (swipe Details): 6.6:1.
    static let neutralFill = fixed(0x5C5C63)
    /// Behind dialogs.
    static let scrim = dynamicAlpha(0x141620, 0.40, 0x08080C, 0.55)
    /// Shadows are cool slate, never pure black (`shadowRGB`).
    static let shadow = dynamic(0x1E202D, 0x08080C)
    /// Favorite star: gold, always with the star shape (never state by color alone).
    static let star = warn
    /// The favorite badge on the map: a white star on dark gold (5.3:1) in both themes.
    static let starBadge = fixed(0xA35400)

    // MARK: Glass (docs/DESIGN-SPEC-GLASS.md 5.2). iOS 26 draws real Liquid Glass; these are the iOS 17 to 25 fallback
    // and the parity values of the web's frosted glass.

    /// The frosted fill where Liquid Glass is unavailable (80%: `label` stays AA over any backdrop, spec 5.3).
    static let glassFill = dynamicAlpha(0xFAFAFC, 0.80, 0x26262A, 0.80)
    /// Glass drawn solid (Increase Contrast, moving elements on the web).
    static let glassSolid = dynamic(0xFAFAFC, 0x26262A)
    /// The thin outer edge of glass (iOS 27's darker edge), stroked around the fallback material.
    static let glassEdge = dynamicAlpha(0x111114, 0.10, 0x000000, 0.50)
    /// Secondary text on glass (placeholders, "est.", unselected tab labels): `label2` is too light on glass.
    static let labelGlass2 = dynamic(0x3C3C43, 0xC7C7CC)

    // MARK: Map overlays (spec 11)

    /// Building and place names on the map: 6.0:1 on the light land, 8.9:1 on the dark land.
    static let mapLabel = dynamic(0x565C66, 0xB4B9C2, highLight: 0x3A3F48, highDark: 0xD4D8DE)
    /// Their halo: the map's land color, so a street or a line under a letter never cuts it.
    static let mapLabelHalo = dynamic(0xF3F2EE, 0x1F2023)
    /// The ring around a bus marker.
    static let busRing = dynamic(0xFFFFFF, 0x18191C)
    /// The 1 pt ring inside a route badge whose color is under 3:1 against its surface (spec 4.3).
    static let badgeRing = dynamicAlpha(0x111114, 0.22, 0xF5F5F7, 0.30)

    // MARK: Older names (kept so earlier code and the widget compile; same values as the tokens above)

    static var text: Color { label }
    static var text2: Color { label2 }
    static var text3: Color { label3 }
    static var accent: Color { tint }
    static var accentFill: Color { tintFill }
    static var sheet: Color { bgSheet }
    static var card: Color { bgCard }
}

extension UIColor {
    /// 0xRRGGBB, opaque.
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
