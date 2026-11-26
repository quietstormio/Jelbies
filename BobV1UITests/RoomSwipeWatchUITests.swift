//
//  RoomSwipeWatchUITests.swift
//  Not a regression test: drives the REAL app through the room swipe (left, right, to the limit, wait for the ease-back) while the host records the
//  simulator screen. Env-gated: SWIPE_ARGS = launch arguments separated by spaces; SWIPE_MARK = a file written at each step.
//

import XCTest

final class RoomSwipeWatchUITests: XCTestCase {
    func testSwipeLeftRightLimitReturn() throws {
        let env = ProcessInfo.processInfo.environment
        guard let args = env["SWIPE_ARGS"] else { throw XCTSkip("SWIPE_ARGS not set") }
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "pip,moss,lavender"] + args.split(separator: " ").map(String.init)
        app.launch()
        let cont = app.buttons["menu-continue"]
        for _ in 0..<6 where cont.waitForExistence(timeout: 20) { cont.tap(); Thread.sleep(forTimeInterval: 4) }
        func mark(_ s: String) { if let m = env["SWIPE_MARK"] { try? s.write(toFile: m, atomically: true, encoding: .utf8) } }
        Thread.sleep(forTimeInterval: 6)
        mark("ready")
        func swipe(_ x0: Double, _ x1: Double, y: Double = 0.30, y1: Double? = nil) {
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: x0, dy: y))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: x1, dy: y1 ?? y))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        if env["SWIPE_CORNERS_ONLY"] == nil {
        swipe(0.8, 0.3); mark("left"); Thread.sleep(forTimeInterval: 2)          // finger left
        swipe(0.2, 0.8); mark("right"); Thread.sleep(forTimeInterval: 2)         // finger right
        swipe(0.1, 0.95); swipe(0.1, 0.95); mark("limit"); Thread.sleep(forTimeInterval: 1.5)          // past the limit: the band
        Thread.sleep(forTimeInterval: 6); mark("returned")          // 4 s idle + 0.8 s ease home
        }
        // pitch: a vertical drag, a diagonal, then the four corners at the limits (each held, then the ease home)
        if env["SWIPE_CORNERS_ONLY"] == nil {
        swipe(0.5, 0.5, y: 0.25, y1: 0.55); mark("vert-down"); Thread.sleep(forTimeInterval: 1.5)
        swipe(0.5, 0.5, y: 0.55, y1: 0.20); swipe(0.5, 0.5, y: 0.55, y1: 0.20); mark("vert-up"); Thread.sleep(forTimeInterval: 1.5)
        swipe(0.7, 0.4, y: 0.25, y1: 0.50); mark("diag"); Thread.sleep(forTimeInterval: 6)
        }
        for (name, x0, x1, y0, y1) in [("c-left-down", 0.9, 0.05, 0.15, 0.65), ("c-left-up", 0.9, 0.05, 0.65, 0.15),
                                       ("c-right-down", 0.1, 0.95, 0.15, 0.65), ("c-right-up", 0.1, 0.95, 0.65, 0.15)] {
            swipe(x0, x1, y: y0, y1: y1); swipe(x0, x1, y: y0, y1: y1); swipe(x0, x1, y: y0, y1: y1)
            Thread.sleep(forTimeInterval: 1.2); mark(name); Thread.sleep(forTimeInterval: 6.5)
        }
        swipe(0.5, 0.5, y: 0.30)          // a plain press on empty space: nothing happens
        Thread.sleep(forTimeInterval: 3)
        XCUIDevice.shared.orientation = .landscapeLeft          // a phone on its side: the same corners
        Thread.sleep(forTimeInterval: 4); mark("landscape")
        for (name, x0, x1, y0, y1) in [("l-left-down", 0.9, 0.05, 0.15, 0.85), ("l-left-up", 0.9, 0.05, 0.85, 0.15),
                                       ("l-right-down", 0.1, 0.95, 0.15, 0.85), ("l-right-up", 0.1, 0.95, 0.85, 0.15)] {
            swipe(x0, x1, y: y0, y1: y1); swipe(x0, x1, y: y0, y1: y1); swipe(x0, x1, y: y0, y1: y1)
            Thread.sleep(forTimeInterval: 1.2); mark(name); Thread.sleep(forTimeInterval: 6.5)
        }
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
    }
}
