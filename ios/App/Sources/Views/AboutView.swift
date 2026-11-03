import SwiftUI
import StraightBussingKit

/// About (ui/views/about.js): unofficial notice, official phone/link, privacy with the privacy policy and support
/// links (App Review 5.1.1 wants the policy reachable in the app), how times work, credits (no copyright sign,
/// like the web's map credit), version + schedule data date. Body text keeps a readable measure in `body`.
struct AboutView: View {
    @Environment(AppModel.self) private var model

    var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                Card(padded: true) {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        Text("Straight Bussing is an unofficial student project.").font(Typo.rowTitle).foregroundStyle(Palette.label)
                        Text("It is not affiliated with or endorsed by the University or by Passio. Arrival times are predictions and can be wrong.")
                            .font(Typo.body).foregroundStyle(Palette.label)
                        Text("For safety rides or anything urgent, use the official service:").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                        OfficialContact()
                    }
                }
                .accessibilityIdentifier("aboutUnofficial")
                SectionTitle(text: "Appearance")
                ThemePicker()
                SectionTitle(text: "Privacy")
                Card(padded: true) {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        bullet("No account, no ads, no tracking. Your location, if you allow it, is used on this iPhone; your live location is never stored or sent anywhere. The one exception: when you ask for directions, the rounded start of a walking leg can be your location (see Walking directions).")
                        bullet("Place search: station names and places within a 30-minute walk of campus stops are searched on this iPhone, including spelling fixes. Only when that finds fewer than 5 matches, or when you tap \u{201C}Search for \u{2026} instead\u{201D}, is text sent to photon.komoot.io (OpenStreetMap geocoder): the text you typed, or its spelling fix when results are shown for the fix, and nothing else.")
                        bullet("Network requests: the public shuttle feeds (passio3.com), Apple Maps for the map and for walking directions, photon.komoot.io for address search (above), and blobberus.github.io for schedule updates (below).")
                        bullet("Schedule updates: at most once a day the app asks blobberus.github.io (the site of the web version) whether newer schedule files exist, and downloads them if so. These are plain requests for public files: no location, search text or ID is sent. Until a new schedule is checked and complete, the one built into the app is used.")
                        bullet("Walking directions: only the start and end of each walking leg (your location, when a trip starts there), rounded to about 10 m, are sent to Apple Maps to follow sidewalks. Nothing else about you or your trip is sent. If that fails, a straight-line estimate is used and labeled \u{201C}estimate\u{201D}.")
                        bullet("Settings (theme, hidden routes, custom routes, favorites) are saved on this iPhone only.")
                    }
                }
                Card {
                    linkRow("Privacy policy", "hand.raised", SiteLinks.privacy, id: "aboutPrivacyPolicy")
                    RowDivider()
                    linkRow("Contact support", "questionmark.bubble", SiteLinks.supportContact, id: "aboutSupport")
                }
                SectionTitle(text: "How times work")
                Text("Arrival times come from the live shuttle feed. Ride, wait and total times in Directions are estimates from schedules and live predictions, and each one says where it came from. If the feed is late or down, the app tells you.")
                    .font(Typo.body).foregroundStyle(Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.insetContent)
                SectionTitle(text: "Credits")
                Card(padded: true) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        bullet("Live and schedule data: public Passio GTFS and GTFS-Realtime feeds.")
                        bullet("Campus places list: OpenStreetMap contributors (ODbL).")
                        bullet("Map on the web version: OpenFreeMap, OpenMapTiles and OpenStreetMap.")
                        bullet("Map in this app: Apple Maps (MapKit).")
                        bullet("Place search: Photon by komoot. Walking routes: Apple Maps.")
                    }
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Version \(version)\(scheduleDate.map { ", schedule data from \($0)" } ?? "")")
                    Text("Unofficial. Not affiliated with the University. Official service: 773.702.8181.")
                }
                .font(Typo.footnote).foregroundStyle(Palette.label2)
                .padding(.horizontal, Space.insetContent)
                .padding(.top, Space.s2)
            }
            .padding(.horizontal, Space.insetContent)
            .padding(.top, Space.s1)
            .padding(.bottom, Space.s6)
        }
        .reportsSheetScrollIfAvailable()
        .background(Palette.bgSheet)
    }

    var scheduleDate: String? {
        guard let g = model.staticData.generated else { return nil }
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: g) else { return nil }
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: Schedule.chicago))
    }

    func bullet(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text("\u{2022}").foregroundStyle(Palette.label2).accessibilityHidden(true)
            Text(s).font(Typo.rowDetail).foregroundStyle(Palette.label).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A row that opens a page of the project site in Safari.
    func linkRow(_ title: String, _ icon: String, _ url: URL, id: String) -> some View {
        Link(destination: url) {
            RowLayout {
                Image(systemName: icon).font(.system(size: IconSize.row)).foregroundStyle(Palette.tint).accessibilityHidden(true)
            } content: {
                Text(title).font(Typo.body).foregroundStyle(Palette.tint)
            } trailing: {
                Image(systemName: "arrow.up.right.square").font(.system(size: IconSize.inline, weight: .semibold)).foregroundStyle(Palette.label3)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityHint("Opens in Safari")
        .accessibilityIdentifier(id)
    }
}

extension View {
    /// About is shown in the sheet (reports its scroll to the header) and inside Settings (no sheet header there).
    func reportsSheetScrollIfAvailable() -> some View { modifier(OptionalSheetScrollReporter()) }
}

/// `reportsSheetScroll` when a `SheetScroll` is in the environment (the map screen's sheet), nothing otherwise.
struct OptionalSheetScrollReporter: ViewModifier {
    @Environment(SheetScroll.self) private var scroll: SheetScroll?
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let scroll {
            content.onScrollGeometryChange(for: Bool.self, of: { g in g.contentOffset.y + g.contentInsets.top > 1 }) { _, v in
                if scroll.scrolled != v { scroll.scrolled = v }
            }
        } else {
            content
        }
    }
}
