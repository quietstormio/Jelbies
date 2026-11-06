//
//  FocusGroupFramingUITests.swift
//  The snuggle close-up of two Jelbies ("Come here" on a 2-Jelbie roster): both bodies must be fully in frame, portrait and landscape.
//  Launch: -SetRoster teddy,panda -MainMenu 0. Screenshots go to HUDFIX_OUT.
//

import XCTest
import UIKit

final class FocusGroupFramingUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["HUDFIX_OUT"] ?? "/tmp/hudfix_ui"
    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }

    @MainActor
    func testPairCloseUpFramesBoth() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-Mute", "1", "-SetRoster", "teddy,panda", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "1024", "-ClockHour", "17"] + (ProcessInfo.processInfo.environment["HUDFIX_ARGS"]?.split(separator: " ").map(String.init) ?? [])
        app.launch()
        sleep(8)
        for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orient
            sleep(5)
            let menu = app.buttons["care-menu"], row = app.buttons["hud-call-all"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            menu.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.buttons["focus-release"].waitForExistence(timeout: 1200), "Let them go shows once they are lined up (\(name))")
            sleep(3); save("\(name)_pair")
            if ProcessInfo.processInfo.environment["HUDFIX_NOTICE"] != nil { sleep(2); save("\(name)_notice") }
            app.buttons["focus-release"].tap()
            sleep(4)
        }
    }

    @MainActor
    private func feedRow(_ name: String, extra: [String]) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-Mute", "1", "-SetRoster", "teddy,panda", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "1024", "-ClockHour", "17", "-NeedsReset", "1"] + extra
        app.launch()
        sleep(6)
        let menu = app.buttons["care-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()
        let feed = app.buttons["care-feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 5))
        feed.tap()
        sleep(5); save("\(name)_feed_row")
        XCTAssertFalse(app.buttons["care-food-berries"].exists); XCTAssertFalse(app.buttons["care-food-pizza"].exists)
    }
    @MainActor func testFeedRowOwnedOnly() throws { try feedRow("owned", extra: ["-StoreSeed", "1"]) }
    @MainActor func testFeedRowEmptyBag() throws { try feedRow("empty", extra: []) }
}
