import XCTest

/// End-to-end smoke test on the demo build (simulated buses, fixed location): tabs, My Routes swipe actions,
/// Directions -> Start -> trip timeline, Settings. When the SB_SHOTS environment variable is set (CI passes
/// TEST_RUNNER_SB_SHOTS), screenshots of states the launch-argument screens cannot reach are saved there.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func save(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SB_SHOTS"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testMainFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        XCTAssertTrue(app.buttons["searchBar"].waitForExistence(timeout: 30), "search bar")
        let title = app.staticTexts["sheetTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Current trip")
        // -demo looks like real use (CI and App Store screenshots): no demo banner, no "Simulated buses" pill
        XCTAssertFalse(app.buttons["simulatedPill"].exists, "-demo shows no simulated-buses indicator")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Demo mode")).firstMatch.exists,
                       "no demo banner or demo alert anywhere")

        app.buttons["tab.routes"].tap()
        XCTAssertEqual(app.staticTexts["sheetTitle"].label, "Routes")
        // a confirmation toast (spec 10.19): every route is shown already, so Show all only confirms it
        let showAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Show all routes")).firstMatch
        if showAll.waitForExistence(timeout: 5) {
            showAll.tap()
            if app.buttons["busAlertBanner"].waitForExistence(timeout: 5) {
                let toast = app.buttons["busAlertBanner"].frame, grab = app.descendants(matching: .any)["sheetGrabber"].frame
                XCTAssertTrue(toast.maxY <= app.buttons["tab.routes"].frame.minY, "the toast sits above the bottom bar")
                XCTAssertTrue(toast.minY > grab.minY || toast.maxY < grab.minY, "never over the sheet's grab bar and title")
                save(app, "55-toast-light")
            }
        }

        app.buttons["tab.myroutes"].tap()
        XCTAssertEqual(app.staticTexts["sheetTitle"].label, "My Routes")
        let row = app.buttons["custom.demo-commute"]
        if row.waitForExistence(timeout: 5) {
            row.swipeLeft()
            XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5), "swipe reveals Details / Edit / Delete")
            XCTAssertTrue(app.buttons["Edit"].exists)
            XCTAssertTrue(app.buttons["Details"].exists)
            save(app, "12-myroutes-swipe-light")
            app.buttons["Delete"].tap()
            // iOS 17/18 show the confirmation as an action sheet with Cancel; iOS 26 as a popover without one
            // (a tap outside cancels). Either way it asks first and says what will happen.
            let message = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This custom route will be removed")).firstMatch
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(message.waitForExistence(timeout: 5) || cancel.exists, "delete asks for confirmation")
            save(app, "13-myroutes-delete-confirm-light")
            if cancel.exists {
                cancel.tap()
            } else if app.otherElements["PopoverDismissRegion"].exists {
                app.otherElements["PopoverDismissRegion"].tap()
            } else {
                // outside the popover, on a spot that is harmless if the tap gets through: the selected tab
                app.buttons["tab.myroutes"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: message)], timeout: 5)
            XCTAssertTrue(app.buttons["custom.demo-commute"].waitForExistence(timeout: 5), "cancel keeps the route")
        }

        app.buttons["tab.current"].tap()
        app.buttons["searchBar"].tap()
        let to = app.textFields["dirTo"]
        XCTAssertTrue(to.waitForExistence(timeout: 10), "destination field")
        // the fields are a card at the top of the expanded sheet, under its title (Apple Maps' search field at the top
        // of the card, DESIGN-SPEC-GLASS 9.2)
        let card = app.descendants(matching: .any)["directionsCard"]
        XCTAssertTrue(card.exists, "the Directions card")
        XCTAssertGreaterThanOrEqual(card.frame.minY, app.staticTexts["sheetTitle"].frame.maxY - 1, "the card sits under the sheet's title")
        to.tap()
        to.typeText("chipotle")
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Chipotle")).firstMatch
        if !suggestion.waitForExistence(timeout: 10) {
            save(app, "14-place-search-failed-light")
            XCTFail("local place suggestion; tree: " + app.debugDescription.replacingOccurrences(of: "\n", with: " | "))
            return
        }
        save(app, "14-place-search-light")
        save(app, "journey-1-search-light")
        suggestion.tap()
        let start = app.buttons["startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "an option with a bus and a Start button")
        // the place details step costs no tap: the destination's summary heads the options (docs/DESIGN-SPEC.md J3)
        XCTAssertTrue(app.descendants(matching: .any)["placeSummary"].exists, "the destination's place summary")
        save(app, "journey-2-options-light")
        start.tap()
        XCTAssertTrue(app.staticTexts["tripHeadline"].waitForExistence(timeout: 15), "trip progress timeline")
        save(app, "15-trip-started-light")
        save(app, "journey-3-trip-light")
        // collapsed during the trip: the header carries the current step and Arriving In, the map shows the trip
        app.descendants(matching: .any)["sheetGrabber"].tap()
        waitSheet(app, "Collapsed", "the trip sheet collapses")
        XCTAssertTrue(app.descendants(matching: .any)["arrivingIn"].waitForExistence(timeout: 10), "Arriving In in the collapsed header")
        sleep(2)
        save(app, "journey-4-trip-map-light")

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.buttons["searchBar"].waitForExistence(timeout: 10))
        // the search bar "exists" under the sheet too: wait until Settings has really gone before the next tap
        waitGone(app.navigationBars["Settings"], 10, "Settings closed")

        // Lines by Time (owner 2026-10-18): the clock next to the gear opens its sheet; Cancel changes nothing
        let clock = app.buttons["timeButton"]
        XCTAssertTrue(clock.waitForExistence(timeout: 10) && clock.isHittable, "the clock in the lower-right group")
        clock.tap()
        if !app.navigationBars["Lines by Time"].waitForExistence(timeout: 6) { clock.tap() }   // a tap lost to a settling sheet
        XCTAssertTrue(app.navigationBars["Lines by Time"].waitForExistence(timeout: 10), "Lines by Time sheet")
        save(app, "41-lines-by-time-light")
        app.buttons["timeCancel"].tap()
        XCTAssertTrue(app.buttons["searchBar"].waitForExistence(timeout: 10))
    }

    /// The glass layout (DESIGN-SPEC-GLASS 3, the "what moves where" table): the search circle at the trailing end of
    /// the tab bar's row under the collapsed card; Settings alone at the top right; Lines by Time over Locate riding
    /// above the card at the trailing edge; expanded, the group is gone and the bottom row stays.
    func testGlassLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        let search = app.buttons["searchBar"], gear = app.buttons["settingsButton"]
        let clock = app.buttons["timeButton"], locate = app.buttons["locateButton"]
        let grab = app.descendants(matching: .any)["sheetGrabber"]
        XCTAssertTrue(search.waitForExistence(timeout: 30), "the search circle")
        XCTAssertTrue(grab.waitForExistence(timeout: 10))
        XCTAssertEqual(sheetState(app), "Collapsed")
        let w = app.windows.firstMatch.frame
        let first = app.buttons["tab.current"].frame, last = app.buttons["tab.myroutes"].frame
        XCTAssertEqual(search.frame.midY, first.midY, accuracy: 6, "search sits on the tab bar's row: \(search.frame) vs \(first)")
        XCTAssertGreaterThan(search.frame.minX, last.maxX, "at its trailing end")
        XCTAssertGreaterThanOrEqual(search.frame.width, 44, "a 56 pt circle")
        XCTAssertGreaterThan(first.minY, grab.frame.maxY, "the bottom row under the collapsed card")
        XCTAssertTrue(gear.isHittable, "Settings")
        XCTAssertLessThan(gear.frame.maxY, w.midY, "Settings at the top")
        XCTAssertGreaterThan(gear.frame.midX, w.midX, "on the right")
        XCTAssertTrue(clock.isHittable && locate.isHittable, "Lines by Time and Locate on the map")
        XCTAssertLessThanOrEqual(clock.frame.maxY, locate.frame.minY + 1, "Lines by Time over Locate")
        XCTAssertLessThan(locate.frame.maxY, grab.frame.minY, "the group rides above the card")
        XCTAssertGreaterThan(locate.frame.midX, w.midX, "at the trailing edge")
        save(app, "61-glass-collapsed-light")
        grab.tap()
        waitSheet(app, "Expanded", "expanded")
        waitGone(clock, 5, "the lower-right group leaves while the sheet is expanded")
        XCTAssertTrue(search.isHittable, "the bottom row stays")
        XCTAssertTrue(gear.isHittable, "Settings stays")
        save(app, "62-glass-expanded-light")
    }

    /// A started trip ends when a stop's Directions picks a new destination (else "Trip to Chipotle" would follow a
    /// plan to another place). Regression test of the 2026-10-11 sweep.
    func testNewDestinationFromAStopEndsTheTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "tripstop"]
        app.launch()
        let directions = app.buttons["stopDirections"]
        XCTAssertTrue(directions.waitForExistence(timeout: 30), "a stop opened during a started trip")
        directions.tap()
        XCTAssertTrue(app.textFields["dirTo"].waitForExistence(timeout: 10), "Directions to the stop")
        app.buttons["tab.current"].tap()
        let noTrip = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "No trip in progress")).firstMatch
        XCTAssertTrue(noTrip.waitForExistence(timeout: 10), "the old trip ended")
        XCTAssertFalse(app.staticTexts["tripHeadline"].exists, "no timeline of the old trip")
    }

    /// Owner 2026-11-03: Retry tapped again and again while on a route must never shift the screen and end the trip by
    /// accident. `-feed flaky` starts a trip with live data, then fails the feed until Retry is tapped. Retry sits on the
    /// banner's leading side; six taps on the same screen point (the first one brings the feed back) keep the slot in
    /// place, the trip keeps running, and once the finger stops the banner gives its place back with the trip still on.
    func testRepeatedRetryDuringATripKeepsTheTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "trip", "-feed", "flaky", "-detent", "peek"]
        app.launch()
        let retry = app.buttons["bannerRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 45), "the feed fails during the trip: Retry in the status banner")
        let chip = app.descendants(matching: .any)["contextBar"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the trip chip (its Show all ends the trip)")
        let window = app.windows.firstMatch.frame
        let f0 = retry.frame
        let banner = app.descendants(matching: .any)["statusPill"]
        let b0 = banner.frame, c0 = chip.frame
        XCTAssertLessThan(f0.midX, window.midX, "Retry on the leading side: \(f0)")
        XCTAssertGreaterThan(c0.minY, b0.maxY, "the trip chip is under the banner")
        save(app, "53-retry-trip-light")
        let spot = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: f0.midX - window.minX, dy: f0.midY - window.minY))
        for _ in 0..<4 { spot.tap() }   // the same screen point every time, as a hurried finger would
        // the finger is still tapping: each check right after one more tap (a query takes a moment on a slow runner, and
        // the banner gives its place back 2.5 s after the last tap)
        let slot = app.buttons["bannerRetry"]
        spot.tap()
        let c1 = chip.frame
        XCTAssertEqual(c1.minY, c0.minY, accuracy: 1, "the trip chip (and its Show all) did not move")
        spot.tap()
        let b1 = banner.frame
        XCTAssertEqual(b1.minY, b0.minY, accuracy: 1, "the banner did not move")
        XCTAssertGreaterThanOrEqual(b1.height, b0.height - 1, "the banner did not shrink")
        spot.tap()
        XCTAssertTrue(slot.frame.contains(CGPoint(x: f0.midX, y: f0.midY)), "the tapped point is still on the slot: \(slot.frame) vs \(f0)")
        save(app, "54-retry-recovered-light")
        XCTAssertTrue(app.descendants(matching: .any)["arrivingIn"].exists, "the trip is still on (Arriving In in the header)")
        XCTAssertTrue(chip.exists, "the trip chip is still there")
        waitGone(slot, 10, "the banner gives its place back once the finger stops")
        XCTAssertTrue(app.descendants(matching: .any)["contextBar"].exists, "the trip was not ended")
        XCTAssertTrue(app.descendants(matching: .any)["arrivingIn"].exists, "the trip was not ended")
    }

    /// Turn a SwiftUI switch on: a tap on its trailing edge (the switch, not the label), then, if the value did not
    /// change (iOS 26 lays the row out differently), a tap on the inner switch control.
    func turnOn(_ toggle: XCUIElement, in app: XCUIApplication) -> Bool {
        func isOn(_ timeout: TimeInterval) -> Bool {
            let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
            return XCTWaiter.wait(for: [on], timeout: timeout) == .completed
        }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if isOn(3) { return true }
        // the list may have re-laid out (live alerts leave Settings when simulated buses start): find the switch again
        _ = reveal(toggle, in: app)
        if (toggle.value as? String) == "1" { return true }
        let inner = toggle.switches.firstMatch
        (inner.exists ? inner : toggle).tap()
        return isOn(5)
    }

    /// Scroll the screen until `e` is on screen and clear of the home indicator (Settings is long with live data: the
    /// operator's alerts, the bus alerts, the credits); up first, then back down. Lists drop rows that are off screen
    /// from the accessibility tree, so `exists` alone does not say where the row is.
    func reveal(_ e: XCUIElement, in app: XCUIApplication) -> Bool {
        let bottom = app.windows.firstMatch.frame.maxY - 140
        func ok() -> Bool { e.exists && e.isHittable && e.frame.maxY < bottom }
        var tries = 0
        while !ok() && tries < 24 { app.swipeUp(); tries += 1 }
        tries = 0
        while !ok() && tries < 24 { app.swipeDown(); tries += 1 }
        return ok()
    }

    func waitGone(_ e: XCUIElement, _ timeout: TimeInterval, _ why: String) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: e)
        gone.expectationDescription = why
        wait(for: [gone], timeout: timeout)
    }

    /// Settings > Simulated buses (demo), the way App Review would use it at night: off by default; while on, the
    /// status pill reads "Simulated buses" on every tab (no banner), a tap on it opens Settings at the switch, and the
    /// switch turns it off. Runs WITHOUT -demo (normal prefs; live feed requests).
    func testSimulatedBusesSwitch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["searchBar"].waitForExistence(timeout: 30), "search bar")
        let pill = app.buttons["simulatedPill"]
        XCTAssertFalse(pill.exists, "simulated buses are off by default")

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let toggle = app.switches["simulatedBuses"]
        XCTAssertTrue(reveal(toggle, in: app), "Settings has the Simulated buses switch")
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        XCTAssertTrue(turnOn(toggle, in: app), "the Simulated buses switch turns on")
        save(app, "23-simulated-settings-light")
        app.buttons["settingsDone"].tap()

        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the status pill says so on the map screen")
        XCTAssertTrue(pill.label.contains("Simulated buses"), "pill text: \(pill.label)")
        XCTAssertFalse(app.buttons["demoOff"].exists, "no demo banner with Turn off any more")
        waitGone(app.buttons["busAlertBanner"], 10, "the confirmation banner goes away")
        app.buttons["tab.routes"].tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "and on every tab")
        save(app, "24-simulated-routes-light")

        pill.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "the pill opens Settings")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "at the switch")
        XCTAssertTrue(reveal(toggle, in: app), "the switch on screen")
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if (toggle.value as? String) == "1" { (toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle).tap() }
        app.buttons["settingsDone"].tap()
        waitGone(pill, 10, "turning the switch off removes the pill")
    }

    /// The grab bar's state as VoiceOver reads it: "Collapsed" or "Expanded".
    func sheetState(_ app: XCUIApplication) -> String {
        (app.descendants(matching: .any)["sheetGrabber"].value as? String) ?? ""
    }

    func waitSheet(_ app: XCUIApplication, _ state: String, _ why: String) {
        let e = expectation(for: NSPredicate(format: "value == %@", state), evaluatedWith: app.descendants(matching: .any)["sheetGrabber"])
        e.expectationDescription = why
        wait(for: [e], timeout: 8)
    }

    /// The sheet's two states (owner spec 2026-10-12): it launches collapsed with the next bus in the title line; the
    /// whole header strip drags it (the title text, not only the grab bar), the release goes the way the finger last
    /// moved, and a tap on the grab bar toggles.
    func testHeaderStripMovesTheSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        let title = app.staticTexts["sheetTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertEqual(sheetState(app), "Collapsed", "launches collapsed")
        let next = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Next bus at the nearest stop")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 20), "the collapsed title line keeps the next bus")
        // drag up from the title text: expands
        let t = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        t.press(forDuration: 0.05, thenDragTo: t.withOffset(CGVector(dx: 0, dy: -300)))
        waitSheet(app, "Expanded", "a drag up on the title expands")
        // drag down from the grab bar: collapses
        let grab = app.descendants(matching: .any)["sheetGrabber"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grab.press(forDuration: 0.05, thenDragTo: grab.withOffset(CGVector(dx: 0, dy: 400)))
        waitSheet(app, "Collapsed", "a drag down on the grab bar collapses")
        // a drag that goes up and then back down a little: the last motion (down) wins
        let t2 = app.staticTexts["sheetTitle"].coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        t2.press(forDuration: 0.05, thenDragTo: t2.withOffset(CGVector(dx: 0, dy: -250)))
        waitSheet(app, "Expanded", "up again")
        // a tap on the grab bar toggles
        app.descendants(matching: .any)["sheetGrabber"].tap()
        waitSheet(app, "Collapsed", "a tap on the grab bar collapses")
        app.descendants(matching: .any)["sheetGrabber"].tap()
        waitSheet(app, "Expanded", "and expands")
        save(app, "35-sheet-expanded-light")
    }

    /// Current trip expanded (ship checklist item 3, owner decision 2026-10-11): the nearest stop and its next buses
    /// come first under the title and fit whole above the tab bar; the alert row, station search and Routes to station
    /// come after. Without a location, "Use my location" is first and the station search next.
    func testCurrentTripNextBusFirst() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sheetTitle"].waitForExistence(timeout: 30))
        app.descendants(matching: .any)["sheetGrabber"].tap()
        waitSheet(app, "Expanded", "expanded to read the list")
        let block = app.descendants(matching: .any)["nextBusBlock"]
        XCTAssertTrue(block.waitForExistence(timeout: 30), "the nearest stop with its next buses")
        let arrival = block.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "minute", "arriving now")).firstMatch
        XCTAssertTrue(arrival.waitForExistence(timeout: 20), "its arrivals loaded (not the loading rows)")
        let title = app.staticTexts["sheetTitle"], tab = app.buttons["tab.current"], search = app.textFields["nearbySearch"]
        XCTAssertTrue(search.exists)
        XCTAssertGreaterThanOrEqual(block.frame.minY, title.frame.maxY, "under the title")
        XCTAssertLessThanOrEqual(block.frame.maxY, tab.frame.minY, "fully visible above the tab bar: \(block.frame) vs tab bar \(tab.frame)")
        XCTAssertLessThan(block.frame.maxY, search.frame.minY, "the station search comes after the next bus")
        let pick = app.buttons["pickOpen"]
        XCTAssertTrue(pick.exists && pick.frame.minY > block.frame.maxY, "Routes to station comes after the next bus")

        app.terminate()
        app.launchArguments = ["-demo", "-noloc"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sheetTitle"].waitForExistence(timeout: 30))
        app.descendants(matching: .any)["sheetGrabber"].tap()
        waitSheet(app, "Expanded", "expanded")
        let useLoc = app.buttons["useMyLocation"]
        XCTAssertTrue(useLoc.waitForExistence(timeout: 30), "without a location: Use my location")
        let search2 = app.textFields["nearbySearch"]
        XCTAssertTrue(search2.exists)
        XCTAssertGreaterThanOrEqual(useLoc.frame.minY, app.staticTexts["sheetTitle"].frame.maxY)
        XCTAssertLessThan(useLoc.frame.maxY, search2.frame.minY, "Use my location first, the station search next")
        XCTAssertLessThanOrEqual(search2.frame.maxY, app.buttons["tab.current"].frame.minY, "both visible above the tab bar")
        XCTAssertFalse(app.descendants(matching: .any)["nextBusBlock"].exists)
    }

    /// Building and place names follow the rider's own zoom and pan (laid out again when the camera stops): shots for
    /// the gallery; the names are decorative and hidden from VoiceOver, so they are checked by eye there.
    func testMapNamesFollowZoomAndPan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sheetTitle"].waitForExistence(timeout: 30))
        XCTAssertEqual(sheetState(app), "Collapsed", "the map in view")
        sleep(3)
        let map = app.maps.firstMatch.exists ? app.maps.firstMatch : app.windows.firstMatch
        map.pinch(withScale: 2.5, velocity: 1.5)
        sleep(3)
        save(app, "39-map-zoomed-light")
        let c = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        c.press(forDuration: 0.1, thenDragTo: c.withOffset(CGVector(dx: -120, dy: 160)))
        sleep(3)
        save(app, "40-map-panned-light")
        XCTAssertTrue(app.buttons["searchBar"].exists, "the app is still on the map screen")
    }
}
