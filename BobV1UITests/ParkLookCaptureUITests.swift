//
//  ParkLookCaptureUITests.swift
//  Capture aid, not a regression test: launches the REAL app straight into the Park (`-StartPark 1`) and saves portrait screenshots to PARK_LOOK_OUT
//  (TEST_RUNNER_PARK_LOOK_OUT) for the trees / bushes / flower patches look. Skips without it.
//

import XCTest

final class ParkLookCaptureUITests: XCTestCase {
    private var out: String { ProcessInfo.processInfo.environment["PARK_LOOK_OUT"] ?? "" }

    @MainActor
    func testParkShots() throws {
        try XCTSkipIf(out.isEmpty, "PARK_LOOK_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES",
                                "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12", "-StartPark", "1"]
        app.launch()
        for k in 0..<8 {
            sleep(4)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/park_\(k + 1).png"))
        }
        app.terminate()
    }

    /// The merged-branch capture: launches the app (`-StartPark 1`), rotates (`PARK_LOOK_ORIENT=portrait|landscape`, default landscape), WAITS for the park's Go home button (`park-home`) and FAILS
    /// if it does not appear in 90 s, then saves <tag>_roam, taps the round Play button (`park-play`) and saves <tag>_picker, taps the first toy (`play-toy-*`) and saves <tag>_play after 4 s, taps
    /// Done (`play-done`) and saves <tag>_after; <tag>_frames.txt lists the frames and hit-ability of the HUD buttons at each step. Meant for a RELEASE build of the app (the Debug build runs at
    /// about 1 frame/s in the simulator, so the `-StartPark` hook, 90 frames, takes minutes).
    @MainActor
    func testParkLandscape() throws {
        try XCTSkipIf(out.isEmpty, "PARK_LOOK_OUT not set")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let portrait = ProcessInfo.processInfo.environment["PARK_LOOK_ORIENT"] == "portrait"
        XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
        let tag = (ProcessInfo.processInfo.environment["PARK_LOOK_TAG"] ?? "") + (portrait ? "port" : "land")
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "bob,pearl,teddy", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES",
                                "-BlobDrops.v1", "1024", "-ClockHour", ProcessInfo.processInfo.environment["PARK_LOOK_HOUR"] ?? "12", "-StartPark", "1"]
        if let r = ProcessInfo.processInfo.environment["PARK_LOOK_ROSTER"], let i = app.launchArguments.firstIndex(of: "-SetRoster") { app.launchArguments[i + 1] = r }          // (e.g. bob,teddy)
        if let extra = ProcessInfo.processInfo.environment["PARK_LOOK_ARGS"] { app.launchArguments += extra.split(separator: " ").map(String.init) }          // (extra launch arguments, space separated)
        let flow = ProcessInfo.processInfo.environment["PARK_LOOK_FLOW"] ?? "picker"          // picker: tap Play and look at the toy strip; play: `-StartParkPlay ball` (the player owns no toys under XCTest, whose store does not persist) then Done
        if flow == "toytap" { app.launchArguments.removeLast(2) }          // (no -StartPark: this flow walks the real UI)
        if flow == "play" || flow == "flick" { app.launchArguments += ["-StartParkPlay", "ball"] }
        if flow == "slide" { app.launchArguments += ["-StartSlide", "1"] }          // (the simulator's own aid: a Jelbie rides the slide ~4 s into the park)
        app.launch()
        var frames = ""
        func shot(_ name: String) { try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(out)/\(tag)_\(name).png")) }          // (a flow tag is part of `name` where it matters)
        func note(_ step: String) {
            frames += "[\(step)] window=\(app.windows.firstMatch.frame)\n"
            for id in ["park-home", "park-play", "play-done", "park-chip", "park-sound-button"] {
                let e = app.buttons[id]
                frames += "  \(id): exists=\(e.exists) hittable=\(e.exists && e.isHittable) frame=\(e.exists ? "\(e.frame)" : "-")\n"
            }
        }
        if let w = ProcessInfo.processInfo.environment["PARK_LOOK_PREWAIT"].flatMap(Double.init) { sleep(UInt32(w)) }          // (a busy host: do not query the app while it loads the park, its main thread answers no snapshot within 30 s)
        let home = app.buttons["park-home"]
        let opened = flow == "toytap" ? true : home.waitForExistence(timeout: 300)
        if !opened { shot("FAILED_no_park") }
        XCTAssertTrue(opened, "the park never opened (no park-home button) in \(tag)")
        if flow == "slide" {
            for k in 0..<14 { sleep(2); shot("slide_\(String(format: "%02d", k))") }
        } else if flow == "flick" {
            sleep(8); shot("flick_00")
            // a hard flick straight toward the camera (the park's entrance hedge is at the bottom of the screen): from the lower half, fast, downward
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.62)), to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.97))
            from.press(forDuration: 0.02, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
            for k in 1...12 { shot("flick_\(String(format: "%02d", k))") }
            sleep(3); shot("flick_end")
        } else if flow == "toytap" {
            // buy the first toy in the shop (the player owns none under XCTest), then go to the park and play it from the picker
            app.buttons["go-out"].tap()
            if app.buttons["town-shop"].waitForExistence(timeout: 10) { app.buttons["town-shop"].tap() }
            let tab = app.buttons["shop-tab-toys"]
            _ = tab.waitForExistence(timeout: 8)
            let strip = app.buttons["shop-tab-food"].exists ? app.buttons["shop-tab-food"] : app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shop-tab-'")).firstMatch
            for _ in 0..<3 { if strip.exists { strip.swipeLeft(velocity: .fast) } }          // (the tab strip scrolls sideways; its later tabs start off screen)
            sleep(1)
            if tab.exists { tab.tap() }
            sleep(2); shot("toytap_1_shop")
            let items = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shop-item-'"))
            _ = items.firstMatch.waitForExistence(timeout: 5)
            for i in 0..<items.count where items.element(boundBy: i).isHittable { items.element(boundBy: i).tap(); sleep(2); break }          // (the first one ON screen: the list scrolls sideways)
            let buy = app.buttons["item-buy"].exists ? app.buttons["item-buy"] : app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Buy '")).firstMatch
            if buy.waitForExistence(timeout: 5) { buy.tap(); sleep(2); shot("toytap_2_bought") }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            sleep(1)
            if app.buttons["shop-back"].waitForExistence(timeout: 3) { app.buttons["shop-back"].tap(); sleep(1) }
            if app.buttons["town-park"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["town-park"].waitForExistence(timeout: 5) { app.descendants(matching: .any)["town-park"].firstMatch.tap() }
            let go = app.buttons["park-go"]; if go.waitForExistence(timeout: 10) { go.tap() }
            XCTAssertTrue(app.buttons["park-play"].waitForExistence(timeout: 90), "park did not open after the shop")
            sleep(3); app.buttons["park-play"].tap(); sleep(2); shot("toytap_3_picker"); note("toytap_picker")
            let toy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play-toy-'")).firstMatch
            if toy.waitForExistence(timeout: 5) { toy.tap(); sleep(5); shot("toytap_4_playing"); note("toytap_playing") } else { frames += "no play-toy-* after buying\n" }
        } else if flow == "roam" {
            sleep(6); shot("roam"); note("roam")          // (just the roaming view: used for the dusk picture with PARK_LOOK_HOUR=19)
        } else if flow == "play" {
            sleep(10); shot("play"); note("play")
            let done = app.buttons["play-done"]
            if done.waitForExistence(timeout: 10) { done.tap(); sleep(3); shot("after"); note("after") } else { frames += "no play-done button (play did not start)\n" }
        } else {
            sleep(5); shot("roam"); note("roam")
            let play = app.buttons["park-play"]
            XCTAssertTrue(play.waitForExistence(timeout: 5), "no Play button in the park (\(tag))")
            play.tap(); sleep(2); shot("picker"); note("picker")
            let toy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play-toy-'")).firstMatch
            if toy.waitForExistence(timeout: 3) { toy.tap(); sleep(4); shot("play_from_picker"); note("play_from_picker") } else { frames += "no play-toy-* button after tapping Play (no toys owned)\n" }
        }
        try? frames.write(toFile: "\(out)/\(tag)_\(flow)_frames.txt", atomically: true, encoding: .utf8)
        app.terminate()
    }
}
