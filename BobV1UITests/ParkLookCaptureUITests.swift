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
        let flow = ProcessInfo.processInfo.environment["PARK_LOOK_FLOW"] ?? "picker"          // picker: tap Play and look at the toy strip; play: `-StartParkPlay ball` (the player owns no toys under XCTest, whose store does not persist) then Done
        if flow == "play" { app.launchArguments += ["-StartParkPlay", "ball"] }
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
        let home = app.buttons["park-home"]
        let opened = home.waitForExistence(timeout: 90)
        if !opened { shot("FAILED_no_park") }
        XCTAssertTrue(opened, "the park never opened (no park-home button) in \(tag)")
        if flow == "roam" {
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
