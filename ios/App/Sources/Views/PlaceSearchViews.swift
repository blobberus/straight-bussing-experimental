import SwiftUI
import StraightBussingKit

/// Place search state shared by Directions, Current trip "Type an address or place" and Routes to station
/// (web ui/views/placesearch.js). `status`: idle (settled), busy (Photon still coming; items may be listed),
/// err (Photon failed and nothing was found).
struct PlaceUI: Equatable {
    enum Status: Equatable { case idle, busy, err }
    var q = ""
    var items: [PlaceHit] = []
    var assumed: SearchAssumption?
    /// Search exactly as typed (no spelling fix; Photon always from 3 letters).
    var exact = false
    /// The correction that was on screen before "Search for … instead" (for "Did you mean …?").
    var fix: SearchAssumption?
    var status: Status = .idle
}

/// Runs one search: on-device results right away (no debounce), Photon only when the index has fewer than
/// 5 matches (or for an exact search) after a 250 ms pause, cancelled by the next keystroke.
@MainActor
enum PlaceSearchFlow {
    static let photonDelayNs: UInt64 = 250_000_000

    static func run(_ q: String, exact: Bool, model: AppModel, update: (PlaceUI) -> Void, current: () -> PlaceUI) async {
        let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
        var st = current()
        st.q = query
        guard PlaceIndex.norm(query).count >= 2 else {
            st.items = []; st.assumed = nil; st.status = .idle
            update(st)
            return
        }
        let index = model.places
        let local = await Task.detached(priority: .userInitiated) { PlaceSearcher.local(query, index: index, exact: exact) }.value
        guard !Task.isCancelled else { return }
        let need = model.placeSearcher != nil && PlaceSearcher.needsRemote(query, local: local, exact: exact)
        st.items = local.items
        st.assumed = exact ? nil : local.assumed
        st.status = need ? .busy : .idle
        update(st)
        guard need, let searcher = model.placeSearcher else { return }
        try? await Task.sleep(nanoseconds: photonDelayNs)
        guard !Task.isCancelled else { return }
        let r = await searcher.search(query, index: index, exact: exact)
        guard !Task.isCancelled, r.error != "aborted" else { return }
        st.items = r.items
        st.assumed = exact ? nil : r.assumed
        st.status = r.error != nil && r.items.isEmpty ? .err : .idle
        update(st)
    }
}

/// "Showing results for Regenstein" + "Search for “regensteen” instead" (or "Did you mean …?" in exact mode), above
/// the results card (spec J2).
struct AssumeNote: View {
    let state: PlaceUI
    let onExact: (Bool) -> Void
    var body: some View {
        if state.exact, let fix = state.fix {
            VStack(alignment: .leading, spacing: 0) {
                Text("Showing results for \u{201C}\(state.q)\u{201D}").font(Typo.rowDetail).foregroundStyle(Palette.label2)
                Button("Did you mean \(fix.to)?") { onExact(false) }.textButtonStyle(font: Typo.rowDetail.weight(.semibold))
            }
            .padding(.horizontal, Space.s1)
            .accessibilityElement(children: .contain)
        } else if !state.exact, let a = state.assumed, a.big {
            VStack(alignment: .leading, spacing: 0) {
                (Text("Showing results for ").foregroundStyle(Palette.label2) + Text(a.to).fontWeight(.semibold).foregroundStyle(Palette.label))
                    .font(Typo.rowDetail)
                Button("Search for \u{201C}\(a.from)\u{201D} instead") { onExact(true) }.textButtonStyle(font: Typo.rowDetail.weight(.semibold))
            }
            .padding(.horizontal, Space.s1)
            .accessibilityElement(children: .contain)
        }
    }
}

/// Results list for the "Type an address or place" fields (placesearch.js placeListHTML).
struct PlaceList: View {
    let state: PlaceUI
    let typed: String
    let errorTitle: String
    let errorBody: String
    let onPick: (PlaceHit) -> Void
    let onExact: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if PlaceIndex.norm(typed).count < 2 {
                Hint("Type at least 2 letters of an address, building or place.")
            } else {
                AssumeNote(state: state, onExact: onExact)
                if state.items.isEmpty {
                    if state.status == .busy { Hint("Searching places\u{2026}") }
                    else if state.status == .err { EmptyStateView(title: errorTitle, message: errorBody, icon: Sym.feedError) }
                    else if typed.trimmingCharacters(in: .whitespaces).count < 3 { Hint("Keep typing to search more places.") }
                    else { EmptyStateView(title: "No places found", message: "Check the spelling or try a nearby landmark.", icon: "mappin.slash") }
                } else {
                    Card {
                        ForEach(Array(state.items.enumerated()), id: \.offset) { item in
                            if item.offset > 0 { RowDivider() }
                            Button { onPick(item.element) } label: {
                                RowLayout {
                                    Image(systemName: "mappin").font(.system(size: IconSize.row)).foregroundStyle(Palette.label2)
                                        .accessibilityHidden(true)
                                } content: {
                                    Text(item.element.label).font(Typo.rowTitle).foregroundStyle(Palette.label).lineLimit(2)
                                    Text(item.element.sub.commaSeparated).font(Typo.rowDetail).foregroundStyle(Palette.label2).lineLimit(2)
                                } trailing: { EmptyView() }
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                    if state.status == .busy { Hint("Searching more places\u{2026}") }
                }
            }
        }
    }
}

/// The privacy line under every place-search field (same words as the web).
struct PhotonNote: View {
    var body: some View {
        Text("Places near campus are searched on this iPhone; otherwise only the text you type (or its spelling fix) is sent to photon.komoot.io.")
            .font(Typo.footnote).foregroundStyle(Palette.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s1)
    }
}

/// Secondary hint text (web .v-hint).
struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typo.rowDetail).foregroundStyle(Palette.label2).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s1)
    }
}

/// A search field inside the sheet (spec 10.2 / 10.8): magnifier, the field on `fill`, a clear button, 44 pt.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var identifier: String = ""
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass").font(.system(size: IconSize.status)).foregroundStyle(Palette.label2).accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .font(Typo.body)
                .foregroundStyle(Palette.label)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .frame(minHeight: Space.tap)
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: IconSize.status)).foregroundStyle(Palette.label3)
                        .frame(width: 32, height: Space.tap).contentShape(Rectangle())
                }
                .buttonStyle(ChromePressStyle())
                .accessibilityLabel("Clear")
            }
        }
        .padding(.leading, Space.s3)
        .padding(.trailing, Space.s1)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}
