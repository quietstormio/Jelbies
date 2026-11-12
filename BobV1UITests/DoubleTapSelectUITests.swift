//
//  DoubleTapSelectUITests.swift
//  A double tap on the visible body of a Jelbie selects him (the name chip "hud-name" shows), every time: with ONE Jelbie (no silhouettes are
//  published for a hit test until a pick is running, so the double tap used to miss until a voice name had started one) and with two.
//

import XCTest

final class DoubleTapSelectUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func run(roster: String, wander: Bool, label: String) {
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", roster, "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-ClockHour", "12", "-Mute", "1"]
        if !wander { app.launchArguments += ["-BlobNoWander", "1"] }
        app.launch()
        let ids = roster.split(separator: ",").count
        XCTAssertTrue(app.buttons["care-menu"].waitForExistence(timeout: 90))
        Thread.sleep(forTimeInterval: 8)
        var hits = 0
        for i in 0..<10 {
            let id = i % ids
            let e = app.descendants(matching: .any).matching(identifier: "jelbie-\(id)").firstMatch
            guard e.waitForExistence(timeout: 5) else { continue }
            let f = e.frame
            let win = app.windows.firstMatch.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX - win.minX, dy: f.midY - win.minY)).doubleTap()
            let chip = app.staticTexts["hud-name"]
            if chip.waitForExistence(timeout: 3) { hits += 1 } else { print("DOUBLETAP_MISS \(label) i=\(i) id=\(id) frame=\(f) value=\(e.value ?? "")") }
            let clear = app.buttons["hud-clear"]
            if clear.exists { clear.tap(); Thread.sleep(forTimeInterval: 1.0) }
        }
        print("DOUBLETAP_RESULT \(label): \(hits)/10")
        XCTAssertEqual(hits, 10, "\(label): selected \(hits) of 10 double taps")
        app.terminate()
    }

    @MainActor func testOneJelbieStanding() { run(roster: "bob", wander: false, label: "one standing") }
    @MainActor func testOneJelbieWandering() { run(roster: "bob", wander: true, label: "one wandering") }
    @MainActor func testTwoJelbies() { run(roster: "bob,pip", wander: false, label: "two") }
}
