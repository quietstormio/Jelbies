//
//  RosterSlotsTextUITests.swift
//  The roster-slots line reads "N/3 at home" (not "room for N more"): on the Town's Jelly Spring card and on the Jelly Spring screen. 1, 2 and 3 at home.
//  Screenshots go to UISMALL_OUT.
//

import XCTest

final class RosterSlotsTextUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func run(_ roster: String, home n: Int) {
        let out = ProcessInfo.processInfo.environment["UISMALL_OUT"] ?? "/tmp/ui_small"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        func shot(_ app: XCUIApplication, _ name: String) { try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png")) }
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", roster, "-MainMenu", "0", "-Mute", "1", "-Intro", "0", "-Jelbies.started.v1", "YES", "-ClockHour", "12", "-BlobNoWander", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 90))
        Thread.sleep(forTimeInterval: 6)
        app.buttons["go-out"].tap()
        let adopt = app.descendants(matching: .any)["town-adopt"].firstMatch
        XCTAssertTrue(adopt.waitForExistence(timeout: 30), "the Jelly Spring card")
        for _ in 0..<4 where !adopt.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 0.5) }
        shot(app, "slots_town_\(n)")
        let text = "\(n)/3 at home"
        let hit = app.staticTexts[text].exists || adopt.label.contains(text)
        XCTAssertTrue(hit, "town card says \(text); label: \(adopt.label)")
        XCTAssertFalse(adopt.label.lowercased().contains("room for"))
        if n < 3 {
            adopt.tap()
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 30), "the Jelly Spring screen says \(text)")
            Thread.sleep(forTimeInterval: 2)
            shot(app, "slots_spring_\(n)")
        }
        app.terminate()
    }

    @MainActor func testOneAtHome() { run("bob", home: 1) }
    @MainActor func testTwoAtHome() { run("bob,pip", home: 2) }
    @MainActor func testThreeAtHome() { run("bob,pip,moss", home: 3) }
}
