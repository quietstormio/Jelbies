//
//  CampHomeUITests.swift
//  camp-home-r1: the way home from the Camp stays on screen, also after a move. Bring one Camp creature home, the Home bar must be there, tap it, the yard must close.
//  Env: CAMP_OUT (a folder for the three screenshots), CAMP_LANDSCAPE=1.
//

import XCTest

final class CampHomeUITests: XCTestCase {
    @MainActor
    func testHomeStaysAfterABringHome() {
        let env = ProcessInfo.processInfo.environment
        let out = env["CAMP_OUT"] ?? "/tmp"
        let tag = env["CAMP_LANDSCAPE"] == "1" ? "l" : "p"
        let app = XCUIApplication()
        app.launchArguments += ["-MainMenu", "0", "-NewGame", "bob,pip", "-Mute", "1", "-ClockHour", "12", "-CampSeed", "2", "-StartCamp", "1"]
        app.launch()
        if env["CAMP_LANDSCAPE"] == "1" { XCUIDevice.shared.orientation = .landscapeLeft }
        let shot = { (n: String) in try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(n).png")) }
        XCTAssertTrue(app.otherElements["camp-header"].waitForExistence(timeout: 60))
        let got = app.buttons["Got it"]
        if got.waitForExistence(timeout: 4) { got.tap() }
        XCTAssertTrue(app.buttons["camp-home"].waitForExistence(timeout: 10))
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'camp-chip-'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        XCTAssertTrue(app.buttons["Bring home"].waitForExistence(timeout: 10))
        app.buttons["Bring home"].tap()
        sleep(1)
        let pick = app.buttons["camp-pick-1"]          // (a full home asks who goes to Camp: Pip swaps)
        if pick.waitForExistence(timeout: 3) { pick.tap(); app.buttons["camp-sheet-go"].tap() }
        sleep(3)
        XCTAssertTrue(app.buttons["camp-home"].waitForExistence(timeout: 20), "the Home bar must be back after the move")
        sleep(2)
        shot("1_after_move")
        app.buttons["camp-home"].tap()
        sleep(1); shot("2_tapped")
        XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 20))
        sleep(2); shot("3_home")
        XCTAssertFalse(app.otherElements["camp-header"].exists)
    }
}
