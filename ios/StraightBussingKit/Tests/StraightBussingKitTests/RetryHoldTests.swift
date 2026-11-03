import XCTest
@testable import StraightBussingKit

/// The status banner's Retry, tapped again and again during a trip (owner 2026-11-03): the banner keeps its place for
/// `RetryHold.holdS` after the last tap even when the feed comes back, so nothing under it (the trip chip's Show all,
/// which ends the trip) slides under the finger.
final class RetryHoldTests: XCTestCase {
    let T = 1_800_000_000.0
    let err = LiveText.Pill(kind: .err, text: "Can't reach the shuttle feed. Retrying. Showing last known data.", retry: true)
    let late = LiveText.Pill(kind: .warn, text: "Live data delayed. Times may be off.", retry: false)

    func testLivePillAlwaysShowsAsIs() {
        var h = RetryHold()
        h.saw(err)
        XCTAssertEqual(h.shown(err, now: T), RetryHold.Shown(pill: err, recovered: false))
        h.tapped(now: T)
        XCTAssertEqual(h.shown(late, now: T + 1), RetryHold.Shown(pill: late, recovered: false), "a new live pill replaces the held one")
    }

    func testNoTapNoHold() {
        var h = RetryHold()
        h.saw(err)
        h.saw(nil)
        XCTAssertNil(h.shown(nil, now: T), "the feed came back without a Retry tap: the banner goes at once")
        XCTAssertNil(h.holdEnds(now: T))
    }

    func testFeedBackAfterRetryKeepsThePlace() {
        var h = RetryHold()
        h.saw(err)
        h.tapped(now: T)
        h.saw(nil)   // the retry worked
        XCTAssertEqual(h.shown(nil, now: T + 0.2), RetryHold.Shown(pill: err, recovered: true))
        XCTAssertEqual(h.shown(nil, now: T + RetryHold.holdS - 0.01)?.recovered, true)
        XCTAssertNil(h.shown(nil, now: T + RetryHold.holdS), "the place is given back once the finger stops")
        XCTAssertEqual(h.holdEnds(now: T + 1), T + RetryHold.holdS)
    }

    /// Five quick taps: Retry, then four on the held (recovered) banner. The banner stays the whole time and for holdS
    /// after the last tap; at no moment between the taps is there no banner (a gap would let the trip chip move up).
    func testRepeatedTapsDuringATripNeverLeaveAGap() {
        var h = RetryHold()
        h.saw(err)
        var t = T
        h.tapped(now: t)
        h.saw(nil)
        for _ in 0..<4 {
            for dt in stride(from: 0.0, through: 0.4, by: 0.05) {
                XCTAssertNotNil(h.shown(nil, now: t + dt), "a banner at +\(dt) s after a tap")
            }
            t += 0.4
            h.tapped(now: t)
        }
        XCTAssertEqual(h.shown(nil, now: t + RetryHold.holdS - 0.1)?.pill, err)
        XCTAssertNil(h.shown(nil, now: t + RetryHold.holdS + 0.1))
    }

    func testFeedFailsAgainDuringTheHold() {
        var h = RetryHold()
        h.saw(err)
        h.tapped(now: T)
        h.saw(nil)
        h.saw(err)
        XCTAssertEqual(h.shown(err, now: T + 1), RetryHold.Shown(pill: err, recovered: false), "back to Retry, in the same place")
    }
}
