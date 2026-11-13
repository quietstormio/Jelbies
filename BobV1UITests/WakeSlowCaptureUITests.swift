//
//  WakeSlowCaptureUITests.swift
//  Capture aid (off unless WAKE_UI_OUT is set): the REAL app, one Jelbie sent to bed (-SleepNow 1, by day: a nap), then either a tap on him (WAKE_UI_MODE=tap: the host writes tap.xy "x y" normalised
//  after ready.mark, then go.mark) or nothing (natural: he wakes when his nap is over). A host script records the simulator video; this test writes ready.mark / tap.epoch / done.mark into WAKE_UI_OUT.
//

import XCTest

final class WakeSlowCaptureUITests: XCTestCase {
    @MainActor
    func testSleeperWake() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["WAKE_UI_OUT"] else { throw XCTSkip("set TEST_RUNNER_WAKE_UI_OUT") }
        let mode = env["WAKE_UI_MODE"] ?? "tap", secs = Double(env["WAKE_UI_SECS"] ?? "20") ?? 20
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        func mark(_ n: String, _ s: String = "") { try? s.write(toFile: "\(out)/\(n)", atomically: true, encoding: .utf8) }
        let app = XCUIApplication()
        app.launchArguments += ["-Mute", "1", "-SetRoster", env["WAKE_UI_ROSTER"] ?? "pip", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-StoreSeed", "2", "-ClockHour", env["WAKE_UI_HOUR"] ?? "12", "-NeedsReset", "1", "-SleepNow", "1"]
        if let extra = env["WAKE_UI_ARGS"], !extra.isEmpty { app.launchArguments += extra.split(separator: " ").map(String.init) }
        app.launch()
        XCTAssertTrue(app.buttons["care-menu"].waitForExistence(timeout: 30), "care menu")
        sleep(UInt32(env["WAKE_UI_WAIT"] ?? "25") ?? 25)          // (sent to bed, lying down)
        mark("ready.mark", String(format: "%.3f", Date().timeIntervalSince1970))
        if mode == "tap" {
            for _ in 0..<1200 where !FileManager.default.fileExists(atPath: "\(out)/go.mark") { usleep(100_000) }
            let xy = ((try? String(contentsOfFile: "\(out)/tap.xy", encoding: .utf8)) ?? "0.5 0.55").split(separator: " ").compactMap { Double($0) }
            app.coordinate(withNormalizedOffset: CGVector(dx: xy.first ?? 0.5, dy: xy.count > 1 ? xy[1] : 0.55)).tap()
            mark("tap.epoch", String(format: "%.3f", Date().timeIntervalSince1970))
        }
        Thread.sleep(forTimeInterval: secs)
        mark("done.mark")
    }
}
