//
//  SpringArmUITests.swift
//  Capture aid, not a regression test (skips without SPRING_OUT): switches through the Jelly Spring's seven species with the arrows while a recording runs outside.
//  SPRING_MODE = calm (2 s per page) | fast (0.4 s per page) | settled (2.5 s, a screenshot per page) ; SPRING_ROUNDS = laps (forward then back), SPRING_PAGE = start page.
//  SPRING_FLAG = extra launch argument pair "-Name value" (e.g. "-SpringArmOld 1"). Writes marker lines to SPRING_OUT/marks.txt (wall clock per step).
//

import XCTest

final class SpringArmUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    @MainActor func testSwitching() throws {
        guard let out = env["SPRING_OUT"], !out.isEmpty else { throw XCTSkip("SPRING_OUT not set") }
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let mode = env["SPRING_MODE"] ?? "calm"
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "lavender", "-NewGameCoins", "10000", "-Mute", "1", "-MainMenu", "0", "-Intro", "0", "-ClockHour", "12",
                                "-PickerMode", "more", "-PickerPage", env["SPRING_PAGE"] ?? "0"]
        if let f = env["SPRING_FLAG"], !f.isEmpty { app.launchArguments += f.split(separator: " ").map(String.init) }
        app.launch()
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) { skip.tap() }
        let next = app.buttons["Next Jelmiko"], prev = app.buttons["Previous Jelmiko"]
        XCTAssertTrue(next.waitForExistence(timeout: 60))
        var marks = ""
        func mark(_ s: String) { marks += String(format: "%.3f %@\n", Date().timeIntervalSince1970, s); try? marks.write(toFile: "\(out)/marks.txt", atomically: true, encoding: .utf8) }
        func shot(_ n: String) { try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(n).png")) }
        sleep(4)
        mark("start")
        let rounds = mode == "midwave" ? 0 : (Int(env["SPRING_ROUNDS"] ?? "1") ?? 1)
        let dwell: UInt32 = mode == "fast" ? 400_000 : (mode == "settled" ? 2_500_000 : 2_000_000)
        let start = Int(env["SPRING_PAGE"] ?? "0") ?? 0
        for _ in 0..<rounds {
            for i in 1...6 { next.tap(); mark("fwd \((start + i) % 7)"); usleep(dwell); if mode == "settled" { shot("settled_p\((start + i) % 7)") } }
            for i in 1...6 { prev.tap(); mark("back \((start + 6 - i) % 7)"); usleep(dwell) }
        }
        if mode == "midwave" {
            // switch away while the creature is mid-move: tap at 1.0 s after landing, then again at 0.9 s
            for i in 1...6 { next.tap(); usleep(1_000_000 + UInt32(i % 3) * 300_000); mark("mid \(i)") }
        }
        mark("end")
        sleep(1)
        app.terminate()
    }
}
