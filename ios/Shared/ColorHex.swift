import SwiftUI

extension Color {
    /// '#RRGGBB' -> Color (falls back to '#555555', like core/esc.js safeColor).
    init(hex: String?) {
        var s = (hex ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = s.count == 6 ? UInt32(s, radix: 16) : nil
        let rgb = v ?? 0x555555
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }

    /// '#RRGGBB' faded toward a neutral gray, opaque: map routes that are not in focus (the web draws them at 25 %
    /// opacity; MapKit ignores a polyline color's alpha, so the fade is mixed into the color instead).
    static func dimmed(hex: String?, amount: Double = 0.72) -> Color {
        var s = (hex ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let rgb = (s.count == 6 ? UInt32(s, radix: 16) : nil) ?? 0x555555
        let gray = 0.62
        func mix(_ c: UInt32) -> Double { Double(c) / 255 * (1 - amount) + gray * amount }
        return Color(.sRGB, red: mix((rgb >> 16) & 0xFF), green: mix((rgb >> 8) & 0xFF), blue: mix(rgb & 0xFF), opacity: 1)
    }

    /// '#RRGGBB' mixed toward the opaque 0xRRGGBB `base` (the map's land): a line drawn at `1 - amount` opacity over it
    /// (spec 11.3 focused state: unfocused lines at 0.2), opaque because MapKit ignores a polyline color's alpha.
    static func mixed(hex: String?, toward base: UInt32, amount: Double) -> Color {
        var s = (hex ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let rgb = (s.count == 6 ? UInt32(s, radix: 16) : nil) ?? 0x555555
        func mix(_ c: UInt32, _ b: UInt32) -> Double { Double(c) / 255 * (1 - amount) + Double(b) / 255 * amount }
        return Color(.sRGB, red: mix((rgb >> 16) & 0xFF, (base >> 16) & 0xFF), green: mix((rgb >> 8) & 0xFF, (base >> 8) & 0xFF),
                     blue: mix(rgb & 0xFF, base & 0xFF), opacity: 1)
    }

    /// Badge text on a route color (docs/DESIGN-SPEC.md 4.3): whichever of #FFFFFF and #111114 has the higher contrast
    /// (GTFS route_text_color is ignored when it is lower; RED #D62728 takes white at 5.0:1). Used by the route badge,
    /// the bus marker, the rails and the Live Activity chip.
    static func badgeText(hex: String?) -> Color {
        let white = Color.contrast(hex: hex, against: 0xFFFFFF), ink = Color.contrast(hex: hex, against: 0x111114)
        return white >= ink ? .white : Color(red: 17 / 255, green: 17 / 255, blue: 20 / 255)
    }

    /// Readable text color on a '#RRGGBB' background (core/esc.js textOn, by relative luminance).
    static func textOn(hex: String?) -> Color {
        var s = (hex ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let rgb = (s.count == 6 ? UInt32(s, radix: 16) : nil) ?? 0x555555
        return luminance(rgb) > 0.4 ? Color(red: 0.067, green: 0.067, blue: 0.078) : .white
    }

    /// WCAG relative luminance of 0xRRGGBB.
    static func luminance(_ rgb: UInt32) -> Double {
        func lin(_ c: UInt32) -> Double {
            let x = Double(c) / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin((rgb >> 16) & 0xFF) + 0.7152 * lin((rgb >> 8) & 0xFF) + 0.0722 * lin(rgb & 0xFF)
    }

    /// WCAG contrast ratio of a '#RRGGBB' color against 0xRRGGBB (route chips under 3:1 get a ring).
    static func contrast(hex: String?, against bg: UInt32) -> Double {
        var s = (hex ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let a = luminance((s.count == 6 ? UInt32(s, radix: 16) : nil) ?? 0x555555), b = luminance(bg)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
