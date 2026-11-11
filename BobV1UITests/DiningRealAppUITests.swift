//
//  DiningRealAppUITests.swift
//  Capture aid (off unless DINING_UI_OUT is set): the REAL app, three Jelbies put to bed at night (-SleepNow 1 -ClockHour 3), then Feed (or Drink) from the care menu and a screenshot every ~0.5 s for 40 s,
//  with the wall-clock offset in the file name. Mode (env DINING_UI_MODE): gather = last week's flow (trayFirst false, soft wake off); first = tray-first, instant wake; firstsoft = tray-first + soft wake.
//  Run: TEST_RUNNER_DINING_UI_OUT=<dir> TEST_RUNNER_DINING_UI_MODE=first TEST_RUNNER_DINING_UI_KIND=feed xcodebuild test-without-building ... -only-testing:BobV1UITests/DiningRealAppUITests/testFeedAtNight
//

import XCTest
import UIKit

final class DiningRealAppUITests: XCTestCase {
    @MainActor
    func testFeedAtNight() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["DINING_UI_OUT"] else { throw XCTSkip("set TEST_RUNNER_DINING_UI_OUT") }
        let mode = env["DINING_UI_MODE"] ?? "first", kind = env["DINING_UI_KIND"] ?? "feed"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments += ["-Mute", "1", "-SetRoster", "pip,moss,lavender", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-StoreSeed", "2", "-ClockHour", "3", "-SleepNow", "1"]
        if mode == "gather" { app.launchEnvironment["DINING_GATHER"] = "1" }
        if mode == "firstsoft" { app.launchEnvironment["DINING_SOFT"] = "1" }
        app.launch()
        sleep(30)          // (they walk to bed and fall asleep)
        func shot(_ name: String) { try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(name).png")) }
        shot("00_before_menu")
        let menu = app.buttons["care-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "care menu")
        if !app.buttons["care-feed"].exists { menu.tap(); sleep(1) }
        let (button, item) = kind == "drink" ? ("care-water", "care-drink-water") : ("care-feed", "care-food-sushi")
        let b = app.buttons[button]
        XCTAssertTrue(b.waitForExistence(timeout: 5), button)
        b.tap()
        let it = app.buttons[item]
        XCTAssertTrue(it.waitForExistence(timeout: 5), item)
        shot("01_picker")
        let t0 = Date()
        it.tap()
        var n = 0
        while Date().timeIntervalSince(t0) < 40 {
            let t = Date().timeIntervalSince(t0)
            shot(String(format: "f%03d_t%05.1f", n, t)); n += 1
        }
        print("DININGUI frames \(n) over 40 s")
    }
}
