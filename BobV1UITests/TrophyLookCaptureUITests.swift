//
//  TrophyLookCaptureUITests.swift
//  Capture aid, not a regression test (trophy-look-r1): opens the Trophies sheet (`-OpenProfile 0 -OpenTrophies 1`) with the seed in TROPHY_LOOK_SEED ("reset trophymix" or "reset"),
//  saves portrait top / scrolled-to-bottom and landscape top / bottom screenshots to TROPHY_LOOK_OUT (TEST_RUNNER_TROPHY_LOOK_OUT). Skips without it.
//

import XCTest

final class TrophyLookCaptureUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["TROPHY_LOOK_OUT"] ?? "" }

    @MainActor
    func testTrophySheetShots() throws {
        try XCTSkipIf(out.isEmpty, "TROPHY_LOOK_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let tag = ProcessInfo.processInfo.environment["TROPHY_LOOK_TAG"] ?? "shot"
        let seed = ProcessInfo.processInfo.environment["TROPHY_LOOK_SEED"] ?? "reset trophymix"
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "1024", "-ClockHour", "12", "-Mute", "1",
                                "-LobbySeed", seed, "-OpenProfile", "0", "-OpenTrophies", "1"]
        app.launch()
        let sheet = app.otherElements["trophies-sheet"]
        XCTAssertTrue(app.buttons["trophies-close"].waitForExistence(timeout: 120), "the Trophies sheet never opened")
        sleep(3)
        for _ in 0..<3 where app.buttons["Got it"].exists { app.buttons["Got it"].tap(); sleep(1) }          // (the first-visit tip card)
        func shot(_ name: String) { try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(name).png")) }
        shot("port_1_top")
        for k in 2...4 { app.swipeUp(velocity: .slow); sleep(1); shot("port_\(k)_scroll") }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(5); shot("land_1_top")
        for k in 2...5 { app.swipeUp(velocity: .slow); sleep(1); shot("land_\(k)_scroll") }
        _ = sheet
        app.terminate()
    }
}
