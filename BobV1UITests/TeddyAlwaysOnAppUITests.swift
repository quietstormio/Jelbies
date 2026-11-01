//
//  TeddyAlwaysOnAppUITests.swift
//  Not a regression test: the REAL app with Teddy through the scenes that used to drop his ears + pom (the bath and its exit run, bedtime, the park),
//  screenshots written to TEDDYON_DIR (env-gated). Debug build (NightIdle is a Debug aid).
//

import XCTest

final class TeddyAlwaysOnAppUITests: XCTestCase {
    private var dir = ""
    private let base = ["-NewGame", "bob,pearl,teddy", "-NewGameCoins", "10000", "-MainMenu", "0", "-ForceSpecies", "teddy"]

    private func launch(_ extra: [String]) throws -> XCUIApplication {
        guard let d = ProcessInfo.processInfo.environment["TEDDYON_DIR"], !d.isEmpty else { throw XCTSkip("TEDDYON_DIR not set") }
        dir = d
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments += base + extra
        app.launch()
        let cont = app.buttons["Continue"]
        if cont.waitForExistence(timeout: 20) { for _ in 0..<6 { if cont.exists, cont.isHittable { cont.tap() }; Thread.sleep(forTimeInterval: 2) } }
        return app
    }
    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
    }

    /// Clean: he runs out toward the camera (shots), the bath (shots), then the X.
    func testBathAndExitRun() throws {
        let app = try launch(["-BlobGameDemo", "gclean", "-GameAction", "clean", "-GameActionDelay", "6"])
        let cancel = app.buttons["bath-cancel"]
        for i in 0..<150 where !cancel.exists { Thread.sleep(forTimeInterval: 1.5); shot("0_runout_\(String(format: "%03d", i))") }
        XCTAssertTrue(cancel.exists, "the bath is up")
        Thread.sleep(forTimeInterval: 20)
        shot("1_bath_scrub"); Thread.sleep(forTimeInterval: 8); shot("1_bath_scrub_b")
        cancel.tap()
        for i in 0..<30 { Thread.sleep(forTimeInterval: 1.5); shot("2_exit_\(String(format: "%02d", i))") }
        _ = app.buttons["care-menu"].waitForExistence(timeout: 60)
        Thread.sleep(forTimeInterval: 15)
        shot("5_room_after")
    }

    /// The X while he is still running out: he runs back to his spot (exitBack).
    func testBathRunBack() throws {
        let app = try launch(["-BlobGameDemo", "gclean", "-GameAction", "clean", "-GameActionDelay", "6"])
        let cancel = app.buttons["bath-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 300), "the clean-up has started")
        cancel.tap()
        for i in 0..<40 { Thread.sleep(forTimeInterval: 1.5); shot("6_runback_\(String(format: "%02d", i))") }
    }

    func testBedtime() throws {
        let app = try launch(["-ClockHour", "22"])
        XCTAssertTrue(app.buttons["care-menu"].waitForExistence(timeout: 120))
        Thread.sleep(forTimeInterval: 15)
        app.buttons["care-menu"].tap()
        let bed = app.buttons["hud-bedtime"]
        XCTAssertTrue(bed.waitForExistence(timeout: 10), "Bedtime is in the menu")
        bed.tap()
        for i in 0..<45 { Thread.sleep(forTimeInterval: 3); shot("3_bed_\(String(format: "%02d", i))") }
    }

    func testPark() throws {
        let app = try launch(["-ClockHour", "12"])
        XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 120))
        Thread.sleep(forTimeInterval: 10)
        app.buttons["go-out"].tap()
        XCTAssertTrue(app.buttons["town-park"].waitForExistence(timeout: 10))
        app.buttons["town-park"].tap()
        XCTAssertTrue(app.buttons["park-go"].waitForExistence(timeout: 10))
        shot("4_park_picker")
        app.buttons["park-go"].tap()
        for i in 0..<60 {          // (the outing run, the fade, the walk in: slow in a Debug build)
            if app.buttons["park-home"].exists { break }
            Thread.sleep(forTimeInterval: 5); shot("4_park_walk_\(String(format: "%02d", i))")
        }
        XCTAssertTrue(app.buttons["park-home"].exists, "the park is up")
        Thread.sleep(forTimeInterval: 10)
        for i in 0..<30 { Thread.sleep(forTimeInterval: 3); shot("4_park_\(String(format: "%02d", i))") }
    }
}
