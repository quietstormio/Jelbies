//
//  WearPreviewLooksUITests.swift
//  The shop's "On <name>" picture for the slow-to-prepare looks, on a fresh one-creature game of the purple species: opens each look's item sheet (a cold wear-mesh cache per look: each look is
//  opened once, in a fresh launch) and records the app's own `preview-ready` ms (sheet task start to picture shown, including the 120 ms settle). Written to WEAR_OUT/looks.txt.
//  Looks the shop does not sell (hoodie, raincoat are unlisted; chainGold is retired) are recorded as absent.
//

import XCTest

final class WearPreviewLooksUITests: XCTestCase {
    func testPreviewReadyForTheSlowLooks() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        let out = env["WEAR_OUT"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let logPath = "\(out)/app_log.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", "lavender", "-NewGameCoins", "10000", "-MainMenu", "0", "-Intro", "0", "-Mute", "1", "-WearPreviewLog", logPath]
        if env["WEAR_OLD_PREP"] == "1" { app.launchArguments += ["-WearRadialOld", "1"] }
        app.launch()
        XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 300), "no go-out button")
        app.buttons["go-out"].tap()
        XCTAssertTrue(app.buttons["town-shop"].waitForExistence(timeout: 30)); app.buttons["town-shop"].tap()
        let tab = app.buttons["shop-tab-wear"]
        _ = app.buttons["shop-tab-food"].waitForExistence(timeout: 30)
        for _ in 0..<3 where !tab.isHittable { app.buttons["shop-tab-food"].swipeLeft(velocity: .fast) }
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        sleep(2)
        let looks = ["diamondJ": "diamond_j", "chainGold": "chain_gold", "bandanaSun": "bandana_sun", "hoodie": "hoodie", "raincoat": "raincoat", "sweatband": "sweatband", "tutuPink": "tutu_pink", "scarfPlum": "scarf_plum"]
        let order = ["diamondJ", "chainGold", "bandanaSun", "hoodie", "raincoat", "sweatband", "tutuPink", "scarfPlum"]
        func readyLines() -> [String] { ((try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.contains("preview-ready") }.map(String.init) }
        var report = ""
        for name in order {
            let item = app.buttons["shop-item-wear-\(looks[name]!)"]
            for _ in 0..<8 where !item.isHittable { app.swipeDown(velocity: .fast) }
            var tries = 0
            while !(item.exists && item.isHittable) && tries < 14 { app.swipeUp(velocity: .fast); tries += 1 }
            guard item.exists && item.isHittable else { report += "\(name)\tABSENT from the shop\n"; continue }
            let before = readyLines().count
            item.tap()
            let t1 = Date()
            while readyLines().count <= before && Date().timeIntervalSince(t1) < 40 { usleep(100_000) }
            let line = readyLines().dropFirst(before).first ?? "no preview-ready line"
            report += "\(name)\t\(line)\n"
            print("WEARLOOK \(name) \(line)")
            app.swipeDown(velocity: .fast)
            usleep(800_000)
        }
        try? report.write(toFile: "\(out)/looks.txt", atomically: true, encoding: .utf8)
        app.terminate()
    }
}
