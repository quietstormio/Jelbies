//
//  RaceLegsUITests.swift
//  Real-app capture of hurdle jumps in the Jelly Circuit (legs / feet must stay on the body through take-off, flight and landing). The race starts straight from launch
//  (-RaceStart 1: the capture aid in GameScreen; the Track lobby path left the Jelbie idling). The caller (scripts/race_legs_capture.sh) records the simulator screen
//  between the <name>.mark file this test writes and its end. Env: CAPTURE_OUT, CAPTURE_SECS.
//

import XCTest

final class RaceLegsUITests: XCTestCase {
    @MainActor
    func testHurdleJump() {
        let out = ProcessInfo.processInfo.environment["CAPTURE_OUT"] ?? "/tmp/race_legs"
        let secs = Double(ProcessInfo.processInfo.environment["CAPTURE_SECS"] ?? "70") ?? 70
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob", "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12", "-volley.partner", "99",
                                "-NeedsHappy", "1", "-RaceStart", "1", "-RaceStartDelay", "8", "-RaceSeed", "7", "-RaceCourse", "wave", "-RaceAuto", "4", "-A11yAutoJump", "1"]
        app.launch()
        let cont = app.buttons["Continue"]          // (a cold launch can land on the title screen)
        if cont.waitForExistence(timeout: 5) { cont.tap() }
        sleep(8)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/shot_start.png"))
        try? "go".write(toFile: "\(out)/hurdle.mark", atomically: true, encoding: .utf8)
        var t = 0.0
        while t < secs { sleep(10); t += 10; try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/shot_\(Int(t)).png")) }
        app.terminate()
    }
}
