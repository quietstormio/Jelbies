//
//  ShopHeaderShotsUITests.swift
//  Screenshots of the Shop's header (title, subtitle, coins pill, category pills, wave) in portrait, landscape and at a large Dynamic Type size, into SHOP_OUT (before / after the spacing change).
//

import XCTest

final class ShopHeaderShotsUITests: XCTestCase {
    func testShopHeaderShots() throws {
        let out = ProcessInfo.processInfo.environment["SHOP_OUT"] ?? NSTemporaryDirectory()
        let tag = ProcessInfo.processInfo.environment["SHOP_TAG"] ?? "shot"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        for (name, big) in [("normal", false), ("bigtext", true)] {
            let app = XCUIApplication()
            app.launchArguments += ["-SetRoster", "bob,pearl,teddy", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "9860", "-Mute", "1"]
            if big { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 300))
            app.buttons["go-out"].tap()
            XCTAssertTrue(app.buttons["town-shop"].waitForExistence(timeout: 30)); app.buttons["town-shop"].tap()
            _ = app.buttons["shop-back"].waitForExistence(timeout: 30); sleep(2)
            func shot(_ o: String) { try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(name)_\(o).png")) }
            shot("portrait")
            XCUIDevice.shared.orientation = .landscapeLeft; sleep(3); shot("landscape")
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
    }
}
