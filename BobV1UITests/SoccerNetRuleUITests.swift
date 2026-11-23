//
//  SoccerNetRuleUITests.swift
//  Capture aid for the Soccer net's owner rule (2026-11-23): the Bag lists the owned net with no Place action. Pictures go to NET_RULE_OUT. Skips without it.
//

import XCTest

final class SoccerNetRuleUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["NET_RULE_OUT"] ?? "" }
    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }

    @MainActor
    func testBagListsTheOwnedNetWithoutPlace() throws {
        try XCTSkipIf(out.isEmpty, "NET_RULE_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-MainMenu", "0", "-Mute", "1", "-ClockHour", "14", "-AutoContinue", "0.5", "-PlayDemo", "5", "-GrantSoccerNet", "1", "-StoreOpen", "bag", "-StoreTab", "toys"]
        app.launch()
        XCTAssertTrue(app.buttons["bag-close"].waitForExistence(timeout: 300))
        sleep(4); shot("d_bag_toys_0")
        for k in 1...3 { app.swipeUp(velocity: .slow); sleep(1); shot("d_bag_toys_scroll\(k)") }
        app.terminate()
    }
}
