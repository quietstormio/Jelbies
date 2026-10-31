//
//  WhiteWingUITests.swift
//  Capture aid, not a regression test: launches the REAL app with `-ForceSpecies whitewing` (the look-only candidate) and saves screenshots of the
//  room (portrait + landscape), the Clean (bath) stages and the Jelly Spa to WW_APP_OUT (TEST_RUNNER_WW_APP_OUT). Skips without it.
//

import XCTest

final class WhiteWingUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["WW_APP_OUT"] ?? "" }
    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }
    private func launch(_ extra: [String] = [], roster: String = "bob,pip,lavender") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", roster, "-ForceSpecies", "whitewing", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES",
                                "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12"] + extra
        app.launch()
        return app
    }

    @MainActor
    func testWhiteWingInTheApp() throws {
        try XCTSkipIf(out.isEmpty, "WW_APP_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
        var app = launch()
        sleep(14); save("07_app_room_portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(6); save("07_app_room_landscape")
        app.terminate()
        // bath: scripted Clean, held at every complete stage
        XCUIDevice.shared.orientation = .portrait
        app = launch(["-BlobGameDemo", "gclean", "-BathHold", "1"])
        sleep(5); save("08_app_pre_tap"); app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        for k in 0..<8 { sleep(5); save("08_app_bath_\(k + 1)") }
        app.terminate()
        // spa: the picker, then a visit
        app = launch(["-GroomAuto", "visit"])
        sleep(5); app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        for k in 0..<4 { sleep(7); save("09_app_spa_\(k + 1)") }
        app.terminate()
    }
}
