//
//  ShowLobbyUITests.swift
//  The Jelly Show lobby's states a still capture cannot reach (the locked-card hint, the blocker line) and the room-after-lobby check (the portrait path flips renderer state and puts it back).
//  Screenshots go to SHOW_OUT (TEST_RUNNER_SHOW_OUT).
//

import XCTest

final class ShowLobbyUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["SHOW_OUT"] ?? "/tmp/show_ui"
    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func launch(roster: String = "pip,moss,lavender", hour: Int = 12, auto: String? = "show", seed: String = "reset dress") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", roster, "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "\(hour)", "-LobbySeed", seed]
        if let auto { app.launchArguments += ["-LobbyAuto", auto] }
        app.launch()
        return app
    }

    @MainActor
    func testLockedHintAndStartAreThere() {
        let app = launch()
        XCTAssertTrue(el(app, "rank-pond").waitForExistence(timeout: 40))
        for id in ["show-start", "show-dress", "show-help", "show-rivals", "show-tip", "show-entrant", "show-estimate", "show-theme", "show-ranks", "show-prizes", "show-card", "show-back"] { XCTAssertTrue(el(app, id).exists, id) }
        sleep(6)
        el(app, "rank-pond").tap(); sleep(1)
        save("s1_hint")
    }

    @MainActor
    func testBlockedState() {
        let app = launch(seed: "reset dress blocked")
        XCTAssertTrue(el(app, "show-why").waitForExistence(timeout: 50), "a meal is out: the reason shows")
        sleep(2)
        XCTAssertFalse(el(app, "show-start").isEnabled)
        save("s2_blocked")
    }

    @MainActor
    func testRoomAfterShowLobby() {
        for (tag, roster) in [("three", "pip,moss,lavender"), ("bob", "bob")] {
            for hour in [21, 12] {
                var app = launch(roster: roster, hour: hour, auto: nil)
                sleep(25); save("\(tag)_\(hour)_before"); app.terminate()
                app = launch(roster: roster, hour: hour)
                XCTAssertTrue(el(app, "show-back").waitForExistence(timeout: 40)); sleep(10)
                el(app, "show-back").tap()                     // back goes to the Studio
                if el(app, "studio-back").waitForExistence(timeout: 20) { sleep(3); el(app, "studio-back").tap() }
                if el(app, "town-home").waitForExistence(timeout: 20) { el(app, "town-home").tap() }
                sleep(8); save("\(tag)_\(hour)_after_show")
                app.terminate()
            }
        }
    }
}
