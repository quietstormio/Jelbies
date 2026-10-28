//
//  PipWatchUITests.swift
//  Not a regression test: drives the REAL app into the room and keeps it there while the host records the simulator screen
//  (xcrun simctl io <udid> recordVideo). Env-gated: PIPWATCH_SECS (TEST_RUNNER_PIPWATCH_SECS) = how long to stay; PIPWATCH_ARGS = extra launch
//  arguments separated by spaces (e.g. "-WearForce beanie_honey"); PIPWATCH_MARK = a file written when the HUD is up (the host starts its clip there).
//

import XCTest

final class PipWatchUITests: XCTestCase {
    func testWatchRoom() throws {
        let env = ProcessInfo.processInfo.environment
        guard let secs = env["PIPWATCH_SECS"].flatMap(Double.init) else { throw XCTSkip("PIPWATCH_SECS not set") }
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "pip,moss,lavender"]
        if let extra = env["PIPWATCH_ARGS"], !extra.isEmpty { app.launchArguments += extra.split(separator: " ").map(String.init) }
        app.launch()
        let cont = app.buttons["Continue"]
        // (the title can still be fading in / the intro running: tap until Continue is really gone, the room is behind it)
        if cont.waitForExistence(timeout: 60) {
            for _ in 0..<12 {
                if cont.exists, cont.isHittable { cont.tap() }
                let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cont)
                if XCTWaiter().wait(for: [gone], timeout: 5) == .completed { break }
            }
        }
        XCTAssertTrue(app.buttons["care-menu"].waitForExistence(timeout: 90), "the HUD is up")
        if let mark = env["PIPWATCH_MARK"] { try? "up".write(toFile: mark, atomically: true, encoding: .utf8) }
        Thread.sleep(forTimeInterval: secs)
    }
}
