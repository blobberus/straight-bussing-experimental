import Foundation

/// The status banner's Retry, safe to tap again and again (owner 2026-11-03: "move the retry button to the left side of
/// the notification so if the user spams it while on a route, it doesn't shift and accidentally cancel their current
/// trip"). The Retry button sits in a fixed slot on the banner's leading side; this type decides what that slot and the
/// banner show:
/// - while the feed is in error, the live pill (Retry in the slot; a poll in flight shows progress there and ignores
///   further taps);
/// - when the feed comes back right after a Retry tap, the banner does NOT vanish at once: for `holdS` seconds after the
///   last tap it keeps its place, drawn as "recovered", so nothing under it (the trip chip and its Show all, which ends
///   the trip, or the sheet's header) can slide under a finger that keeps tapping. Each tap in that window extends it.
/// Pure (no clock of its own) so the rule is unit-tested and the same on the web (`docs/DESIGN-SPEC.md` 10.3).
public struct RetryHold: Equatable, Sendable {
    /// How long the banner keeps its place after the last Retry tap once the feed is back (seconds).
    public static let holdS = 2.5

    /// When Retry (or the held banner) was last tapped; -infinity = never.
    public private(set) var lastTap: Double = -.infinity
    /// The last banner shown while the feed was in trouble: what the held slot is drawn from.
    public private(set) var last: LiveText.Pill?

    public init() {}

    /// The banner to draw now.
    public struct Shown: Equatable, Sendable {
        public var pill: LiveText.Pill
        /// The feed is back; the banner only keeps its place (no action, taps absorbed).
        public var recovered: Bool
    }

    /// Note the pill the model shows now (call whenever it changes); a nil pill keeps the last one for the hold.
    public mutating func saw(_ pill: LiveText.Pill?) {
        if let pill { last = pill }
    }

    /// A tap on Retry, or on the held banner, at `now`.
    public mutating func tapped(now: Double) {
        lastTap = now
    }

    /// Is the hold running at `now` (a tap less than `holdS` ago)?
    public func holding(now: Double) -> Bool { now - lastTap < Self.holdS }

    /// What the banner shows for the live `pill` at `now`: the live pill, else the last one as "recovered" while the
    /// hold runs, else nothing.
    public func shown(_ pill: LiveText.Pill?, now: Double) -> Shown? {
        if let pill { return Shown(pill: pill, recovered: false) }
        if holding(now: now), let last { return Shown(pill: last, recovered: true) }
        return nil
    }

    /// When the hold ends (to look again then), nil when none is running.
    public func holdEnds(now: Double) -> Double? { holding(now: now) ? lastTap + Self.holdS : nil }
}
