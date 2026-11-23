//
//  ProfileEntryUITests.swift
//  profile-entry-r1: taps the two new Profile buttons in the real app (roster card, name header), looks at the Profile, goes back, and takes the screenshots.
//  Env: PE_OUT (a folder for the pictures), PE_LANDSCAPE=1. Launch with the owner's save copied into the installed app first (the test never writes a save).
//

import XCTest

final class ProfileEntryUITests: XCTestCase {
    @MainActor
    func testRosterAndHeaderOpenTheProfileAndBackReturnsToTheRoom() {
        let env = ProcessInfo.processInfo.environment
        let out = env["PE_OUT"] ?? "/tmp"
        let land = env["PE_LANDSCAPE"] == "1"
        let tag = land ? "l" : "p"
        let app = XCUIApplication()
        app.launchArguments += ["-MainMenu", "0", "-Mute", "1", "-ClockHour", "14", "-ForceOrientation", land ? "left" : "portrait"]
        app.launch()
        let shot = { (n: String) in try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(n).png")) }
        XCTAssertTrue(app.buttons["roster-button"].waitForExistence(timeout: 90))
        sleep(4)
        // 1. the roster panel
        app.buttons["roster-button"].tap()
        let p0 = app.buttons["roster-profile-0"]
        XCTAssertTrue(p0.waitForExistence(timeout: 5)); sleep(1)
        shot("1_roster")
        let ids = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'roster-profile-'")).count
        XCTAssertGreaterThanOrEqual(ids, 1)
        let second = app.buttons["roster-profile-1"]
        let target = second.exists ? second : p0
        target.tap()
        let got = app.buttons["Got it"]; if got.waitForExistence(timeout: 3) { got.tap() }
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 8), "the Profile opens")          // (the Trophies tip card shows once on a first Profile)
        sleep(2); shot("2_profile_from_roster")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["roster-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Back"].exists)
        sleep(1); shot("3_room_after_roster_profile")
        XCTAssertFalse(app.buttons["hud-profile"].exists, "nobody was selected by it")
        // 2. a selected Jelmiko: pick by the roster card, then the header button
        app.buttons["roster-button"].tap()
        let card = app.otherElements["roster-card-0"].exists ? app.otherElements["roster-card-0"] : app.buttons["roster-card-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let hp = app.buttons["hud-profile"]
        XCTAssertTrue(hp.waitForExistence(timeout: 10), "the name header carries the Profile button")
        sleep(1); shot("4_header")
        hp.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 8))
        sleep(2); shot("5_profile_from_header")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["hud-profile"].waitForExistence(timeout: 5), "back: the same Jelmiko is still selected")
        sleep(1); shot("6_room_after_header_profile")
    }
}
