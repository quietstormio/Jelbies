//
//  TricksRowUITests.swift
//  The Tricks row of the selected-Jelbie menu (stage 1 of the trick plan), portrait and landscape: tap the Jelbie, open the paw, tap Tricks, see the
//  known chips and the locked ones, tap Strut. TRICKS_TAP_P / TRICKS_TAP_L = "x,y" fractions of the screen where the Jelbie stands; TRICKS_OUT = screenshot folder.
//

import XCTest
import UIKit

final class TricksRowUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["TRICKS_OUT"] ?? "/tmp/tricks_ui"
    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    private func frac(_ key: String, _ dflt: CGVector) -> CGVector {
        guard let s = ProcessInfo.processInfo.environment[key] else { return dflt }
        let p = s.split(separator: ",").compactMap { Double($0) }
        return p.count == 2 ? CGVector(dx: p[0], dy: p[1]) : dflt
    }

    @MainActor
    func testTricksRowPortraitAndLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-BlobNoWander", "1", "-ClockHour", "12", "-Mute", "1", "-GrantTrick", "strut", "-HUDHighlight", "0"]
        app.launch()
        sleep(8)
        save("0_launch")
        for (orient, key, name) in [(UIDeviceOrientation.portrait, "TRICKS_TAP_P", "portrait"), (.landscapeLeft, "TRICKS_TAP_L", "landscape")] {
            XCUIDevice.shared.orientation = orient
            sleep(5)
            let menu = app.buttons["care-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10), "the paw shows (\(name))")
            sleep(2)
            menu.tap()
            XCTAssertTrue(app.buttons["hud-tricks"].waitForExistence(timeout: 5), "the Tricks row is in his menu (\(name))")
            save("\(name)_1_menu")
            app.buttons["hud-tricks"].tap()
            XCTAssertTrue(app.buttons["hud-trick-strut"].waitForExistence(timeout: 5), "the bought Strut chip (\(name))")
            XCTAssertTrue(app.buttons["hud-trick-sing"].exists, "Sing is locked but listed (\(name))")
            save("\(name)_2_tricks")
            if name == "portrait" {
                app.buttons["hud-trick-strut"].tap()
                for s in [0.4, 0.8, 1.2, 1.6, 2.0] { Thread.sleep(forTimeInterval: s == 0.4 ? 0.4 : 0.4); save("portrait_3_strut_\(s)") }
            } else {
                menu.tap()
            }
        }
        app.terminate()
    }
}
