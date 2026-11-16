//
//  TipStrokeUITests.swift
//  The tip card has its own window and a tap-outside recognizer; this proves a 3 s stroke on a Jelmiko still gives its haptics (the -HapticLog CSV) and hearts (frames) after the card is
//  gone, whether it went with "Got it" or with a tap outside, and compares both with a run that never showed a card (control). Pictures and counts go to TIPS_OUT.
//

import XCTest

final class TipStrokeUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["TIPS_OUT"] ?? "/tmp/tips_ui"
    private let base = ["-NewGame", "bob", "-NewGameCoins", "10000", "-MainMenu", "0", "-TipsReset", "1", "-NeedsHappy", "1"]
    override func setUp() { continueAfterFailure = false; try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true) }

    private func shot(_ name: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: Self.out + "/\(name).png")) }

    /// (haptic events in the CSV, by kind) after the stroke.
    private func haptics(_ path: String) -> (total: Int, kinds: [String: Int]) {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return (0, [:]) }
        var k: [String: Int] = [:]
        for l in s.split(separator: "\n").dropFirst() { let c = l.split(separator: ",", omittingEmptySubsequences: false); if c.count > 1 { k[String(c[1]), default: 0] += 1 } }
        return (k.values.reduce(0, +), k)
    }

    private func run(_ name: String, dismiss: String) {
        let log = Self.out + "/haptic_\(name).csv"; try? FileManager.default.removeItem(atPath: log)
        let app = XCUIApplication()
        app.launchArguments += base + ["-HapticLog", log] + (dismiss == "none" ? [] : ["-TipShow", "powerup"])
        app.launch()
        if dismiss != "none" {
            let card = app.otherElements["tip-powerup"]
            XCTAssertTrue(card.waitForExistence(timeout: 150), "the card is up")
            shot("\(name)_1_card")
            if dismiss == "gotit" { app.buttons["tip-got-it"].tap() }
            else { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.85)).tap() }          // a tap on the floor, away from the Jelmiko
            let gone = NSPredicate(format: "exists == false"); expectation(for: gone, evaluatedWith: card); waitForExpectations(timeout: 15)
            shot("\(name)_2_gone")
        } else { sleep(60) }
        // close-up: heart > Come here
        var opened = false
        for _ in 0..<4 where !opened {          // (a busy simulator answers a query late: tap the heart, give it time, look again)
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.91)).tap()
            sleep(4)
            opened = app.staticTexts["Come here"].waitForExistence(timeout: 30)
        }
        XCTAssertTrue(opened, "the heart menu is open"); app.staticTexts["Come here"].tap()
        XCTAssertTrue(app.buttons["focus-release"].waitForExistence(timeout: 150), "the close-up is up")
        sleep(3)
        let before = haptics(log).total
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)), b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        var frames = 0
        for i in 0..<3 {          // 3 strokes of a slow rub = about 3 s of petting (as PetFixWatchUITests)
            a.press(forDuration: 0.6, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.2)
            if i == 1 { shot("\(name)_3_stroke"); frames += 1 }
        }
        shot("\(name)_4_after"); sleep(3)
        let h = haptics(log)
        try? "\(name): haptic events before stroke \(before), after \(h.total) (new \(h.total - before)), kinds \(h.kinds)\n".write(toFile: Self.out + "/stroke_\(name).txt", atomically: true, encoding: .utf8)
        XCTAssertGreaterThan(h.total, before, "\(name): the stroke gave haptics")
    }

    func testControlNoCard() { run("control", dismiss: "none") }
    func testStrokeAfterGotIt() { run("gotit", dismiss: "gotit") }
    func testStrokeAfterTapOutside() { run("outside", dismiss: "outside") }
}
