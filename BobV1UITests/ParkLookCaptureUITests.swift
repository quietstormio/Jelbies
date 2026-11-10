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

    /// Landscape (or `PARK_LOOK_ORIENT=portrait`): the same launch, rotated; it WAITS for the park's Go home button (`park-home`) and fails if the park does not open within 60 s,
    /// then saves land_1...land_3 (or port_*) a few seconds apart. (Round 2 captured the home room by mistake because nothing checked the park had opened.)
    @MainActor
    func testParkLandscape() throws {
        try XCTSkipIf(out.isEmpty, "PARK_LOOK_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let portrait = ProcessInfo.processInfo.environment["PARK_LOOK_ORIENT"] == "portrait"
        XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob,pearl,teddy", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES",
                                "-BlobDrops.v1", "1024", "-ClockHour", "12", "-StartPark", "1"]
        app.launch()
        let home = app.buttons["park-home"]
        let opened = home.waitForExistence(timeout: 60)
        let tag = portrait ? "port" : "land"
        if !opened { try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_FAILED_no_park.png")) }
        XCTAssertTrue(opened, "the park never opened (no park-home button) in \(tag)")
        for k in 0..<3 {
            sleep(6)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(k + 1).png"))
        }
        app.terminate()
    }
}
