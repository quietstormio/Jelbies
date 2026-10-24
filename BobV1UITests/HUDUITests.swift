//
//  HUDUITests.swift
//  The one main control: group controls (nobody highlighted), individual controls (a Jelbie highlighted), Go out opens the Town. Portrait and landscape.
//  HUD_TAP_P / HUD_TAP_L = "x,y" as fractions of the screen (TEST_RUNNER_HUD_TAP_P ...): where a Jelbie stands. HUD_FLOOR_P / HUD_FLOOR_L: empty floor.
//  Without them the test only checks the group menu and Go out. Screenshots go to HUD_OUT (default /tmp/hud_ui).
//

import XCTest
import UIKit

final class HUDUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["HUD_OUT"] ?? "/tmp/hud_ui"

    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    private func frac(_ key: String) -> CGVector? {
        guard let s = ProcessInfo.processInfo.environment[key] else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0) }
        return p.count == 2 ? CGVector(dx: p[0], dy: p[1]) : nil
    }

    @MainActor
    func testGroupIndividualAndGoOut() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-BlobCount", "3", "-BlobNoWander", "1"]
        app.launch()
        sleep(6)
        for (orient, tap, floor, name) in [(UIDeviceOrientation.portrait, "HUD_TAP_P", "HUD_FLOOR_P", "portrait"), (.landscapeLeft, "HUD_TAP_L", "HUD_FLOOR_L", "landscape")] {
            XCUIDevice.shared.orientation = orient
            sleep(6)
            let menu = app.buttons["care-menu"]
            XCTAssertTrue(app.buttons["go-out"].exists && menu.exists, "Go out and the main control show (\(name))")
            XCTAssertFalse(app.buttons["select-chip"].exists, "no Play-with chip")
            save("\(name)_1_closed")
            menu.tap()
            XCTAssertTrue(app.buttons["hud-bedtime"].waitForExistence(timeout: 5), "group controls (\(name))")
            XCTAssertFalse(app.buttons["hud-dress"].exists)
            save("\(name)_2_group")
            menu.tap()
            if let v = frac(tap) {
                app.coordinate(withNormalizedOffset: v).tap()
                sleep(3)
                menu.tap()
                XCTAssertTrue(app.buttons["hud-dress"].waitForExistence(timeout: 5), "individual controls (\(name))")
                XCTAssertTrue(app.buttons["care-clean"].exists && app.buttons["hud-train"].exists && app.buttons["hud-compete"].exists)
                XCTAssertFalse(app.buttons["hud-bedtime"].exists)
                save("\(name)_3_individual")
                app.buttons["hud-compete"].tap()
                XCTAssertTrue(app.buttons["hud-compete-track"].waitForExistence(timeout: 5), "Compete unfolds Track / Show (\(name))")
                save("\(name)_4_compete")
                menu.tap()
                if let f = frac(floor) {
                    app.coordinate(withNormalizedOffset: f).tap()
                    sleep(2)
                    menu.tap()
                    XCTAssertTrue(app.buttons["hud-bedtime"].waitForExistence(timeout: 5), "a floor tap brings the group controls back (\(name))")
                    menu.tap()
                }
            }
            app.buttons["go-out"].tap()
            XCTAssertTrue(app.otherElements["town-screen"].waitForExistence(timeout: 8), "Go out opens the Town (\(name))")
            for id in ["town-shop", "town-track", "town-studio", "town-cafe"] { XCTAssertTrue(app.buttons[id].exists, "\(id) is a Town destination (\(name))") }
            save("\(name)_5_town")
            app.buttons["town-track"].tap()                       // Track, then back, returns to the Town
            sleep(2)
            app.buttons["track-back"].tap()
            XCTAssertTrue(app.buttons["town-cafe"].waitForExistence(timeout: 5), "back from the Track lands on the Town (\(name))")
            app.buttons["town-home"].tap()
            XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 5), "Home returns to the room (\(name))")
        }
        app.terminate()
    }
}
