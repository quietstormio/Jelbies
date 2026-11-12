//
//  WearPreviewUITests.swift
//  The shop's item sheet for a wearable: Buy must be pressable the moment the sheet is up, and the fitting-room picture ("On <name>") must appear fast.
//  Timings (ms from the item tap to the picture) are printed as `WEARPREVIEW ...` lines and written to WEAR_OUT/timings.txt; WEAR_FRAMES=1 also saves a screenshot per ~0.1 s.
//

import XCTest

final class WearPreviewUITests: XCTestCase {
    func testWearSheetBuyAtOnceAndPreviewFast() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        let out = env["WEAR_OUT"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let logPath = "\(out)/app_log.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob,pearl,teddy", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "9860", "-Mute", "1", "-WearPreviewLog", logPath]
        let old = env["WEAR_OLD"] == "1"          // the old behaviour (700 ms wait, 300 ms polling, no cache), for before / after timings
        if old { app.launchArguments += ["-WearPreviewOld", "1"] }
        app.launch()
        XCTAssertTrue(app.buttons["go-out"].waitForExistence(timeout: 300), "no go-out button")
        app.buttons["go-out"].tap()
        XCTAssertTrue(app.buttons["town-shop"].waitForExistence(timeout: 30)); app.buttons["town-shop"].tap()
        let tab = app.buttons["shop-tab-wear"]
        _ = app.buttons["shop-tab-food"].waitForExistence(timeout: 30)
        for _ in 0..<3 where !tab.isHittable { app.buttons["shop-tab-food"].swipeLeft(velocity: .fast) }
        XCTAssertTrue(tab.waitForExistence(timeout: 10)); tab.tap()
        let items = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shop-item-'"))
        _ = items.firstMatch.waitForExistence(timeout: 10)
        sleep(1)
        var lines = ""
        func say(_ s: String) { print("WEARPREVIEW " + s); lines += s + "\n" }
        var ids: [String] = []
        var done = 0
        for i in 0..<items.count where ids.count < 5 {
            let e = items.element(boundBy: i)
            if e.isHittable { ids.append(e.identifier) }
        }
        XCTAssertGreaterThanOrEqual(ids.count, 3, "fewer than 3 wearables on screen")
        for pass in ["cold", "warm"] {
            for id in ids {
                let t0 = Date()
                items.matching(identifier: id).firstMatch.tap()
                let buy = app.buttons.matching(NSPredicate(format: "identifier == 'item-buy' OR label BEGINSWITH 'Buy '")).firstMatch
                let up = buy.waitForExistence(timeout: 20)
                let tSheet = Date().timeIntervalSince(t0)
                let hittable = up && buy.isHittable
                let tHit = Date().timeIntervalSince(t0)
                // the picture's own time (ms from the sheet's task start to the picture shown) comes from the app's log: XCUI queries cost ~2 s here, too coarse to time it
                func readyLines() -> [String] { ((try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.contains("preview-ready") }.map(String.init) }
                let t1 = Date()
                while readyLines().count <= done && Date().timeIntervalSince(t1) < 20 { usleep(50_000) }
                let line = readyLines().dropFirst(done).first ?? ""
                done = readyLines().count
                let ms = line.components(separatedBy: " ms=").last.flatMap { Int($0.split(separator: " ").first ?? "") } ?? 99999
                let shown = line.contains("shown=true")
                if !up { try? app.debugDescription.write(toFile: "\(out)/tree_nobuy.txt", atomically: true, encoding: .utf8) }
                say("\(old ? "OLD" : "NEW") \(pass) \(id) buy_hittable=\(hittable) (XCUI saw the sheet after \(Int(tHit * 1000)) ms) preview_ms=\(ms) shown=\(shown) [\(line.contains("cached=true") ? "cache hit" : "drawn")]")
                XCTAssertTrue(hittable, "Buy is not hittable when the sheet opens (\(id), \(pass))")
                XCTAssertTrue(shown, "no fitting-room picture (\(id), \(pass))")
                XCTAssertLessThan(ms, pass == "cold" ? 500 : 300, "preview too slow (\(id), \(pass)): \(ms) ms from the sheet's start")
                app.swipeDown(velocity: .fast)
                _ = items.firstMatch.waitForExistence(timeout: 5); usleep(600_000)
            }
        }
        try? lines.write(toFile: "\(out)/timings.txt", atomically: true, encoding: .utf8)
        app.terminate()
    }
}
