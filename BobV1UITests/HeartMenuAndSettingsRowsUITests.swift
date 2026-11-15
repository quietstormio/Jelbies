//
//  HeartMenuAndSettingsRowsUITests.swift
//  (1) The heart menu opens whenever a creature is highlighted: the first one, the SAME one again after the menu was closed, the other one.
//  (2) A Settings row answers a tap in its empty middle (Photo mode, Privacy, Help & Support), not only on the text / chevron.
//  Taps are by coordinate (the element's frame centre): some chrome answers hit tests for what is below it, so `.tap()` can refuse a button a finger reaches.
//  Screenshots go to UISMALL_OUT (default /tmp/ui_small).
//

import XCTest

final class HeartMenuAndSettingsRowsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private var out: String { ProcessInfo.processInfo.environment["UISMALL_OUT"] ?? "/tmp/ui_small" }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "bob,pip", "-MainMenu", "0", "-Mute", "1", "-Intro", "0", "-Jelbies.started.v1", "YES", "-ClockHour", "12", "-BlobNoWander", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["care-menu"].waitForExistence(timeout: 90), "the HUD is up")
        Thread.sleep(forTimeInterval: 8)
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }
    private func centre(_ app: XCUIApplication, _ e: XCUIElement) -> XCUICoordinate {
        let f = e.frame, w = app.windows.firstMatch.frame
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX - w.minX, dy: f.midY - w.minY))
    }
    private func jelbie(_ app: XCUIApplication, _ id: Int) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "jelbie-\(id)").firstMatch }
    private func highlight(_ app: XCUIApplication, _ id: Int) {
        let e = jelbie(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 10))
        centre(app, e).doubleTap()
    }
    private func rowsUp(_ app: XCUIApplication) -> Bool { app.buttons["hud-dress"].waitForExistence(timeout: 6) && app.buttons["hud-come"].exists }

    @MainActor func testHighlightAlwaysOpensTheMenu() {
        let app = launch()
        shot(app, "1_0_start")
        highlight(app, 0)
        XCTAssertTrue(app.staticTexts["hud-name"].waitForExistence(timeout: 6), "highlighted: the name chip")
        XCTAssertTrue(rowsUp(app), "1: highlight one -> the menu's rows exist")
        shot(app, "1_one_highlighted")
        // close the menu with the heart (the highlight stays)
        centre(app, app.buttons["care-menu"]).tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.buttons["hud-dress"].exists, "the menu is closed")
        XCTAssertTrue(app.staticTexts["hud-name"].exists, "the highlight is still there")
        shot(app, "2_0_closed")
        highlight(app, 0)          // the SAME one again
        XCTAssertTrue(rowsUp(app), "2: the same one highlighted again -> the rows exist again")
        shot(app, "2_same_again")
        // the other one
        centre(app, app.buttons["care-menu"]).tap()
        Thread.sleep(forTimeInterval: 2)
        highlight(app, 1)
        XCTAssertTrue(rowsUp(app), "3: the other one -> the rows exist")
        shot(app, "3_other")
        app.terminate()
    }

    @MainActor func testSettingsRowsAnswerInTheirMiddle() {
        let app = launch()
        centre(app, app.buttons["settings-button"]).tap()
        let photo = app.buttons["photo-button"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        shot(app, "5_settings")
        centre(app, photo).tap()
        XCTAssertTrue(app.buttons["photo-shutter"].waitForExistence(timeout: 8), "5: the centre of the Photo mode row opens Photo mode")
        shot(app, "5_photo_open")
        app.terminate()
    }

    @MainActor func testPrivacyAndSupportRowsAnswerInTheirMiddle() {
        let app = launch()
        centre(app, app.buttons["settings-button"]).tap()
        for (row, page) in [("settings-privacy", "privacy-page"), ("settings-support", "support-page")] {
            let r = app.buttons[row]
            XCTAssertTrue(r.waitForExistence(timeout: 10))
            for _ in 0..<6 where !r.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 0.5) }
            shot(app, "5_\(row)_before")
            centre(app, r).tap()
            XCTAssertTrue(app.descendants(matching: .any)[page].waitForExistence(timeout: 8), "5: the centre of \(row) opens \(page)")
            shot(app, "5_\(page)")
            let done = app.buttons["\(page)-done"]
            if done.exists { centre(app, done).tap() }
            Thread.sleep(forTimeInterval: 1.5)
        }
        app.terminate()
    }

    /// A highlight still set when the Settings sheet is closed again: what the HUD shows (reported, the rule asks for the open menu).
    @MainActor func testHighlightSurvivesSettingsSheet() {
        let app = launch()
        highlight(app, 0)
        XCTAssertTrue(rowsUp(app))
        centre(app, app.buttons["settings-button"]).tap()
        XCTAssertTrue(app.buttons["photo-button"].waitForExistence(timeout: 10))
        let done = app.buttons["settings-done"]
        centre(app, done).tap()
        Thread.sleep(forTimeInterval: 2)
        shot(app, "4_back_from_settings")
        XCTAssertTrue(app.staticTexts["hud-name"].exists, "the highlight is still set")
        XCTAssertTrue(rowsUp(app), "4: back from Settings with a highlight still set -> the rows exist")
        app.terminate()
    }
}
