//
//  ShowStageUITests.swift
//  show-stage-r1: the Jelly Show stage shows the selected contestant, and what is put on in Dress up is on the stage body (lobby and Dress up), in the real app.
//  Three Jelmiko at home (Moo, Midnight, Lagoon: pink cow print, black, teal marble), the Show opened from the third one's Profile. Env: SS_OUT (a folder for the pictures; TEST_RUNNER_SS_OUT), SS_LANDSCAPE=1.
//  The pictures are the evidence (a UI test cannot read pixels of the Metal picture): every step also checks the accessibility label of the stage / Dress up figure.
//

import XCTest

final class ShowStageUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["SS_OUT"] ?? "/tmp" }
    private var land: Bool { ProcessInfo.processInfo.environment["SS_LANDSCAPE"] == "1" }
    private func shot(_ n: String) {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(land ? "l" : "p")_\(n).png"))
    }

    /// Mean absolute difference (0...1) of two pictures, both drawn into 96 x 96 grey.
    private func diff(_ a: XCUIScreenshot, _ b: XCUIScreenshot) -> Double {
        func px(_ s: XCUIScreenshot) -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: 96 * 96)
            guard let cg = s.image.cgImage, let ctx = CGContext(data: &buf, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 96, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return buf }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 96, height: 96))
            return buf
        }
        let x = px(a), y = px(b)
        return zip(x, y).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(x.count) / 255
    }

    @MainActor
    func testShowStageFollowsTheContestantAndTheOutfit() {
        XCUIDevice.shared.orientation = land ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "moo,midnight,lagoon", "-NewGameCoins", "5000", "-MainMenu", "0", "-Mute", "1", "-ClockHour", "14", "-BlobNoWander", "1",
                                "-WearList", "none", "-ForceOrientation", land ? "left" : "portrait"]
        app.launch()
        let any = { (id: String) in app.descendants(matching: .any)[id].firstMatch }
        XCTAssertTrue(app.buttons["roster-button"].waitForExistence(timeout: 120))
        sleep(4)
        app.buttons["roster-button"].tap()
        let profiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'roster-profile-'"))
        XCTAssertTrue(profiles.firstMatch.waitForExistence(timeout: 8))
        shot("00_roster")
        // the third Jelmiko's card may be below the panel's fold: the last Profile button, after scrolling the panel
        for _ in 0..<3 where profiles.count < 3 { any("roster-panel").swipeUp(); sleep(1) }
        shot("00_roster_scrolled")
        NSLog("[showstage] roster profile buttons: %d", profiles.count)
        XCTAssertEqual(profiles.count, 3)
        profiles.element(boundBy: 2).tap()          // the third Jelmiko (Lagoon)
        let got = app.buttons["Got it"]; if got.waitForExistence(timeout: 3) { got.tap() }
        let showBtn = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'condition-show' OR label CONTAINS 'Jelly Show'")).firstMatch
        sleep(3)
        let got2 = app.buttons["Got it"]; if got2.exists { got2.tap() }
        XCTAssertTrue(showBtn.waitForExistence(timeout: 20), app.debugDescription)
        shot("0_profile"); showBtn.tap()
        let stage = any("studio-action-shot")
        XCTAssertTrue(stage.waitForExistence(timeout: 30))
        sleep(4)
        XCTAssertTrue(stage.label.hasPrefix("Lagoon"), "the stage shows the selected contestant: \(stage.label)")
        shot("1_lobby_from_third_profile")
        let bareA = stage.screenshot(); sleep(1); let bareB = stage.screenshot()
        let noise = diff(bareA, bareB)          // the slow breathing swell: what "the same picture" differs by
        // Dress up: shoes and a hat go on the body at once
        any("studio-dress").tap()
        XCTAssertTrue(any("dressup-screen").waitForExistence(timeout: 10))
        sleep(3)
        shot("2_dressup_bare")
        let dressBare = any("dressup-figure").screenshot()
        let shoes = any("wardrobe-sneakerLightup")
                XCTAssertTrue(shoes.waitForExistence(timeout: 5)); shoes.tap()
        sleep(3); shot("3_dressup_sneakers")
        let figure = any("dressup-figure")
        XCTAssertGreaterThan(diff(dressBare, figure.screenshot()), noise * 3 + 0.002, "the sneakers are on the Dress up body at once")
        let hat = any("wardrobe-flowerCrown")          // a hat card in the grid (visible without scrolling)
        XCTAssertTrue(hat.waitForExistence(timeout: 5)); hat.tap()
        sleep(3); shot("4_dressup_sneakers_and_hat")
        any("dressup-back").tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 10)); sleep(3)
        shot("5_lobby_still_dressed")
        let dressedLobby = stage.screenshot()
        XCTAssertGreaterThan(diff(bareA, dressedLobby), noise * 3 + 0.002, "the sneakers and the hat Dress up put on are on the lobby's stage body")
        // the contestant cards: 1 then 2 then 3
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'studio-who-'"))
        XCTAssertEqual(tiles.count, 3)
        tiles.element(boundBy: 0).tap(); sleep(3); shot("6_card1")
        XCTAssertTrue(stage.label.hasPrefix("Moo"), "card 1 puts the first on the stage: \(stage.label)")
        let moo = stage.screenshot()
        XCTAssertGreaterThan(diff(moo, dressedLobby), noise * 3 + 0.002, "card 1: the stage BODY changed to the first contestant")
        tiles.element(boundBy: 1).tap(); sleep(3); shot("7_card2")
        XCTAssertTrue(stage.label.hasPrefix("Midnight"), "card 2 puts the second on the stage: \(stage.label)")
        XCTAssertGreaterThan(diff(stage.screenshot(), moo), noise * 3 + 0.002, "card 2: the stage BODY changed to the second contestant")
        tiles.element(boundBy: 2).tap(); sleep(3); shot("8_card3")
        XCTAssertTrue(stage.label.hasPrefix("Lagoon"))
        // the direct path Town -> Jelly Show
        any("studio-back").tap()
        sleep(2)
        let townStudio = any("town-studio")
        if townStudio.waitForExistence(timeout: 5) { townStudio.tap(); XCTAssertTrue(stage.waitForExistence(timeout: 20)); sleep(4); shot("9_direct_from_town") }
    }
}
