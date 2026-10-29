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
        app.launchArguments += ["-LobbySeed", "reset" + (seed.map { " " + $0 } ?? "")]
        app.launch()
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @MainActor
    func testSwapButtons() {
        let app = launch("volley")
        XCTAssertTrue(el(app, "volley-lobby").waitForExistence(timeout: 30))
        sleep(8)
        save("s1_vb_three")
        XCTAssertTrue(el(app, "volley-team-2-swap").exists, "three Jelbies: a swap on each tile")
        el(app, "volley-team-2-swap").tap(); sleep(6)
        save("s2_vb_swap_tile2")
        el(app, "volley-team-1-swap").tap(); sleep(6)
        save("s3_vb_swap_tile1")
    }

    @MainActor
    func testNoSwapWithTwo() {
        let app = launch("volley", roster: "pip,moss")
        XCTAssertTrue(el(app, "volley-lobby").waitForExistence(timeout: 30))
        sleep(8)
        XCTAssertFalse(el(app, "volley-team-1-swap").exists, "two Jelbies: no bench, no swap")
        XCTAssertFalse(el(app, "volley-team-2-swap").exists)
        save("s3b_vb_two")
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
