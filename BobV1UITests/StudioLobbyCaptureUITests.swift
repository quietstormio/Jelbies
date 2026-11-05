//
//  StudioLobbyCaptureUITests.swift
//  Capture aid, not a regression test: opens the Studio lobby directly (`-StoreOpen studio`) and saves timed screenshots to STUDIO_OUT (TEST_RUNNER_STUDIO_OUT):
//  a shot every 0.5 s for the first seconds (how fast the picker tiles and the action shot appear), then the Enter Jelly Show flow. Skips without it.
//

import XCTest

final class StudioLobbyCaptureUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["STUDIO_OUT"] ?? "" }
    private var tag: String { ProcessInfo.processInfo.environment["STUDIO_TAG"] ?? "run" }

    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(name).png"))
    }

    private func run(landscape: Bool) throws {
        try XCTSkipIf(out.isEmpty, "STUDIO_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob,pearl,teddy", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "1024", "-BlobNoWander", "1",
                                "-ClockHour", "12", "-StoreOpen", "studio", "-ShowSeedGoods", "1"]
        if landscape { app.launchArguments += ["-ForceOrientation", "left"] }
        app.launch()
        let name = landscape ? "land" : "port"
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 20) { skip.tap() }
        _ = app.descendants(matching: .any)["studio-screen"].firstMatch.waitForExistence(timeout: 60)
        let t0 = Date()
        for k in 0..<16 {
            shot("\(name)_t\(k)")
            NSLog("[studiocap] %@ k=%d t=%.2f", name, k, Date().timeIntervalSince(t0))
            usleep(500_000)
        }
        sleep(2)
        shot("\(name)_lobby")
        let enter = app.descendants(matching: .any)["studio-show"].firstMatch
        if enter.waitForExistence(timeout: 5) { enter.tap() }
        for k in 0..<8 { sleep(2); shot("\(name)_enter\(k)") }
        app.terminate()
    }

    /// The real way in: the Town ("Where to?"), then the Studio card. Shots every ~0.25 s after the tap (names carry the milliseconds) to time the tiles; STUDIO_OFF=1 launches with the old picture loading.
    @MainActor func testOpenFromTown() throws {
        try XCTSkipIf(out.isEmpty, "STUDIO_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob,pearl,teddy", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "1024", "-BlobNoWander", "1",
                                "-ClockHour", "12", "-StoreOpen", "town", "-ShowSeedGoods", "1"]
        if ProcessInfo.processInfo.environment["STUDIO_OFF"] == "1" { app.launchArguments += ["-PortraitCacheOff", "1"] }
        app.launch()
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 20) { skip.tap() }
        let studio = app.descendants(matching: .any)["town-studio"].firstMatch
        XCTAssertTrue(studio.waitForExistence(timeout: 60))
        sleep(6)
        let t0 = Date()
        studio.tap()
        NSLog("[studiocap] tapped Studio")
        for _ in 0..<24 {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_town_\(String(format: "%05d", ms)).png"))
        }
        app.terminate()
    }

    @MainActor func testPortrait() throws { try run(landscape: false) }
    @MainActor func testLandscape() throws { try run(landscape: true) }
}
