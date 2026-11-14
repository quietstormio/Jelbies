//
//  FirstDayTourCaptureUITests.swift
//  Real-app walk through a new game's first day: the adoption picker's "Bring <name> home", the room, the run-in, the welcome caption, the JellyCoins caption, the seven coach marks,
//  free play. Writes a PNG per step to FIRSTDAY_SHOTS (TEST_RUNNER_FIRSTDAY_SHOTS) and checks Skip / Next are on screen at every step.
//  FIRSTDAY_LANDSCAPE=1 runs it on its side. Simulator only (the launch arguments are capture aids).
//

import XCTest

final class FirstDayTourCaptureUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String, _ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? app.windows.firstMatch.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testFirstDayInTheRealRoom() {
        let env = ProcessInfo.processInfo.environment
        let dir = env["FIRSTDAY_SHOTS"] ?? NSTemporaryDirectory() + "firstday"
        let land = env["FIRSTDAY_LANDSCAPE"] == "1"
        let app = XCUIApplication()
        app.launchArguments += ["-ResetForAdoption", "1", "-MainMenu", "0", "-SkipIntro", "1", "-ClockHour", "12"]
        if let extra = env["FIRSTDAY_ARGS"] { app.launchArguments += extra.split(separator: " ").map(String.init) }
        XCUIDevice.shared.orientation = land ? .landscapeLeft : .portrait
        app.launch()
        XCUIDevice.shared.orientation = land ? .landscapeLeft : .portrait

        XCTAssertTrue(app.buttons["Meet the three"].waitForExistence(timeout: 60), "the picker")
        sleep(3)
        shot(app, "00_picker", dir)
        app.buttons["Meet the three"].tap()
        sleep(3)
        let pick = app.buttons["This one!"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        pick.tap()
        let bring = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bring'")).firstMatch
        XCTAssertTrue(bring.waitForExistence(timeout: 20))
        sleep(2)
        shot(app, "00_naming", dir)
        bring.tap()

        if env["FIRSTDAY_CARD"] == "1" {          // -FirstDayStyle card: the old illustrated screen, then the room
            sleep(4); shot(app, "card_a", dir)
            sleep(10); shot(app, "card_b", dir)
            sleep(6); shot(app, "card_room", dir)
            return
        }
        // the cross-fade into the real room, then the run-in (Skip is up from the first moment)
        XCTAssertTrue(app.descendants(matching: .any)["first-day-skip"].waitForExistence(timeout: 30), "the tour's Skip is up")
        shot(app, "01_runin_a", dir)
        usleep(900_000); shot(app, "01_runin_b", dir)
        usleep(900_000); shot(app, "01_runin_c", dir)

        let next = app.descendants(matching: .any)["first-day-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 40), "the welcome caption comes up when he has arrived")
        sleep(2)
        let names = ["02_welcome", "03_coins", "04_care", "05_jelmiko", "06_coinspill", "07_bag", "08_goout", "09_mic", "10_settings"]
        for (i, n) in names.enumerated() {
            XCTAssertTrue(next.exists, "Next is on screen at \(n)")
            XCTAssertTrue(app.descendants(matching: .any)["first-day-skip"].exists, "Skip is on screen at \(n)")
            shot(app, n, dir)
            sleep(1)
            next.tap()
            if i < names.count - 1 { usleep(1_200_000) }
        }
        sleep(2)
        XCTAssertFalse(app.descendants(matching: .any)["first-day-skip"].exists, "the tour is over: free play")
        shot(app, "11_free", dir)
        sleep(4)
    }

    /// Settings > Watch the opening on a saved game: the opening story, then the tour over the player's own room (nothing runs in).
    func testReplayFromSettings() {
        let env = ProcessInfo.processInfo.environment
        let dir = (env["FIRSTDAY_SHOTS"] ?? NSTemporaryDirectory() + "firstday") + "_replay"
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "lavender,teddy", "-MainMenu", "0", "-SkipIntro", "1", "-ClockHour", "12"]
        app.launch()
        let gear = app.buttons["settings-button"]
        XCTAssertTrue(gear.waitForExistence(timeout: 90), "the room")
        sleep(4)
        shot(app, "r00_room", dir)
        gear.tap()
        let row = app.descendants(matching: .any)["settings-watch-opening"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let skip = app.descendants(matching: .any)["first-day-skip"]
        for _ in 0..<80 where !skip.exists {
            let s = app.buttons["Skip"]
            if s.exists { s.tap() }
            sleep(1)
        }
        XCTAssertTrue(skip.waitForExistence(timeout: 20), "the tour comes up after the opening")
        sleep(2)
        shot(app, "r01_welcome", dir)
        var n = 2
        let next = app.descendants(matching: .any)["first-day-next"]
        while next.exists, n < 14 {
            next.tap(); usleep(1_300_000)
            shot(app, String(format: "r%02d_step", n), dir); n += 1
        }
        XCTAssertFalse(skip.exists, "the replay ended")
        sleep(2)
        shot(app, "r99_after", dir)
    }
}
