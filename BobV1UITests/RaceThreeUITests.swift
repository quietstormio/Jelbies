//
//  RaceThreeUITests.swift
//  Real-app capture of the track meet with a roster of two (Teddy + Panda): three racers in three lanes (the third a temporary rival body), then back home with only the roster.
//  The race starts straight from launch (-RaceStart 1). Screenshots every ~1.5 s into CAPTURE_OUT; the caller (scripts/race_three_capture.sh) records the screen from the mark file.
//

import XCTest

final class RaceThreeUITests: XCTestCase {
    @MainActor
    func testThreeRacers() {
        let out = ProcessInfo.processInfo.environment["CAPTURE_OUT"] ?? "/tmp/race_three"
        let secs = Double(ProcessInfo.processInfo.environment["CAPTURE_SECS"] ?? "90") ?? 90
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        app.launchArguments += ["-SetRoster", env["CAPTURE_ROSTER"] ?? "teddy,panda", "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12", "-volley.partner", "99",
                                "-Mute", "1", "-NeedsHappy", "1", "-RaceStart", "1", "-RaceStartDelay", "6", "-RaceSeed", env["CAPTURE_SEED"] ?? "7", "-RaceAuto", "4", "-A11yAutoJump", "1"]
        app.launch()
        let cont = app.buttons["Continue"]          // (a cold launch can land on the title screen)
        if cont.waitForExistence(timeout: 5) { cont.tap() }
        let skip = app.buttons["Skip"]          // (the intro, when the host is slow enough that it is still playing)
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        try? "go".write(toFile: "\(out)/race.mark", atomically: true, encoding: .utf8)
        let t0 = Date()
        var i = 0
        while Date().timeIntervalSince(t0) < secs {
            let t = Date().timeIntervalSince(t0)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/s_\(String(format: "%03d", i))_\(Int(t)).png"))
            i += 1
            usleep(700_000)
        }
        app.terminate()
    }
}
