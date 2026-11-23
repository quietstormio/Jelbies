//
//  SoccerNetRuleUITests.swift
//  Capture aid for the Soccer net's owner rule (2026-11-23): the net is bought in the Shop, never placed, and shows in the Play picker only
//  once owned. Buys it through the real Shop sheet, then opens the picker and the Bag. Pictures go to NET_RULE_OUT. Skips without it.
//

import XCTest

final class SoccerNetRuleUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["NET_RULE_OUT"] ?? "" }
    private let base = ["-MainMenu", "0", "-Mute", "1", "-ClockHour", "14", "-AutoContinue", "0.5", "-BlobDrops.v1", "1024"]

    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments += base + args; app.launch(); return app
    }

    @MainActor
    func testBuyTheNetThenPickerAndBag() throws {
        try XCTSkipIf(out.isEmpty, "NET_RULE_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
        var app = launch(["-StoreOpen", "item", "-StoreItem", "decor-minigoal"])
        let buy = app.buttons["item-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 300), "the Soccer net's Shop sheet shows a Buy button")
        sleep(2); shot("b_shop_item_before_buy")
        XCTAssertTrue(buy.isEnabled, "affordable")
        buy.tap(); sleep(3); shot("b_shop_item_after_buy")
        app.terminate()
        // the picker now offers it
        app = launch(["-PlayDemo", "5"])
        sleep(25); shot("c_picker_portrait_after_buy")
        app.terminate()
        // the Bag shows it as owned, with no Place action
        app = launch(["-StoreOpen", "bag", "-StoreTab", "toys"])
        XCTAssertTrue(app.buttons["bag-close"].waitForExistence(timeout: 300))
        sleep(4); shot("d_bag_toys_portrait")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'place'")).count > 0 && app.staticTexts["Soccer net"].exists && app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'place' AND label CONTAINS 'Soccer net'")).count > 0, "no Place action for the Soccer net")
        app.terminate()
    }
}
