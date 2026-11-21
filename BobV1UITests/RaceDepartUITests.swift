//
//  RaceDepartUITests.swift
//  race-depart-r1 capture: the owner's real path to a race (Go out -> Town -> Track -> pick the racer -> Race), with the simulator-only probe on (-RaceDepartProbe 1, [rdp] log lines)
//  and one of the housemates' situations held until the trip starts (-RaceDepartSetup, written by RaceDepartProbe.swift; the marker file /tmp/racedep_go starts it).
//  testDepartFromTown runs every situation in RACEDEP_SITUATIONS (comma list, default pair,walkemote,toy) for every seed in RACEDEP_SEEDS (default 1,2,3), one launch each.
//  Env: RACEDEP_RACER (the roster id who races, default 0), RACEDEP_SECS (how long to stay after the tap, default 100), RACEDEP_LANDSCAPE=1. The caller (the scratch scripts) streams the [rdp] lines and records the screen.
//

import XCTest

final class RaceDepartUITests: XCTestCase {
    @MainActor
    func testDepartFromTown() {
        let env = ProcessInfo.processInfo.environment
        let sits = (env["RACEDEP_SITUATIONS"] ?? "pair,walkemote,toy").split(separator: ",").map(String.init)
        let seeds = (env["RACEDEP_SEEDS"] ?? "1,2,3").split(separator: ",").map(String.init)
        let secs = Double(env["RACEDEP_SECS"] ?? "100") ?? 100
        for sit in sits { for seed in seeds { one(sit: sit, seed: seed, secs: secs, landscape: env["RACEDEP_LANDSCAPE"] == "1") } }          // ("pair!ctl": the control, Town open then Home, no race)
    }

    @MainActor
    private func one(sit rawSit: String, seed: String, secs: Double, landscape: Bool) {
        let control = rawSit.hasSuffix("!ctl"), sit = control ? String(rawSit.dropLast(4)) : rawSit
        try? FileManager.default.removeItem(atPath: "/tmp/racedep_go")
        let app = XCUIApplication()
        app.launchArguments += ["-MainMenu", "0", "-NewGame", "bob,lavender,moss", "-Mute", "1", "-ClockHour", "12", "-BlobSeed", seed, "-RaceSeed", "7", "-RaceAuto", "4", "-RaceControl", "pull",
                                "-RaceDepartProbe", "1", "-RaceDepartSetup", sit]
        app.launch()
        let cont = app.buttons["Continue"]
        _ = cont.waitForExistence(timeout: 5)
        if cont.exists { cont.tap() }
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        sleep(8)
        try? "go".write(toFile: "/tmp/racedep_go", atomically: true, encoding: .utf8)          // the situation starts and is held from here
        sleep(sit == "asleep" ? 16 : 4)          // (a sleeper needs time to settle into his bed before the room is frozen behind the Town panels)
        XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 10))
        app.buttons["go-out"].tap()                                                         // the first tap
        XCTAssertTrue(app.buttons["town-track"].waitForExistence(timeout: 10))
        sleep(1)
        app.buttons["town-track"].tap()
        let racer = ProcessInfo.processInfo.environment["RACEDEP_RACER"] ?? "0"          // (RACEDEP_RACER=1: Lavender races and Bob stays home)
        XCTAssertTrue(app.buttons["who-\(racer)"].waitForExistence(timeout: 10))
        sleep(1)
        app.buttons["who-\(racer)"].tap()
        if control {          // the control: the same freeze and resume, no race (Track back, Town home)
            sleep(1)
            app.buttons["track-back"].tap()
            XCTAssertTrue(app.buttons["town-home"].waitForExistence(timeout: 10))
            app.buttons["town-home"].tap()
            sleep(UInt32(min(secs, 12)))
            try? FileManager.default.removeItem(atPath: "/tmp/racedep_go")
            app.terminate()
            sleep(2)
            return
        }
        let race = app.buttons["track-race"]
        XCTAssertTrue(race.waitForExistence(timeout: 10))
        sleep(1)
        race.tap()                                                                          // the race starts: Town closes, the racer runs out, the white
        sleep(UInt32(secs))
        try? FileManager.default.removeItem(atPath: "/tmp/racedep_go")
        app.terminate()
        sleep(2)
    }
}
