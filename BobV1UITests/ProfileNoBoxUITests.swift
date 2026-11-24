//
//  ProfileNoBoxUITests.swift
//  profile-nobox-r1: the Profile has no living-line box ("profile-lately" is gone). Opens a Profile through the roster and takes a picture.
//  Env: PB_OUT (folder), PB_NAME (file name), PB_LANDSCAPE=1, PB_BIG=1 (largest accessibility text size). Uses -NewGame, so no save is touched.
//

import XCTest

final class ProfileNoBoxUITests: XCTestCase {
    @MainActor
    func testProfileHasNoLivingLineBox() {
        let env = ProcessInfo.processInfo.environment
        let out = env["PB_OUT"] ?? "/tmp", name = env["PB_NAME"] ?? "after_portrait"
        let land = env["PB_LANDSCAPE"] == "1", big = env["PB_BIG"] == "1"
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "bob,berry", "-MainMenu", "0", "-Mute", "1", "-ClockHour", "14", "-AutoContinue", "0.5", "-ForceOrientation", land ? "left" : "portrait"]
        if big { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["roster-button"].waitForExistence(timeout: 90))
        sleep(4)
        app.buttons["roster-button"].tap()
        let p0 = app.buttons["roster-profile-0"]
        XCTAssertTrue(p0.waitForExistence(timeout: 5))
        p0.tap()
        let got = app.buttons["Got it"]; if got.waitForExistence(timeout: 3) { got.tap() }
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 8), "the Profile opens")
        XCTAssertTrue(app.descendants(matching: .any)["profile-about"].waitForExistence(timeout: 5), "the description paragraph is still there")
        sleep(2)
        XCTAssertFalse(app.descendants(matching: .any)["profile-lately"].exists, "the living-line box is gone")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }
}
