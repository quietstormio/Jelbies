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

        let up = app.buttons["Meet the three"].waitForExistence(timeout: 60)
        if !up { try? app.debugDescription.write(toFile: dir + "_tree.txt", atomically: true, encoding: .utf8) }
        XCTAssertTrue(up, "the picker")
        sleep(3)
        shot(app, "00_picker", dir)
        app.buttons["Meet the three"].tap()
        sleep(3)
        try? app.debugDescription.write(toFile: dir + "_tree2.txt", atomically: true, encoding: .utf8)
        let pick = app.buttons["This one!"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        pick.tap()
        let bring = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bring'")).firstMatch
        XCTAssertTrue(bring.waitForExistence(timeout: 20))
        sleep(2)
        shot(app, "00_naming", dir)
        bring.tap()

        // the cross-fade into the real room, then the run-in (Skip is up from the first moment)
        let skipUp = app.descendants(matching: .any)["first-day-skip"].waitForExistence(timeout: 20)
        if !skipUp { shot(app, "99_noskip", dir); try? app.debugDescription.write(toFile: dir + "_tree3.txt", atomically: true, encoding: .utf8) }
        XCTAssertTrue(skipUp, "the tour's Skip is up")
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
}
