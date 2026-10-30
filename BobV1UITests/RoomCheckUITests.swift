//
//  RoomCheckUITests.swift
//  Pre-install checks: the room looks the same before and after a lobby / sheet visit (the portrait path flips renderer state and puts it back), a match and a race start,
//  and ten quick open / close cycles. Screenshots go to ROOM_OUT (TEST_RUNNER_ROOM_OUT).
//

import XCTest

final class RoomCheckUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["ROOM_OUT"] ?? "/tmp/room_check"
    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func launch(roster: String, hour: Int, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", roster, "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "\(hour)", "-volley.partner", "99",
                                "-LobbySeed", "reset dress"] + extra
        app.launch()
        return app
    }
    private func home(_ app: XCUIApplication) {
        if el(app, "town-home").waitForExistence(timeout: 20) { el(app, "town-home").tap() }
        sleep(8)
    }

    @MainActor
    func testRoomAfterVisits() {
        for (tag, roster) in [("three", "pip,moss,lavender"), ("bob", "bob")] {
            for hour in [21, 12] {
                var app = launch(roster: roster, hour: hour)
                sleep(25); save("\(tag)_\(hour)_before"); app.terminate()
                for (name, arg, backID) in [("volley", "volley", "volley-back"), ("track", "track", "track-back"), ("train", "volleyTrain", ""), ("studio", "", "")] {
                    if name == "studio" { app = launch(roster: roster, hour: hour, extra: ["-StoreOpen", "studio"]) }
                    else { app = launch(roster: roster, hour: hour, extra: ["-LobbyAuto", arg]) }
                    sleep(22)
                    if name == "train" { el(app, "lobby-sheet-close").waitForExistence(timeout: 30); sleep(4); el(app, "lobby-sheet-close").tap(); sleep(2); el(app, "volley-back").tap() }
                    else if name == "studio" { sleep(6); app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch.tap() }
                    else { sleep(8); el(app, backID).tap() }
                    home(app)
                    save("\(tag)_\(hour)_after_\(name)")
                    app.terminate()
                }
            }
        }
    }

    @MainActor
    func testLandscapeRoom() {
        XCUIDevice.shared.orientation = .landscapeLeft
        var app = launch(roster: "pip,moss,lavender", hour: 12, extra: ["-ForceOrientation", "left"])
        sleep(25); save("land_before"); app.terminate()
        app = launch(roster: "pip,moss,lavender", hour: 12, extra: ["-LobbyAuto", "volley", "-ForceOrientation", "left"])
        sleep(25); el(app, "volley-back").tap(); home(app); save("land_after"); app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testMatchAndRace() {
        for (tag, roster) in [("three", "pip,moss,lavender"), ("bob", "bob")] {
            var app = launch(roster: roster, hour: 12, extra: ["-LobbyAuto", "volley"])
            XCTAssertTrue(el(app, "volley-play").waitForExistence(timeout: 40)); sleep(10)
            el(app, "volley-play").tap(); save("\(tag)_match_0"); XCTAssertTrue(el(app, "volley-leave").waitForExistence(timeout: 120), "the match starts"); sleep(25); save("\(tag)_match")
            el(app, "volley-leave").tap(); sleep(30); save("\(tag)_after_match"); app.terminate()
            app = launch(roster: roster, hour: 12, extra: ["-LobbyAuto", "track"])
            XCTAssertTrue(el(app, "track-race").waitForExistence(timeout: 40)); sleep(10)
            el(app, "track-race").tap(); save("\(tag)_race_0"); for k in 1...4 { sleep(30); save("\(tag)_race_\(k)") }
            app.terminate()
        }
    }

    @MainActor
    func testTenOpenCloseCycles() {
        let app = launch(roster: "pip,moss,lavender", hour: 12)
        sleep(25)
        for i in 0..<10 {
            if el(app, "go-out").waitForExistence(timeout: 10) { el(app, "go-out").tap() }
            if el(app, "town-beach").waitForExistence(timeout: 10) { el(app, "town-beach").tap() }
            XCTAssertTrue(el(app, "volley-back").waitForExistence(timeout: 10), "cycle \\(i)")
            usleep(600_000)
            el(app, "volley-back").tap()
            if el(app, "town-home").waitForExistence(timeout: 10) { el(app, "town-home").tap() }
            usleep(600_000)
            if i == 0 || i == 9 { save("cycle_\(i)") }
        }
        sleep(5); save("cycle_end")
    }
}
