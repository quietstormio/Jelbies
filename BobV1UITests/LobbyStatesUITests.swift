//
//  LobbyStatesUITests.swift
//  Drives the Volleyball and Track lobbies through the states a still capture cannot reach (swap buttons, the locked-card hint, wins, the blocker line, a drill's start caption) and saves
//  screenshots to LOBBY_OUT (TEST_RUNNER_LOBBY_OUT; default /tmp/lobby_ui).
//

import XCTest

final class LobbyStatesUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["LOBBY_OUT"] ?? "/tmp/lobby_ui"

    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    private func launch(_ lobby: String, seed: String? = nil, roster: String = "pip,moss,lavender") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", roster, "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-LobbyAuto", lobby, "-BlobNoWander", "1", "-volley.partner", "99"]
        app.launchArguments += ["-LobbySeed", "reset dress" + (seed.map { " " + $0 } ?? "")]
        app.launch()
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @MainActor
    func testTeamPickerThree() {
        let app = launch("volley")
        XCTAssertTrue(el(app, "volley-lobby").waitForExistence(timeout: 30))
        sleep(8)
        save("s1_vb_three")
        XCTAssertTrue(el(app, "volley-who-0").isSelected && el(app, "volley-who-1").isSelected, "who + the first other Jelmiko start as the team")
        XCTAssertFalse(el(app, "volley-who-2").isSelected)
        el(app, "volley-who-2").tap(); sleep(2)
        XCTAssertTrue(el(app, "volley-who-2").isSelected, "the tapped Jelmiko joins")
        XCTAssertFalse(el(app, "volley-who-0").isSelected, "the one picked earliest drops out")
        save("s2_vb_pick_third")
    }

    @MainActor
    func testTeamPickerTwoAndOne() {
        var app = launch("volley", roster: "pip,moss")
        XCTAssertTrue(el(app, "volley-lobby").waitForExistence(timeout: 30))
        sleep(8)
        XCTAssertTrue(el(app, "volley-who-0").isSelected && el(app, "volley-who-1").isSelected, "two Jelmiko: both play")
        XCTAssertFalse(el(app, "volley-who-friend").exists)
        save("s3b_vb_two")
        app.terminate()
        app = launch("volley", roster: "pip")
        XCTAssertTrue(el(app, "volley-lobby").waitForExistence(timeout: 30))
        sleep(8)
        XCTAssertFalse(el(app, "volley-who-friend").exists, "one Jelmiko and no Park friend: no teammate")
        XCTAssertTrue(el(app, "volley-picker-locked").exists, "the second slot is locked")
        XCTAssertTrue(el(app, "volley-go-park").exists, "with a way to the Park")
        XCTAssertFalse(el(app, "volley-play").isEnabled, "Play is locked")
        XCTAssertTrue(el(app, "volley-train").isEnabled, "Train is solo: it stays on without a partner")
        XCTAssertTrue(el(app, "volley-picker-note").label.contains("needs a partner"), "the partner rule is said under the picker")
        save("s3c_vb_one_locked")
        app.terminate()
        app = launch("volley", roster: "pip")
        app.terminate()
        let friendly = XCUIApplication()
        friendly.launchArguments += ["-SetRoster", "pip", "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-LobbyAuto", "volley", "-BlobNoWander", "1", "-ParkFriendSeed", "7"]
        friendly.launch()
        XCTAssertTrue(el(friendly, "volley-lobby").waitForExistence(timeout: 30))
        sleep(8)
        XCTAssertTrue(el(friendly, "volley-who-friend").exists, "one Jelmiko and a Park friend: the friend fills the second tile")
        XCTAssertTrue(el(friendly, "volley-team-friend").exists)
        XCTAssertTrue(el(friendly, "volley-play").isEnabled)
        save("s3d_vb_one_friend")
    }

    @MainActor
    func testLockedHints() {
        var app = launch("volley")
        XCTAssertTrue(el(app, "volley-tier-shore").waitForExistence(timeout: 30))
        sleep(4)
        el(app, "volley-tier-shore").tap(); sleep(1)
        save("s4_vb_locked_hint")
        app.terminate()
        app = launch("track")
        XCTAssertTrue(el(app, "course-ripple").waitForExistence(timeout: 30))
        sleep(4)
        el(app, "course-ripple").tap(); sleep(1)
        save("s5_track_locked_hint")
    }

    @MainActor
    func testTrackWins() {
        let app = launch("track", seed: "wins")
        XCTAssertTrue(el(app, "course-ripple").waitForExistence(timeout: 30))
        sleep(10)
        save("s6_track_wins")
    }

    @MainActor
    func testBlockedState() {
        var app = launch("volley", seed: "blocked")
        XCTAssertTrue(el(app, "volley-why").waitForExistence(timeout: 40), "a meal is out: the reason shows")
        sleep(2)
        XCTAssertFalse(el(app, "volley-play").isEnabled)
        save("s7_vb_blocked")
        app.terminate()
        app = launch("track", seed: "blocked")
        XCTAssertTrue(el(app, "track-why").waitForExistence(timeout: 40))
        sleep(2)
        XCTAssertFalse(el(app, "track-race").isEnabled)
        save("s8_track_blocked")
    }

    @MainActor
    func testDrillCaption() {
        let app = launch("volley")
        XCTAssertTrue(el(app, "volley-train").waitForExistence(timeout: 30))
        sleep(4)
        el(app, "volley-train").tap()
        XCTAssertTrue(el(app, "volley-drill-spike").waitForExistence(timeout: 40), "the Training sheet opens (a Debug build is slow to animate it in)")
        sleep(4)
        save("s9_train_sheet")
        el(app, "volley-drill-spike").tap()
        for i in 0..<6 { if el(app, "volley-drill-caption").exists { break }; sleep(6); save("dbg_\(i)") }
        XCTAssertTrue(el(app, "volley-drill-caption").waitForExistence(timeout: 40), "the instruction shows when the drill starts")
        sleep(1)
        save("s10_drill_caption")
        sleep(9)
        XCTAssertFalse(el(app, "volley-drill-caption").exists, "and fades after a few seconds")
        save("s11_drill_after")
    }
}
