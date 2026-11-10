//
//  ParkLookCaptureUITests.swift
//  Capture aid, not a regression test: launches the REAL app straight into the Park (`-StartPark 1`) and saves portrait screenshots to PARK_LOOK_OUT
//  (TEST_RUNNER_PARK_LOOK_OUT) for the trees / bushes / flower patches look. Skips without it.
//

import XCTest

final class ParkLookCaptureUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["PARK_LOOK_OUT"] ?? "" }

    @MainActor
    func testParkShots() throws {
        try XCTSkipIf(out.isEmpty, "PARK_LOOK_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES",
                                "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12", "-StartPark", "1"]
        app.launch()
        for k in 0..<8 {
            sleep(4)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/park_\(k + 1).png"))
        }
        app.terminate()
    }

    /// Landscape (or `PARK_LOOK_ORIENT=portrait`) capture of a park that is ALREADY OPEN in a separately launched app. Finding (2026-11-09): when XCUIApplication launches the app, the park never opens, neither
    /// through the `-StartPark 1` hook nor by tapping Go out > Park > Go (cause not found; XCTest also changes the app's persistence / forced-hour / audio paths), in portrait as well as landscape. So this
    /// test does NOT launch the app: start it from outside with `simctl launch ... -StartPark 1` while this test sleeps (PARK_LOOK_WAIT seconds, default 50), then it rotates the device and saves
    /// <tag>_1...3. The test cannot see the app's elements without relaunching it, so whoever runs it must LOOK at the pictures.
    @MainActor
    func testParkLandscape() throws {
        try XCTSkipIf(out.isEmpty, "PARK_LOOK_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let env = ProcessInfo.processInfo.environment
        let portrait = env["PARK_LOOK_ORIENT"] == "portrait"
        let wait = UInt32(env["PARK_LOOK_WAIT"] ?? "50") ?? 50
        sleep(wait)
        XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
        let tag = portrait ? "port" : "land"          // (no XCUIApplication here at all: activate() / element queries would RELAUNCH the app without the -StartPark argument and show the title screen)
        for k in 0..<3 {
            sleep(5)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(k + 1).png"))
        }
    }
}
