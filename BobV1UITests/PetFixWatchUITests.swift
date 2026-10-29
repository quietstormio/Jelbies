//
//  PetFixWatchUITests.swift
//  Not a regression test: drives the REAL app through "call (one or everyone), pet by touch, let go" while the host records the simulator screen
//  (xcrun simctl io <udid> recordVideo). Env-gated: PETFIX_ARGS = launch arguments separated by spaces; PETFIX_PETS = "x,y;x,y" normalised points to stroke
//  (each stroke drags left-right over the point for ~3 s); PETFIX_AFTER = seconds to watch after the let-go; PETFIX_MARK = a file written at each step.
//

import XCTest

final class PetFixWatchUITests: XCTestCase {
    func testCallPetRelease() throws {
        let env = ProcessInfo.processInfo.environment
        guard let args = env["PETFIX_ARGS"] else { throw XCTSkip("PETFIX_ARGS not set") }
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "pip,moss,lavender"] + args.split(separator: " ").map(String.init)
        app.launch()
        let cont = app.buttons["menu-continue"]
        for _ in 0..<6 where cont.waitForExistence(timeout: 20) { cont.tap(); Thread.sleep(forTimeInterval: 4) }          // (the title takes a tap when it is ready: repeat until it is gone)
        func mark(_ s: String) { if let m = env["PETFIX_MARK"] { try? s.write(toFile: m, atomically: true, encoding: .utf8) } }
        XCTAssertTrue(app.buttons["focus-release"].waitForExistence(timeout: 120), "the close-up is up")
        Thread.sleep(forTimeInterval: 3)
        mark("focused")
        for pt in (env["PETFIX_PETS"] ?? "").split(separator: ";") {
            let v = pt.split(separator: ",").compactMap { Double($0) }
            guard v.count == 2 else { continue }
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: v[0] - 0.05, dy: v[1]))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: v[0] + 0.05, dy: v[1]))
            for _ in 0..<3 { a.press(forDuration: 0.6, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.2) }          // (a press-hold, then a slow rub: the pet gesture)
        }
        mark("petted")
        app.buttons["focus-release"].tap()
        mark("released")
        Thread.sleep(forTimeInterval: Double(env["PETFIX_AFTER"] ?? "20") ?? 20)
    }
}
