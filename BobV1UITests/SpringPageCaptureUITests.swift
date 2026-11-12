//
//  SpringPageCaptureUITests.swift
//  Capture aid, not a regression test: the Jelly Spring species page (design B) in the real app. Per species page 0...6 and card tab 0...2 one screenshot, saved as an
//  XCTAttachment "spring_p<i>_t<t>_<portrait|landscape>" (and as a PNG in SPRING_OUT when that is set). Plus the first-gift page (".first" mode), a shot after
//  tapping the colour dot `picker-dot-3` (the dots are buttons) and one after tapping the big button once (the pick step still follows). Only captures: no pixel asserts.
//  Env (through xcodebuild: TEST_RUNNER_SPRING_ORIENT=landscape ...): SPRING_ORIENT = portrait (default) | landscape, SPRING_OUT = a folder for the PNGs (optional).
//  Skips unless SPRING_CAPTURE=1 (TEST_RUNNER_SPRING_CAPTURE=1) is set, so a normal UI-test run never launches it.
//

import XCTest

final class SpringPageCaptureUITests: XCTestCase {
    private var landscape: Bool { ProcessInfo.processInfo.environment["SPRING_ORIENT"] == "landscape" }
    private var orientName: String { landscape ? "landscape" : "portrait" }

    /// Launch arguments every shot shares (simulator capture flags of the app; see AdoptionCenter.swift / StartFlow.swift).
    private let base = ["-MainMenu", "0", "-SkipIntro", "1", "-Mute", "1", "-ClockHour", "12"]

    private func launch(_ extra: [String]) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments += base + extra
        app.launch()
        return app
    }

    /// Waits for the page (the big button of the species step), then lets the Jelbie land and settle.
    private func waitForPage(_ app: XCUIApplication) {
        let b = meet(app)
        if !b.waitForExistence(timeout: 300) { print("SPRING_DUMP " + app.debugDescription) }
        XCTAssertTrue(b.exists, "the species page never came up")
        sleep(7)
    }

    /// A button by accessibility id, else by the start of its label (the page's container id may hide the buttons' own ids from the query).
    private func button(_ app: XCUIApplication, id: String, label: String) -> XCUIElement {
        let byID = app.buttons[id]
        if byID.exists { return byID }
        return app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }
    private func meet(_ app: XCUIApplication) -> XCUIElement { button(app, id: "adopt-meet", label: "Meet the three") }

    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
        if let dir = ProcessInfo.processInfo.environment["SPRING_OUT"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }

    private var enabled: Bool { ProcessInfo.processInfo.environment["SPRING_CAPTURE"] == "1" }

    /// Seven pages x three tabs, "more" mode (the Jelly Spring): the roster is Bob + Teddy, so the button says "Room for 1 more at home".
    @MainActor
    func testAllPagesAndTabs() throws {
        try XCTSkipUnless(enabled, "SPRING_CAPTURE=1 not set")
        for page in 0...6 {
            let app = launch(["-NewGame", "bob,teddy", "-NewGameCoins", "1024",
                              "-PickerMode", "more", "-PickerPage", String(page), "-PickerTab", "0"])
            waitForPage(app)
            shoot("spring_p\(page)_t0_\(orientName)")
            for (t, id, lab) in [(1, "picker-tab-traits", "Traits"), (2, "picker-tab-moves", "Already knows")] {
                let tab = button(app, id: id, label: lab)
                XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(id) is missing")
                tab.tap()
                sleep(2)
                shoot("spring_p\(page)_t\(t)_\(orientName)")
            }
            app.terminate()
        }
    }

    /// The free first gift (".first" mode, no home): the button shows the title only, centred.
    @MainActor
    func testFirstMode() throws {
        try XCTSkipUnless(enabled, "SPRING_CAPTURE=1 not set")
        let app = launch(["-ResetForAdoption", "1", "-PickerPage", "0", "-PickerTab", "0"])
        waitForPage(app)
        shoot("spring_first_t0_\(orientName)")
        app.terminate()
    }

    /// Tapping the fourth colour dot moves to the fourth species (Matcha): proves the dots are buttons.
    @MainActor
    func testDotTap() throws {
        try XCTSkipUnless(enabled, "SPRING_CAPTURE=1 not set")
        let app = launch(["-NewGame", "bob,teddy", "-NewGameCoins", "1024", "-PickerMode", "more", "-PickerPage", "0", "-PickerTab", "0"])
        waitForPage(app)
        shoot("spring_dottap_before_\(orientName)")
        let dot = button(app, id: "picker-dot-3", label: "Matcha")
        XCTAssertTrue(dot.waitForExistence(timeout: 10), "picker-dot-3 is missing")
        dot.tap()
        sleep(7)
        shoot("spring_dottap_after_\(orientName)")
        app.terminate()
    }

    /// One tap on the big button: the pick step ("This one!" / the three Jelbies) still appears (the flow is unchanged).
    @MainActor
    func testCtaOnce() throws {
        try XCTSkipUnless(enabled, "SPRING_CAPTURE=1 not set")
        let app = launch(["-NewGame", "bob,teddy", "-NewGameCoins", "1024", "-PickerMode", "more", "-PickerPage", "3", "-PickerTab", "0"])
        waitForPage(app)
        meet(app).tap()
        XCTAssertTrue(button(app, id: "adopt-pick", label: "This one").waitForExistence(timeout: 20), "the pick step did not appear after the big button")
        sleep(7)
        shoot("spring_cta_after_\(orientName)")
        app.terminate()
    }
}
