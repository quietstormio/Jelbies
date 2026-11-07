//
//  BagPickerCaptureUITests.swift
//  Capture aid, not a regression test: opens the Bag (`-StoreOpen bag`) with two Jelbies and saves screenshots to BAG_OUT (TEST_RUNNER_BAG_OUT). Skips without it.
//

import XCTest

final class BagPickerCaptureUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["BAG_OUT"] ?? "" }

    private func shoot(_ orientation: UIDeviceOrientation, tab: String, name: String) throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = orientation
        app.launchArguments += ["-SetRoster", "teddy,panda", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-ClockHour", "12",
                                "-StoreOpen", "bag", "-StoreTab", tab, "-StoreSeed", "2", "-StoreWear", "1", "-BlobDrops.v1", "1024"]
        app.launch()
        XCTAssertTrue(app.buttons["bag-close"].waitForExistence(timeout: 300))
        sleep(4)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'who-'")).count, 2)
        XCTAssertEqual(app.otherElements["bag-boosts"].exists, false)
        XCTAssertTrue(app.otherElements["lobby-picker-empty"].exists || app.staticTexts["Empty slot"].exists)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        app.terminate()
    }

    @MainActor
    func testBagShots() throws {
        try XCTSkipIf(out.isEmpty, "BAG_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try shoot(.portrait, tab: "wear", name: "bag_wear_port")
        try shoot(.landscapeLeft, tab: "wear", name: "bag_wear_land")
        try shoot(.portrait, tab: "food", name: "bag_food_port")
    }
}
