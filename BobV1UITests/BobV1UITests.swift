//
//  BobV1UITests.swift
//  BobV1UITests
//
//  Created by Dione Marshall on 10/12/26.
//

import XCTest

final class BobV1UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launchArguments += ["-MelonStudio", "1"]
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    /// A one-finger drag that starts on the stage must not scroll the compact page; a drag on the masthead must.
    @MainActor
    func testStageDragDoesNotScrollPage() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone-layout only")
        let app = XCUIApplication()
        app.launchArguments += ["-MelonStudio", "1"]
        app.launch()
        let stage = app.otherElements["melon-stage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        let chip = app.descendants(matching: .any)["status-chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        let y0 = chip.frame.minY

        let a = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let b = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        a.press(forDuration: 0.1, thenDragTo: b)
        sleep(1)
        XCTAssertEqual(chip.frame.minY, y0, accuracy: 1, "page scrolled while dragging the stage")

        // control: dragging on the masthead scrolls the page
        // (the stage starts at about 31% of the window height now that the masthead is short, so start inside the copy)
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let up = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
        top.press(forDuration: 0.1, thenDragTo: up)
        sleep(1)
        XCTAssertLessThan(chip.frame.minY, y0 - 20, "control drag outside the stage should scroll")
    }

    // MARK: - Panel controls

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-MelonStudio", "1"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["status-chip"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Swipes the page up (starting outside the stage) until the element is hittable.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ id: String) {
        let e = el(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 10), "\(id) missing")
        var n = 0
        while !e.isHittable && n < 8 {
            let win = app.windows.firstMatch
            let from = win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            let to = win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            // On compact layouts the bottom of the screen is the panel/notes area, not the stage.
            if app.windows.firstMatch.frame.width > 700 { break }
            from.press(forDuration: 0.05, thenDragTo: to)
            n += 1
        }
    }

    /// The tap is delivered immediately, but the SwiftUI -> accessibility label update lags it by ~0.5 s while the
    /// Metal sim is loading the main thread (measured: label still old at t+0.0 s, new at t+0.5 s). Wait for the
    /// label to reach the expected value (the assertion is unchanged, it just isn't read before the UI can show it).
    @MainActor
    private func awaitLabel(_ e: XCUIElement, _ expected: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let t0 = Date()
        while e.label != expected && Date().timeIntervalSince(t0) < timeout { usleep(100_000) }
        XCTAssertEqual(e.label, expected, file: file, line: line)
    }

    private func num(_ s: String) -> Double? {
        let m = s.split(separator: " ").first.map(String.init) ?? s
        return Double(m.replacingOccurrences(of: "≈", with: ""))
    }

    @MainActor
    func testPauseToggle() throws {
        let app = launch()
        let chip = el(app, "status-chip")
        reveal(app, "btn-pause")
        let live = NSPredicate(format: "label CONTAINS[c] 'LIVE'")
        expectation(for: live, evaluatedWith: chip)
        waitForExpectations(timeout: 10)
        el(app, "btn-pause").tap()
        expectation(for: NSPredicate(format: "label CONTAINS[c] 'PAUSED'"), evaluatedWith: chip)
        waitForExpectations(timeout: 5)
        el(app, "btn-pause").tap()
        expectation(for: live, evaluatedWith: chip)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testNudgeDecays() throws {
        let app = launch()
        reveal(app, "btn-nudge")
        let kin = el(app, "stat-kinetic")
        sleep(3)
        el(app, "btn-nudge").tap()
        var peak = 0.0
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 1.5 {
            peak = max(peak, num(kin.value as? String ?? "") ?? 0)
            if peak > 0 { break }
        }
        XCTAssertGreaterThan(peak, 0, "kinetic never rose after nudge")
        let settled = NSPredicate { _, _ in (self.num(kin.value as? String ?? "") ?? 99) < 0.5 }
        expectation(for: settled, evaluatedWith: nil)
        // Measured in an optimised harness (firmness 0.33): the readout last exceeds 0.5 uJ at ~4.4 s of sim time
        // (Bob is softer and bigger than the old melon slice, and the energy sloshes back and forth before it dies).
        // The unoptimised Debug sim in the UI-test simulator runs ~3x slower than real time (readout still
        // ~12 uJ after 14 s wall), so allow 30 s wall. The sim now runs at most 2 fixed steps per frame (was 3), which slows this
        // Debug-only case further (~16% of real time), so the wall timeout is 60 s.
        waitForExpectations(timeout: 60)
    }

    @MainActor
    func testHopAroundToggle() throws {
        let app = launch()
        reveal(app, "btn-hop")
        let hop = el(app, "btn-hop")
        XCTAssertEqual(hop.label, "Hop around")
        hop.tap()
        awaitLabel(hop, "Stop hopping")
        let kin = el(app, "stat-kinetic")
        var peak = 0.0
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 4.5 { peak = max(peak, num(kin.value as? String ?? "") ?? 0) }
        XCTAssertGreaterThan(peak, 0, "kinetic never rose while hopping")
        XCTAssertTrue(app.state == .runningForeground)
        hop.tap()
        awaitLabel(hop, "Hop around")
        XCTAssertTrue(app.state == .runningForeground)
    }

    @MainActor
    func testControlsKeepVolumeStable() throws {
        let app = launch()
        reveal(app, "swatch-yellow")
        func checkVolume(_ what: String, settle: UInt32 = 1) {
            sleep(settle)
            let v = num(el(app, "stat-volume").value as? String ?? "") ?? -1
            XCTAssertGreaterThanOrEqual(v, 95, "volume after \(what)")
            XCTAssertLessThanOrEqual(v, 105, "volume after \(what)")
        }
        el(app, "swatch-yellow").tap(); checkVolume("yellow")
        for id in ["swatch-pink", "swatch-blue"] { reveal(app, id); el(app, id).tap(); checkVolume(id) }
        reveal(app, "btn-reset"); el(app, "btn-reset").tap(); checkVolume("reset", settle: 4) // reset re-drops the body; landing squash briefly dips to ~94%
        reveal(app, "toggle-slow"); el(app, "toggle-slow").tap(); checkVolume("slow on")
        el(app, "toggle-slow").tap(); checkVolume("slow off")
        reveal(app, "toggle-mesh"); el(app, "toggle-mesh").tap(); checkVolume("mesh on")
        el(app, "toggle-mesh").tap(); checkVolume("mesh off")
        XCTAssertTrue(app.state == .runningForeground)
    }

    @MainActor
    private func dragSlider(_ id: String, initial: String, endX: Double = 0.97) throws {
        let app = launch()
        reveal(app, id)
        let s = el(app, id)
        XCTAssertEqual(s.value as? String, initial)
        let chip = el(app, "status-chip")
        let y0 = s.frame.minY
        let chipY0 = chip.frame.minY
        let f = s.frame
        let thumb = s.coordinate(withNormalizedOffset: CGVector(dx: (6.5 + Double(initial)! * (f.width - 13)) / f.width, dy: 0.5))
        let end = s.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5))
        thumb.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        XCTAssertNotEqual(s.value as? String, initial, "slider did not change")
        XCTAssertEqual(s.frame.minY, y0, accuracy: 2, "page scrolled during slider drag")
        _ = chipY0
        let v = Double(s.value as? String ?? "0") ?? 0
        if endX > 0.5 { XCTAssertGreaterThan(v, 0.8) } else { XCTAssertLessThan(v, 0.6) }
    }

    // Firmness now defaults to 0.95 (near the top of the track), so drag toward the left instead.
    @MainActor
    func testFirmnessSliderDrag() throws {
        try dragSlider("slider-firmness", initial: "0.95", endX: 0.3)
    }

    @MainActor func testDampingSliderDrag() throws {
        let app = launch()
        reveal(app, "slider-damping")
        let initial = el(app, "slider-damping").value as? String ?? ""
        app.terminate()
        try dragSlider("slider-damping", initial: initial)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Game mode: the care button expands into Feed / Drink / Call and collapses after choosing. Feed and Drink share one
    /// meal tray: both are disabled while it is out. All waits are condition based (no fixed timings).
    @MainActor
    func testCareMenuFeedWaterCall() throws {
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["care-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        let feed = app.buttons["care-feed"], water = app.buttons["care-water"]
        XCTAssertFalse(feed.exists, "collapsed menu hides its actions")

        func waitFor(_ format: String, _ element: XCUIElement, _ timeout: TimeInterval = 20, _ message: String) {
            let e = expectation(for: NSPredicate(format: format), evaluatedWith: element)
            XCTAssertEqual(XCTWaiter().wait(for: [e], timeout: timeout), .completed, message)
        }
        func open() {
            menu.tap()
            XCTAssertTrue(feed.waitForExistence(timeout: 10), "menu expands")
            XCTAssertTrue(water.exists)
        }
        func choose(_ b: XCUIElement) {
            b.tap()
            waitFor("exists == false", b, 10, "menu collapses after choosing")
        }
        /// With 2+ drinks, Water unfolds a drink picker (water, soda); choosing one starts it and collapses the menu.
        func chooseWater() {
            water.tap()
            let waterPick = app.buttons["care-drink-water"], sodaPick = app.buttons["care-drink-soda"]
            XCTAssertTrue(waterPick.waitForExistence(timeout: 10), "Water unfolds the drink picker once there are 2+ drinks")
            XCTAssertTrue(sodaPick.exists)
            choose(waterPick)
            waitFor("exists == false", water, 10, "menu collapses after choosing a drink")
        }

        open()
        XCTAssertTrue(feed.isEnabled && water.isEnabled)
        // Feed opens a tiny picker of the catalogue's foods; choosing one starts it and collapses the menu
        feed.tap()
        let berries = app.buttons["care-food-berries"], pizza = app.buttons["care-food-pizza"]
        XCTAssertTrue(berries.waitForExistence(timeout: 10), "Feed unfolds the food picker")
        XCTAssertTrue(pizza.exists)
        choose(pizza)
        waitFor("exists == false", feed, 10, "menu collapses after choosing a food")

        // the tray is out (one tray at a time): Feed and Drink are disabled
        open()
        waitFor("isEnabled == false", feed, 10, "Feed is disabled while the tray is out")
        XCTAssertFalse(water.isEnabled, "Drink waits for the tray too (one tray at a time)")
        // (Come here left the menu: the close-up opens from Train tricks / voice / his bubble)
        menu.tap()
        waitFor("exists == false", feed, 10, "the menu closes")
        open()
        waitFor("isEnabled == true", feed, 180, "Feed is available again once the tray is gone")
        waitFor("isEnabled == true", water, 180, "Drink is available again once the tray is gone")
        chooseWater()
    }

    /// The roster card shows the Nintendogs-style status words (Hunger, Thirst, Attention, Coat) for each Blob.
    @MainActor
    func testRosterCardShowsStatusWords() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-NeedsReset", "1"]          // first-launch seed: hunger 0.2 (Hungry), thirst / attention 0.85 (Quenched / Content)
        app.launch()
        let button = app.buttons["roster-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        let card = app.buttons["roster-card-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the panel lists Bob's card")
        let v = (card.value as? String) ?? ""
        // the seed drains a hair as the app starts, so the tier is one of the neighbours: check the shape, not the exact word
        XCTAssertNotNil(v.range(of: #"Hunger (Full|Normal|Hungry|Famished), Thirst (Quenched|Normal|Thirsty|Parched), Attention (Content|Normal|Lonely|Neglected), Coat (Beautiful|Clean|Normal|Dirty|Filthy)"#, options: .regularExpression), "status summary: \(v)")
        for title in ["Hunger", "Thirst", "Attention", "Coat"] {
            XCTAssertTrue(app.staticTexts[title].exists || card.staticTexts[title].exists, "the \(title) title is drawn on the card")
        }
    }

    /// Clean: the row runs him out of the room, the fade lands in the bath with the tool bar; the cancel button returns to the room.
    @MainActor
    func testCareMenuClean() throws {
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["care-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()
        let clean = app.buttons["care-clean"]
        XCTAssertTrue(clean.waitForExistence(timeout: 10), "the menu has a Clean row")
        XCTAssertTrue(clean.isEnabled)
        XCTAssertFalse(app.buttons["care-bath"].exists, "there is no separate Bath row")
        clean.tap()
        let cancel = app.buttons["bath-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 60), "the clean-up scene comes up with a cancel button")
        XCTAssertTrue(app.staticTexts["Jelly Soap"].exists, "the tool bar is up")
        XCTAssertFalse(menu.exists, "the care menu hides during the clean-up")
        cancel.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 60), "cancel returns to the room")
        XCTAssertFalse(cancel.exists)
    }

    // MARK: Voice v1

    private func voiceApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-VoiceFakeMic", "1", "-VoiceFakeText", "sit", "-VoiceReset", "1"] + extra
        app.launch()
        return app
    }

    private func waitValue(_ e: XCUIElement, contains: String, timeout: TimeInterval = 10, _ message: String) {
        let ex = expectation(for: NSPredicate(format: "value CONTAINS %@", contains), evaluatedWith: e)
        XCTAssertEqual(XCTWaiter().wait(for: [ex], timeout: timeout), .completed, message)
    }

    /// The mic exists; a 1.2 s hold opens listen mode (the edge glow was drawn) and the glow is gone after the release.
    @MainActor
    func testVoiceMicHoldShowsGlowThenHides() throws {
        let app = voiceApp()
        let mic = app.buttons["voice-mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 20), "the mic button is on the HUD")
        XCTAssertTrue(app.buttons["voice-tricks"].exists)
        XCTAssertFalse(app.otherElements["voice-glow"].exists, "no glow before a hold")
        mic.press(forDuration: 1.2)
        XCTAssertTrue(app.otherElements["voice-glow"].waitForNonExistence(timeout: 0.6), "the glow is gone right after the release (mic path)")
        waitValue(mic, contains: "1 talks", "one listen opened")
        waitValue(mic, contains: "1 glows", "the glow was drawn during the hold")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.otherElements["voice-glow"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "the glow is gone after the release")
    }

    /// The glow is drawn within a frame or so of the press (budget generous for the simulator) and the level feedback exists.
    @MainActor
    func testVoiceGlowAppearsQuicklyAfterPress() throws {
        let app = voiceApp(["-VoiceLog", "1"])
        let mic = app.buttons["voice-mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 20))
        mic.press(forDuration: 0.8)
        waitValue(mic, contains: "1 glows", "the glow was drawn")
        let v = mic.value as? String ?? ""
        let ms = Int(v.components(separatedBy: "glow ").last?.components(separatedBy: " ms").first ?? "") ?? 9999
        XCTAssertGreaterThanOrEqual(ms, 0)
        XCTAssertLessThan(ms, 100, "touch-down to glow visible: \(ms) ms (\(v))")
    }

    /// Double-tap-hold on EMPTY space: the glow is drawn on the second touch-down (not after the hold threshold), within the latency budget,
    /// and it is gone right after the finger lifts (no lingering fade).
    @MainActor
    func testVoiceDoubleTapHoldGlowIsInstantAndGoneOnRelease() throws {
        let app = voiceApp(["-VoiceLog", "1", "-BlobNoWander", "1"])
        let mic = app.buttons["voice-mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 20))
        let empty = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        empty.tap()
        empty.press(forDuration: 0.9)
        // after the release: no waiting for the transcript, the glow is already gone
        XCTAssertTrue(app.otherElements["voice-glow"].waitForNonExistence(timeout: 0.6), "the glow is gone right after the release")
        waitValue(mic, contains: "1 talks", "the gesture opened a listen")
        waitValue(mic, contains: "1 glows", "the glow was drawn during the hold")
        let v = mic.value as? String ?? ""
        let ms = Int(v.components(separatedBy: "glow ").last?.components(separatedBy: " ms").first ?? "") ?? 9999
        XCTAssertGreaterThanOrEqual(ms, 0)
        XCTAssertLessThan(ms, 100, "second tap-down to glow visible: \(ms) ms (\(v))")
    }

    /// A double-tap that does not hold (a quick second tap) cancels silently: no glow left behind, the listen is not sent.
    @MainActor
    func testVoiceQuickDoubleTapLeavesNoGlow() throws {
        let app = voiceApp(["-BlobNoWander", "1"])
        let mic = app.buttons["voice-mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 20))
        let empty = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        empty.tap(); empty.tap()
        XCTAssertTrue(app.otherElements["voice-glow"].waitForNonExistence(timeout: 0.6), "no glow after a quick double tap")
    }

    /// After a taught word the heard pill quotes it and Bob's understanding bubble shows the rep.
    @MainActor
    func testVoiceHeardPillAndRepBubbleAppear() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-VoiceFakeMic", "1", "-VoiceFakeText", "sit", "-VoiceReset", "1", "-VoiceSay", "sit", "-VoiceTeach", "sit", "-VoiceDelay", "1", "-BlobNoWander", "1"]
        app.launch()
        let heard = app.descendants(matching: .any)["voice-heard"]
        XCTAssertTrue(heard.waitForExistence(timeout: 30), "the heard pill shows")
        XCTAssertTrue((heard.value as? String ?? "").contains("sit"), "it quotes the words: \(heard.value ?? "nil")")
        let bubble = app.descendants(matching: .any)["voice-bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "Bob's bubble shows")
        XCTAssertTrue((bubble.value as? String ?? "").hasPrefix("rep sit"), "a rep: \(bubble.value ?? "nil")")
    }

    /// The trick book opens from its button; tapping a row has him do the trick and closes the sheet.
    @MainActor
    func testVoiceTrickBookOpensAndRowCloses() throws {
        let app = voiceApp()
        let book = app.buttons["voice-tricks"]
        XCTAssertTrue(book.waitForExistence(timeout: 20))
        book.tap()
        let sit = app.buttons["voice-trick-sit"]
        XCTAssertTrue(sit.waitForExistence(timeout: 10), "a row per trick")
        XCTAssertTrue(app.buttons["voice-trick-jacks"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["voice-name"].exists, "the name lesson row")
        sit.tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sit)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, "a row tap closes the book")
        XCTAssertTrue(app.buttons["voice-mic"].waitForExistence(timeout: 5))
    }

    /// The name row shows the name as known (no lesson) and a nickname can be typed in.
    @MainActor
    func testVoiceNameRowIsKnownAndTakesANickname() throws {
        let app = voiceApp()
        let book = app.buttons["voice-tricks"]
        XCTAssertTrue(book.waitForExistence(timeout: 20))
        book.tap()
        let name = app.descendants(matching: .any)["voice-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(name.label.contains("He knows it"), name.label)
        let field = app.textFields["voice-nickname-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("bubbles")
        app.buttons["voice-nickname-add"].firstMatch.tap()
        XCTAssertTrue(app.buttons["voice-nickname-bubbles"].firstMatch.waitForExistence(timeout: 5), "the nickname chip appears")
    }

    /// Trick book Flip row -> he just flips: no timing bar or any other meter appears, and the book closes.
    @MainActor
    func testFlipRowFlipsWithNoMeterOnScreen() throws {
        let app = voiceApp()
        let book = app.buttons["voice-tricks"]
        XCTAssertTrue(book.waitForExistence(timeout: 20))
        book.tap()
        let row = app.buttons["voice-trick-flip"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the Flip row")
        row.tap()
        XCTAssertTrue(app.buttons["voice-mic"].waitForExistence(timeout: 10), "the book closes and the game is back")
        let meter = app.descendants(matching: .any)["flip-meter"]
        XCTAssertFalse(meter.waitForExistence(timeout: 3), "no flip meter appears while he flips")
        XCTAssertFalse(app.descendants(matching: .any)["flip-hint"].exists)
    }

    /// A double-tap-hold ON Bob (he stands at the middle of the room when he does not wander) does not open listen mode.
    @MainActor
    func testVoiceDoubleTapHoldOnBobDoesNotListen() throws {
        let app = voiceApp(["-BlobNoWander", "1"])
        let mic = app.buttons["voice-mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 20))
        let bob = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bob.tap()
        bob.press(forDuration: 1.2)
        XCTAssertFalse(app.otherElements["voice-glow"].exists, "no glow when the gesture lands on Bob")
        XCTAssertTrue((mic.value as? String ?? "").contains("0 talks"), "listen mode never opened: \(mic.value ?? "nil")")
    }
}
