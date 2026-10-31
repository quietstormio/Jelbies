//
//  TeddyEarsAppUITests.swift
//  Not a regression test: the REAL app with Lavender, Pearl and Teddy, screenshots written to TEDDYAPP_DIR (env-gated). Portrait and landscape.
//

import XCTest

final class TeddyEarsAppUITests: XCTestCase {
    func testTeddyRoomShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["TEDDYAPP_DIR"], !dir.isEmpty else { throw XCTSkip("TEDDYAPP_DIR not set") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "lavender,pearl,teddy", "-NewGameCoins", "10000", "-MainMenu", "0"]
        app.launch()
        let cont = app.buttons["Continue"]
        if cont.waitForExistence(timeout: 20) { for _ in 0..<6 { if cont.exists, cont.isHittable { cont.tap() }; Thread.sleep(forTimeInterval: 2) } }
        _ = app.buttons["care-menu"].waitForExistence(timeout: 90)
        Thread.sleep(forTimeInterval: 30)
        for (name, o) in [("portrait", UIDeviceOrientation.portrait), ("landscape", UIDeviceOrientation.landscapeLeft)] {
            XCUIDevice.shared.orientation = o
            Thread.sleep(forTimeInterval: 12)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/06_app_\(name).png"))
            Thread.sleep(forTimeInterval: 6)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/06_app_\(name)_b.png"))
        }
    }
}
