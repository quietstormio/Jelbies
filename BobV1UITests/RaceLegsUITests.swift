//
//  RaceLegsUITests.swift
//  Real-app capture of a hurdle jump in the Jelly Circuit (legs / feet must stay on the body through take-off, flight and landing). The caller (scripts/race_legs_capture.sh)
//  records the simulator screen between the <name>.mark file this test writes and its end. Env: CAPTURE_OUT, CAPTURE_SECS.
//

import XCTest

final class RaceLegsUITests: XCTestCase {
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @MainActor
    func testHurdleJump() {
        let out = ProcessInfo.processInfo.environment["CAPTURE_OUT"] ?? "/tmp/race_legs"
        let secs = Double(ProcessInfo.processInfo.environment["CAPTURE_SECS"] ?? "70") ?? 70
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob", "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12", "-volley.partner", "99",
                                "-LobbyAuto", "track", "-RaceCourse", "wave", "-RaceAuto", "4", "-A11yAutoJump", "1"]
        app.launch()
        XCTAssertTrue(el(app, "track-race").waitForExistence(timeout: 60))
        sleep(14)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/shot_lobby.png"))
        el(app, "track-race").tap()
        sleep(3); try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/shot_after_tap.png"))
        try? "go".write(toFile: "\(out)/hurdle.mark", atomically: true, encoding: .utf8)
        var t = 0.0
        while t < secs { sleep(5); t += 5; try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/shot_\(Int(t)).png")) }
        app.terminate()
    }
}
