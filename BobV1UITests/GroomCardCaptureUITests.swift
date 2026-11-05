//
//  GroomCardCaptureUITests.swift
//  Capture aid, not a regression test: launches the REAL app straight into the Jelly Spa street (`-GroomAuto visit`) and saves portrait screenshots
//  to GROOM_CARD_OUT (TEST_RUNNER_GROOM_CARD_OUT) for the town "Where to?" Groomer card (town_preview_groom). Skips without it.
//

import XCTest

final class GroomCardCaptureUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["GROOM_CARD_OUT"] ?? "" }

    @MainActor
    func testGroomStreetShots() throws {
        try XCTSkipIf(out.isEmpty, "GROOM_CARD_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES",
                                "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12", "-GroomAuto", "visit"]
        app.launch()
        sleep(5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        for k in 0..<12 {          // (12 x 2 s: the street fades in at a different moment on a busy Mac; pick a settled frame)
            sleep(2)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/street_\(k + 1).png"))
        }
        app.terminate()
    }
}
