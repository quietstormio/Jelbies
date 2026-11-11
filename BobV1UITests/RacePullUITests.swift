//
//  RacePullUITests.swift
//  The REAL app (Release): a finger pulling down on the screen makes the Jelbie hop, the one-button assist's Hop button works, and -RaceControl taps still has the two foot buttons.
//  Optional env RP_OUT: a folder for the screenshots (PNG).
//

import XCTest

final class RacePullUITests: XCTestCase {
    private let home = ["-SetRoster", "pip,pearl", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "1024", "-NeedsHappy", "1", "-Mute", "1",
                        "-RaceStart", "1", "-RaceStartDelay", "3", "-RaceSeed", "7"]

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += home + extra
        app.launch()
        return app
    }

    /// Past the title screen's Continue (a cold launch can land there), then until the countdown has been on screen and is gone: the race is live.
    private func waitForGo(_ app: XCUIApplication, anchor: String) {
        let cont = app.buttons["Continue"]
        let anchorEl = element(app, anchor), count = element(app, "race-count")
        let start = Date()
        while !anchorEl.exists, Date().timeIntervalSince(start) < 120 {
            if cont.exists, cont.isHittable { cont.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(anchorEl.exists, "\(anchor) never appeared")
        XCTAssertTrue(count.waitForExistence(timeout: 30), "the countdown never showed")
        var t = 0.0
        while count.exists, t < 20 { Thread.sleep(forTimeInterval: 0.25); t += 0.25 }
        XCTAssertFalse(count.exists, "the countdown never ended")
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func hops(_ el: XCUIElement) -> Int {
        guard let v = el.value as? String, let n = Int(v.split(separator: " ").first ?? "") else { return -1 }
        return n
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let a = XCTAttachment(screenshot: shot); a.name = name; a.lifetime = .keepAlways; add(a)
        if let out = ProcessInfo.processInfo.environment["RP_OUT"], !out.isEmpty {
            try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }
    }

    @MainActor
    func testAFingerPullMakesHops() {
        let app = launch()
        waitForGo(app, anchor: "race-pull")
        let pad = element(app, "race-pull")
        XCTAssertTrue(pad.exists)
        save(app, "finger_0_go")
        let win = app.windows.element(boundBy: 0)
        let size = win.frame.size
        let dragMax = min(max(min(size.width, size.height) * 0.36, 110), 230)
        let start = win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        let end = start.withOffset(CGVector(dx: 0, dy: 0.8 * dragMax))
        for i in 1...6 {
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
            save(app, "finger_\(i)_after")
            Thread.sleep(forTimeInterval: 0.7)
        }
        let n = hops(pad)
        XCTAssertGreaterThanOrEqual(n, 4, "six pulls, at least four hops (the pad reports \(n))")
        app.terminate()
    }

    @MainActor
    func testTheHopButton() {
        let app = launch(["-A11yRaceAssist", "oneButton"])
        waitForGo(app, anchor: "race-hop")
        let hop = element(app, "race-hop")
        XCTAssertTrue(hop.exists)
        XCTAssertFalse(element(app, "race-pull").exists, "no pull pad with the one-button assist")
        for _ in 0..<5 { hop.tap(); Thread.sleep(forTimeInterval: 1.0) }
        let n = hops(hop)
        XCTAssertGreaterThanOrEqual(n, 3, "five presses, at least three hops (the button reports \(n))")
        save(app, "hopbutton")
        app.terminate()
    }

    @MainActor
    func testTapsStillHasItsButtons() {
        let app = launch(["-RaceControl", "taps"])
        waitForGo(app, anchor: "race-left")
        XCTAssertTrue(element(app, "race-left").exists)
        XCTAssertTrue(element(app, "race-right").exists)
        XCTAssertFalse(element(app, "race-pull").exists, "no pull pad in taps mode")
        app.terminate()
    }
}
