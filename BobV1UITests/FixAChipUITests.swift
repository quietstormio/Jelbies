//
//  FixAChipUITests.swift
//  Capture aid: double-tap a Jelly -> the "Play with <name>?" chip must be visible and the Go out pill hidden (portrait and landscape).
//  FIXA_TAP_P / FIXA_TAP_L = "x,y" as fractions of the screen (set as TEST_RUNNER_FIXA_TAP_P ...). Without them it only saves plain screenshots to find a Jelly.
//

import XCTest
import UIKit

final class FixAChipUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["FIXA_OUT"] ?? "/tmp/fixa_ui"

    private func save(_ shot: XCUIScreenshot, _ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? shot.image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    private func frac(_ key: String) -> CGVector? {
        guard let s = ProcessInfo.processInfo.environment[key] else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0) }
        return p.count == 2 ? CGVector(dx: p[0], dy: p[1]) : nil
    }

    @MainActor
    func testChipHidesGoOut() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-BlobCount", "3", "-BlobNoWander", "1"]
        app.launch()
        sleep(6)
        for (orient, key, name) in [(UIDeviceOrientation.portrait, "FIXA_TAP_P", "portrait"), (.landscapeLeft, "FIXA_TAP_L", "landscape")] {
            XCUIDevice.shared.orientation = orient
            sleep(7)
            if let h = ProcessInfo.processInfo.environment["FIXA_HOLD"], h == name { sleep(30) }          // (time for `simctl io screenshot`)
            save(XCUIScreen.main.screenshot(), "plain_\(name)")
            XCTAssertTrue(app.buttons["go-out"].exists, "Go out shows normally (\(name))")
            if let v = frac(key) {
                app.coordinate(withNormalizedOffset: v).doubleTap()
                let chip = app.buttons["select-chip"].firstMatch
                XCTAssertTrue(chip.waitForExistence(timeout: 12), "the chip appears (\(name))")
                sleep(1)
                if let h = ProcessInfo.processInfo.environment["FIXA_HOLD"], h == name { sleep(30) }
                save(XCUIScreen.main.screenshot(), "chip_\(name)")
                XCTAssertFalse(app.buttons["go-out"].exists, "Go out is hidden while the chip is up (\(name))")
                app.buttons["Cancel"].firstMatch.tap()
                sleep(2)
                XCTAssertTrue(app.buttons["go-out"].exists, "Go out is back after the chip is dismissed (\(name))")
            }
        }
        app.terminate()
    }
}
