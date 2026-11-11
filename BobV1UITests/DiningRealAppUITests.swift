//
//  DiningRealAppUITests.swift
//  Capture aid (off unless DINING_UI_OUT is set): the REAL app, three Jelbies AWAKE at noon (-ClockHour 12), hungry (fresh needs: -NeedsReset 1), then Feed from the care menu.
//  A host script (scripts-free: see the run notes in BASELINE.md) records the simulator video; this test only drives the taps and writes marks into DINING_UI_OUT:
//  ready.mark (picker open, waiting), then it waits for go.mark, taps the food and writes tap.epoch (wall-clock seconds), then sleeps DINING_UI_SECS and writes done.mark.
//  Env DINING_UI_KIND = feed (default) | drink.
//

import XCTest

final class DiningRealAppUITests: XCTestCase {
    @MainActor
    func testFeedAwake() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["DINING_UI_OUT"] else { throw XCTSkip("set TEST_RUNNER_DINING_UI_OUT") }
        let kind = env["DINING_UI_KIND"] ?? "feed", secs = Double(env["DINING_UI_SECS"] ?? "60") ?? 60
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        func mark(_ n: String, _ s: String = "") { try? s.write(toFile: "\(out)/\(n)", atomically: true, encoding: .utf8) }
        let app = XCUIApplication()
        app.launchArguments += ["-Mute", "1", "-SetRoster", "pip,moss,lavender", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-StoreSeed", "2", "-ClockHour", "12", "-NeedsReset", "1"]
        if let extra = env["DINING_UI_ARGS"], !extra.isEmpty { app.launchArguments += extra.split(separator: " ").map(String.init) }
        app.launch()
        sleep(12)          // (they settle and roam)
        let menu = app.buttons["care-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "care menu")
        if !app.buttons["care-feed"].exists { menu.tap(); sleep(1) }
        let (button, item) = kind == "drink" ? ("care-water", "care-drink-water") : ("care-feed", "care-food-sushi")
        let b = app.buttons[button]
        XCTAssertTrue(b.waitForExistence(timeout: 5), button)
        b.tap()
        let it = app.buttons[item]
        XCTAssertTrue(it.waitForExistence(timeout: 5), item)
        mark("ready.mark")
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: "\(out)/go.mark") { usleep(100_000) }
        it.tap()
        mark("tap.epoch", String(format: "%.3f", Date().timeIntervalSince1970))
        Thread.sleep(forTimeInterval: secs)
        mark("done.mark")
    }
}
