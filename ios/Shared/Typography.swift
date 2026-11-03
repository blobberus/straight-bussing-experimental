import SwiftUI

/// Typography roles (docs/DESIGN-SPEC.md section 2 and table 14.2): the system font through Dynamic Type text
/// styles only, three weights (Regular, Semibold, Bold), tabular figures for every time and count. The website writes
/// the same roles relative to its body size (web/css/tokens.css `--t-*`). Map labels are the only fixed sizes (they do
/// not follow Dynamic Type, as in Apple Maps).
///
/// Rules (spec 2.1): at most four roles in one card; two roles next to each other differ in at least two of size,
/// weight and color; sentence case everywhere (`.textCase(nil)` on list headers).
enum Typo {
    /// Sheet header title: tab roots, Directions, stop and route names. 22 / 28 Bold.
    static let sheetTitle = Font.title2.bold()
    /// The one thing to read first inside a sheet: the next step, a place name. 20 / 25 Semibold.
    static let heroTitle = Font.title3.weight(.semibold)
    /// First line of a list row. 17 / 22 Semibold.
    static let rowTitle = Font.headline
    /// Paragraphs, field text. 17 / 22 Regular.
    static let body = Font.body
    /// Button labels. 17 / 22 Semibold.
    static let button = Font.body.weight(.semibold)
    /// Second and third lines of rows. 15 / 20 Regular.
    static let rowDetail = Font.subheadline
    /// Label above a group of rows. 15 / 20 Semibold.
    static let sectionTitle = Font.subheadline.weight(.semibold)
    /// Honesty notes, timestamps, helper text, "est." after small numbers. 13 / 18 Regular.
    static let footnote = Font.footnote
    /// Small labels: "Arriving In", option criteria, tags. 12 / 16 Semibold.
    static let caption = Font.caption.weight(.semibold)
    /// Bottom bar labels. 11 / 13 Semibold.
    static let tabLabel = Font.caption2.weight(.semibold)
    /// Route short name in a 24 pt badge. 12 / 16 Bold.
    static let badge = Font.caption.bold()
    /// Route short name in a 20 pt badge. 11 / 13 Bold.
    static let badgeSmall = Font.caption2.bold()
    /// The next-bus or next-step numeral (once per screen at most). 34 / 41 Bold, tabular.
    static let etaHero = Font.largeTitle.bold().monospacedDigit()
    /// ETA numeral in rows. 22 / 28 Semibold, tabular.
    static let etaRow = Font.title2.weight(.semibold).monospacedDigit()
    /// "min" after an `etaRow` numeral, on its baseline.
    static let etaUnitRow = Font.subheadline
    /// "min" after an `etaHero` numeral.
    static let etaUnitHero = Font.headline

    // Map labels: fixed sizes (spec 2.1)
    static let mapLandmark = Font.system(size: 12, weight: .semibold)
    static let mapBadge = Font.system(size: 11, weight: .bold)
    /// A bus marker whose short name is longer than 5 characters.
    static let mapBadgeLong = Font.system(size: 10, weight: .bold)
    static let mapCallout = Font.system(size: 13, weight: .semibold)
}
