//
//  CallAllCaptureUITests.swift
//  The heart menu's "Come here" row (calls everyone): menu closed, menu open, mid-walk, lined up, released. Portrait and landscape.
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
        app.launchArguments += (ProcessInfo.processInfo.environment["CALLALL_HOUR"].map { ["-ClockHour", $0] } ?? []) + ["-NewGame", "bob,pearl,teddy", "-NewGameCoins", "10000", "-MainMenu", "0"]
        app.launch()
        sleep(8)
                for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            if let only = ProcessInfo.processInfo.environment["CALLALL_ONLY"], only != name { continue }
            XCUIDevice.shared.orientation = orient
            sleep(5)
            let menu = app.buttons["care-menu"], row = app.buttons["hud-call-all"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            XCTAssertFalse(row.exists, "the row is folded away with the menu closed (\(name))")
            save("\(name)_1_before")
            menu.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5), "the heart menu has the Come here row (\(name))")
            XCTAssertEqual(row.label, "Call everyone")
            XCTAssertTrue(app.buttons["care-feed"].exists)
            XCTAssertGreaterThan(row.frame.minY, app.buttons["hud-bedtime"].frame.minY, "Come here is the last row, below Bedtime (\(name))")
            sleep(1); save("\(name)_2_menu")
            if ProcessInfo.processInfo.environment["CALLALL_MENUONLY"] != nil { menu.tap(); sleep(1); continue }
            row.tap()
            if name == "landscape" { sleep(1); save("\(name)_3_midwalk"); sleep(150); save("\(name)_4_lined")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.09)).tap(); sleep(6); save("\(name)_5_released"); continue }
            sleep(1); save("\(name)_3_midwalk")
            XCTAssertTrue(app.buttons["focus-release"].waitForExistence(timeout: 420), "Let them go shows once they are lined up (\(name))")
            sleep(2); save("\(name)_4_lined")
            XCTAssertFalse(row.exists)
            app.buttons["focus-release"].tap()
            sleep(3); save("\(name)_5_released")
        }
    }
}
