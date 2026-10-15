//
//  BobV1UITests.swift
//  BobV1UITests
//
//  Created by Dione Marshall on 10/12/26.
//

import XCTest

final class BobV1UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launchArguments += ["-MelonStudio", "1"]
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    /// A one-finger drag that starts on the stage must not scroll the compact page; a drag on the masthead must.
    @MainActor
    func testStageDragDoesNotScrollPage() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone-layout only")
        let app = XCUIApplication()
        app.launchArguments += ["-MelonStudio", "1"]
        app.launch()
        let stage = app.otherElements["melon-stage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        let chip = app.descendants(matching: .any)["status-chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        let y0 = chip.frame.minY

        let a = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let b = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        a.press(forDuration: 0.1, thenDragTo: b)
        sleep(1)
        XCTAssertEqual(chip.frame.minY, y0, accuracy: 1, "page scrolled while dragging the stage")

        // control: dragging on the masthead scrolls the page
        // (the stage starts at about 31% of the window height now that the masthead is short, so start inside the copy)
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let up = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
        top.press(forDuration: 0.1, thenDragTo: up)
        sleep(1)
        XCTAssertLessThan(chip.frame.minY, y0 - 20, "control drag outside the stage should scroll")
    }

    // MARK: - Panel controls

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-MelonStudio", "1"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["status-chip"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Swipes the page up (starting outside the stage) until the element is hittable.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ id: String) {
        let e = el(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 10), "\(id) missing")
        var n = 0
        while !e.isHittable && n < 8 {
            let win = app.windows.firstMatch
            let from = win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            let to = win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            // On compact layouts the bottom of the screen is the panel/notes area, not the stage.
            if app.windows.firstMatch.frame.width > 700 { break }
            from.press(forDuration: 0.05, thenDragTo: to)
            n += 1
        }
    }

    private func num(_ s: String) -> Double? {
        let m = s.split(separator: " ").first.map(String.init) ?? s
        return Double(m.replacingOccurrences(of: "≈", with: ""))
    }

    @MainActor
    func testPauseToggle() throws {
        let app = launch()
        let chip = el(app, "status-chip")
        reveal(app, "btn-pause")
        let live = NSPredicate(format: "label CONTAINS[c] 'LIVE'")
        expectation(for: live, evaluatedWith: chip)
        waitForExpectations(timeout: 10)
        el(app, "btn-pause").tap()
        expectation(for: NSPredicate(format: "label CONTAINS[c] 'PAUSED'"), evaluatedWith: chip)
        waitForExpectations(timeout: 5)
        el(app, "btn-pause").tap()
        expectation(for: live, evaluatedWith: chip)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testNudgeDecays() throws {
        let app = launch()
        reveal(app, "btn-nudge")
        let kin = el(app, "stat-kinetic")
        sleep(3)
        el(app, "btn-nudge").tap()
        var peak = 0.0
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 1.5 {
            peak = max(peak, num(kin.value as? String ?? "") ?? 0)
            if peak > 0 { break }
        }
        XCTAssertGreaterThan(peak, 0, "kinetic never rose after nudge")
        let settled = NSPredicate { _, _ in (self.num(kin.value as? String ?? "") ?? 99) < 0.5 }
        expectation(for: settled, evaluatedWith: nil)
        // Measured in an optimised harness (firmness 0.33): the readout last exceeds 0.5 uJ at ~4.4 s of sim time
        // (Bob is softer and bigger than the old melon slice, and the energy sloshes back and forth before it dies).
        // The unoptimised Debug sim in the UI-test simulator runs ~3x slower than real time (readout still
        // ~12 uJ after 14 s wall), so allow 30 s wall. The sim now runs at most 2 fixed steps per frame (was 3), which slows this
        // Debug-only case further (~16% of real time), so the wall timeout is 60 s.
        waitForExpectations(timeout: 60)
    }

    @MainActor
    func testHopAroundToggle() throws {
        let app = launch()
        reveal(app, "btn-hop")
        let hop = el(app, "btn-hop")
        XCTAssertEqual(hop.label, "Hop around")
        hop.tap()
        XCTAssertEqual(hop.label, "Stop hopping")
        let kin = el(app, "stat-kinetic")
        var peak = 0.0
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 4.5 { peak = max(peak, num(kin.value as? String ?? "") ?? 0) }
        XCTAssertGreaterThan(peak, 0, "kinetic never rose while hopping")
        XCTAssertTrue(app.state == .runningForeground)
        hop.tap()
        XCTAssertEqual(hop.label, "Hop around")
        XCTAssertTrue(app.state == .runningForeground)
    }

    @MainActor
    func testControlsKeepVolumeStable() throws {
        let app = launch()
        reveal(app, "swatch-yellow")
        func checkVolume(_ what: String, settle: UInt32 = 1) {
            sleep(settle)
            let v = num(el(app, "stat-volume").value as? String ?? "") ?? -1
            XCTAssertGreaterThanOrEqual(v, 95, "volume after \(what)")
            XCTAssertLessThanOrEqual(v, 105, "volume after \(what)")
        }
        el(app, "swatch-yellow").tap(); checkVolume("yellow")
        for id in ["swatch-pink", "swatch-blue"] { reveal(app, id); el(app, id).tap(); checkVolume(id) }
        reveal(app, "btn-reset"); el(app, "btn-reset").tap(); checkVolume("reset", settle: 4) // reset re-drops the body; landing squash briefly dips to ~94%
        reveal(app, "toggle-slow"); el(app, "toggle-slow").tap(); checkVolume("slow on")
        el(app, "toggle-slow").tap(); checkVolume("slow off")
        reveal(app, "toggle-mesh"); el(app, "toggle-mesh").tap(); checkVolume("mesh on")
        el(app, "toggle-mesh").tap(); checkVolume("mesh off")
        XCTAssertTrue(app.state == .runningForeground)
    }

    @MainActor
    private func dragSlider(_ id: String, initial: String, endX: Double = 0.97) throws {
        let app = launch()
        reveal(app, id)
        let s = el(app, id)
        XCTAssertEqual(s.value as? String, initial)
        let chip = el(app, "status-chip")
        let y0 = s.frame.minY
        let chipY0 = chip.frame.minY
        let f = s.frame
        let thumb = s.coordinate(withNormalizedOffset: CGVector(dx: (6.5 + Double(initial)! * (f.width - 13)) / f.width, dy: 0.5))
        let end = s.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5))
        thumb.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        XCTAssertNotEqual(s.value as? String, initial, "slider did not change")
        XCTAssertEqual(s.frame.minY, y0, accuracy: 2, "page scrolled during slider drag")
        _ = chipY0
        let v = Double(s.value as? String ?? "0") ?? 0
        if endX > 0.5 { XCTAssertGreaterThan(v, 0.8) } else { XCTAssertLessThan(v, 0.6) }
    }

    // Firmness now defaults to 0.95 (near the top of the track), so drag toward the left instead.
    @MainActor
    func testFirmnessSliderDrag() throws {
        try dragSlider("slider-firmness", initial: "0.95", endX: 0.3)
    }

    @MainActor func testDampingSliderDrag() throws {
        let app = launch()
        reveal(app, "slider-damping")
        let initial = el(app, "slider-damping").value as? String ?? ""
        app.terminate()
        try dragSlider("slider-damping", initial: initial)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Game mode: the care button expands into Feed / Water / Call and collapses after choosing. Feed and Water are
    /// independent: each is disabled only while its own bowl is out. All waits are condition based (no fixed timings).
    @MainActor
    func testCareMenuFeedWaterCall() throws {
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["care-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        let feed = app.buttons["care-feed"], water = app.buttons["care-water"], call = app.buttons["care-call"]
        XCTAssertFalse(feed.exists, "collapsed menu hides its actions")

        func waitFor(_ format: String, _ element: XCUIElement, _ timeout: TimeInterval = 20, _ message: String) {
            let e = expectation(for: NSPredicate(format: format), evaluatedWith: element)
            XCTAssertEqual(XCTWaiter().wait(for: [e], timeout: timeout), .completed, message)
        }
        func open() {
            menu.tap()
            XCTAssertTrue(feed.waitForExistence(timeout: 10), "menu expands")
            XCTAssertTrue(water.exists)
            XCTAssertTrue(call.exists)
        }
        func choose(_ b: XCUIElement) {
            b.tap()
            waitFor("exists == false", b, 10, "menu collapses after choosing")
        }

        open()
        XCTAssertTrue(feed.isEnabled && water.isEnabled && call.isEnabled)
        choose(feed)

        // food bowl is out: Feed is disabled, Water and Call are not
        open()
        waitFor("isEnabled == false", feed, 10, "Feed is disabled while the food bowl is out")
        XCTAssertTrue(water.isEnabled, "Water is independent of the food bowl")
        XCTAssertTrue(call.isEnabled)
        choose(water)

        // both bowls are out: call him over; he comes, waves, then goes back to the bowls
        open()
        waitFor("isEnabled == false", water, 10, "Water is disabled while the water bowl is out")
        XCTAssertFalse(feed.isEnabled)
        choose(call)

        // every bowl retires eventually (finished or the 45 s timeout): both buttons come back
        open()
        waitFor("isEnabled == true", feed, 180, "Feed is available again once the food bowl is gone")
        waitFor("isEnabled == true", water, 180, "Water is available again once the water bowl is gone")
        choose(water)
    }
}
