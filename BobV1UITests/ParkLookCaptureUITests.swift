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

    /// Landscape: the same launch, rotated to landscape; saves land_1...land_3 after the park is up.
    @MainActor
    func testParkLandscape() throws {
        try XCTSkipIf(out.isEmpty, "PARK_LOOK_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob,pearl,teddy", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES",
                                "-BlobDrops.v1", "1024", "-ClockHour", "12", "-StartPark", "1"]
        app.launch()
        for k in 0..<4 {
            sleep(8)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/land_\(k + 1).png"))
        }
        app.terminate()
    }
}
