//
//  CallAllCaptureUITests.swift
//  The bottom-centre "Come here" pill (calls everyone): before the tap, mid-walk, lined up, released. Portrait and landscape.
//  Launch: -NewGame bob,pearl,teddy -NewGameCoins 10000 -MainMenu 0. Screenshots go to CALLALL_OUT.
//

import XCTest
import UIKit

final class CallAllCaptureUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["CALLALL_OUT"] ?? "/tmp/callall_ui"
    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }

    @MainActor
    func testCallEveryone() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "bob,pearl,teddy", "-NewGameCoins", "10000", "-MainMenu", "0"]
        app.launch()
        sleep(8)
        let only = ProcessInfo.processInfo.environment["CALLALL_ONLY"]
        for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] where only == nil || only == name {
            if only != nil && name == "landscape" { try landscapeBlind(app, orient); continue }
            XCUIDevice.shared.orientation = orient
            sleep(5)
            let pill = app.buttons["hud-call-all"]
            XCTAssertTrue(pill.waitForExistence(timeout: 10), "the pill shows (\(name))")
            XCTAssertGreaterThanOrEqual(pill.frame.height, 44)
            XCTAssertEqual(pill.label, "Call everyone")
            save("\(name)_1_before")
            app.buttons["care-menu"].tap()
            sleep(1)
            XCTAssertFalse(pill.exists, "hidden while the paw menu is open (\(name))")
            save("\(name)_1b_menu")
            app.buttons["care-menu"].tap()
            sleep(1)
            XCTAssertTrue(pill.waitForExistence(timeout: 5))
            pill.tap()
            sleep(1)
            save("\(name)_2_midwalk")
            XCTAssertTrue(app.buttons["focus-release"].waitForExistence(timeout: 420), "Let them go shows once they are lined up (\(name))")
            sleep(2)
            save("\(name)_3_lined")
            XCTAssertFalse(pill.exists)
            app.buttons["focus-release"].tap()
            sleep(3)
            save("\(name)_4_released")
            XCTAssertTrue(pill.waitForExistence(timeout: 10), "the pill is back after release (\(name))")
        }
    }

    /// The Debug simulator's main thread is too busy for element queries during the walk: fixed waits and coordinate taps instead.
    @MainActor
    private func landscapeBlind(_ app: XCUIApplication, _ orient: UIDeviceOrientation) throws {
        XCUIDevice.shared.orientation = orient
        sleep(6)
        save("landscape_1_before")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()          // the pill (bottom centre)
        sleep(1); save("landscape_2_midwalk")
        sleep(150); save("landscape_3_lined")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.09)).tap()          // Let them go (top left)
        sleep(6); save("landscape_4_released")
    }
}
