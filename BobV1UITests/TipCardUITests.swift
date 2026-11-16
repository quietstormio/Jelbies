//
//  TipCardUITests.swift
//  First-time tips on the real app: a tap outside dismisses the card, Got it dismisses it, landscape placement, and the Settings "Show tips again" row.
//  Pictures go to TIPS_OUT (default /tmp/tips_ui). Dev launch arguments (-TipShow / -TipsReset) work on the simulator.
//

import XCTest

final class TipCardUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["TIPS_OUT"] ?? "/tmp/tips_ui"
    private let base = ["-NewGame", "bob", "-NewGameCoins", "10000", "-MainMenu", "0", "-TipsReset", "1", "-StoreSeed", "1"]

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: Self.out + "/\(name).png"))
    }
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += base + args
        app.launch()
        return app
    }

    func testTapOutsideDismissesAndGotItDismisses() {
        let app = launch(["-TipShow", "powerup"])
        let card = app.otherElements["tip-powerup"]
        XCTAssertTrue(card.waitForExistence(timeout: 120), "the power-up card shows")
        shot("tap_before")
        // a tap on the floor (well outside the card, on the room): the card goes
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.78)).tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: card); waitForExpectations(timeout: 10)
        shot("tap_after")
        // the second card: Got it
        app.terminate()
        let app2 = launch(["-TipShow", "powerup"])
        XCTAssertTrue(app2.otherElements["tip-powerup"].waitForExistence(timeout: 120))
        app2.buttons["tip-got-it"].tap()
        expectation(for: gone, evaluatedWith: app2.otherElements["tip-powerup"]); waitForExpectations(timeout: 10)
        shot("gotit_after")
    }

    func testTapOutsideStillPressesTheButtonUnderIt() {
        // the tap that dismisses the card also reaches the control it landed on: the heart opens the care menu
        let app = launch(["-TipShow", "powerup"])
        XCTAssertTrue(app.otherElements["tip-powerup"].waitForExistence(timeout: 120))
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.91)).tap()          // the heart (bottom right)
        XCTAssertTrue(app.staticTexts["Feed"].waitForExistence(timeout: 10), "the heart menu opened under the dismissing tap")
        XCTAssertFalse(app.otherElements["tip-powerup"].exists)
        shot("tap_through")
    }

    func testLandscapeHomeAndWhereTo() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(["-TipShow", "powerup"])
        XCTAssertTrue(app.otherElements["tip-powerup"].waitForExistence(timeout: 120))
        sleep(2); shot("powerup_l")
        app.terminate()
        let app2 = launch(["-TipShow", "town", "-StoreOpen", "town"])
        XCTAssertTrue(app2.otherElements["tip-town"].waitForExistence(timeout: 120))
        sleep(2); shot("town_l")
    }

    func testSettingsShowTipsAgain() {
        let app = launch(["-SettingsOpen", "1"])
        let row = app.buttons["settings-tips-again"]
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 120))
        sleep(1); shot("settings_before")
        row.tap()
        shot("settings_after")          // (the line stays for 3 s; the simulator is slow to answer a query, so it is judged on the picture)
    }

    func testHelpPage() {
        let app = launch(["-SettingsOpen", "1", "-SupportOpen", "1"])
        XCTAssertTrue(app.staticTexts["Feed: tap the heart, then Feed, and pick a snack."].waitForExistence(timeout: 120))
        sleep(1); shot("help")
    }
}
