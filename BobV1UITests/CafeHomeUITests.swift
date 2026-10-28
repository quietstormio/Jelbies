//
//  CafeHomeUITests.swift
//  The café's "Go home" pill (cafe-go-home): shown with the menu in portrait and landscape, and tapping it fades back to the room.
//  Uses the -CafeAuto enter capture aid. Screenshots go to CAFE_OUT (default /tmp/cafehome).
//

import XCTest
import UIKit

final class CafeHomeUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["CAFE_OUT"] ?? "/tmp/cafehome"

    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/cafehome_\(name).png"))
    }

    @MainActor
    func testGoHomeFromCafe() throws {
        for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            let app = XCUIApplication()
            app.launchArguments += ["-BlobCount", "3", "-BlobNoWander", "1", "-ClockHour", "12", "-MainMenu", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-CafeAuto", "enter"]
            XCUIDevice.shared.orientation = orient
            app.launch()
            XCUIDevice.shared.orientation = orient
            let home = app.buttons["cafe-go-home"]
            let shown = home.waitForExistence(timeout: 90)
            if !shown { save("\(name)_missing") }
            XCTAssertTrue(shown, "Go home shows at the café (\(name))")
            XCTAssertEqual(home.label, "Go home")
            XCTAssertFalse(app.buttons["cafe-home"].exists, "only one way home (\(name))")
            sleep(2)
            save(name)
            home.tap()
            XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 20), "Go home returns to the room (\(name))")
            XCTAssertFalse(home.exists)
            save("\(name)_home")
            app.terminate()
        }
    }
}
