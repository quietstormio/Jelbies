//
//  ContactCaptureUITests.swift
//  Not a regression test: BEFORE / AFTER captures of the touching emotes in the REAL app (the contact fix). ONE scene per run, driven by env
//  (scripts/contact_capture.sh reads scripts/contact_scenes.tsv and sets them): CAPTURE_OUT (TEST_RUNNER_CAPTURE_OUT) = folder, CAPTURE_NAME, CAPTURE_CAST
//  ("teddy,pearl"), CAPTURE_KIND (a SocialKind raw value | lieDown | sleepPile | - for none), CAPTURE_ANGLE (low | side), CAPTURE_ARGS (extra launch
//  arguments, space separated), CAPTURE_SECS (default 18). The app is launched with -NewGame <cast> -ContactDemo <kind> -ContactCam <angle>
//  (Melon/ContactDemo.swift) and screenshots are written to <out>/<name>_<angle>/f_<ms>.png as fast as the simulator gives them.
//  Works on any branch that has ContactDemo.swift (merge g-contactcap into it). Release + ENABLE_TESTABILITY=YES like the other app captures.
//

import XCTest

final class ContactCaptureUITests: XCTestCase {
    func testScene() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["CAPTURE_OUT"], !out.isEmpty, let name = env["CAPTURE_NAME"], let cast = env["CAPTURE_CAST"] else { throw XCTSkip("CAPTURE_OUT / CAPTURE_NAME / CAPTURE_CAST not set") }
        let kind = env["CAPTURE_KIND"] ?? "-", angle = env["CAPTURE_ANGLE"] ?? "low"
        let scene = name + "_" + angle
        let dir = out + "/" + scene
        try? FileManager.default.removeItem(atPath: dir)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let secs = env["CAPTURE_SECS"].flatMap(Double.init) ?? 18
        let app = XCUIApplication()
        app.launchArguments += ["-NewGame", cast, "-NewGameCoins", "10000", "-MainMenu", "0", "-RoomWide", "0", "-ContactCam", angle]
        if kind != "-" { app.launchArguments += ["-ContactDemo", kind, "-ContactDemoDelay", "3"] }
        if let extra = env["CAPTURE_ARGS"], !extra.isEmpty { app.launchArguments += extra.split(separator: " ").map(String.init) }
        app.launchEnvironment["CONTACTDEMO_LOG"] = out + "/" + scene + ".demolog"
        app.launch()
        let cont = app.buttons["Continue"]
        if cont.waitForExistence(timeout: 20) { for _ in 0..<6 { if cont.exists, cont.isHittable { cont.tap() }; Thread.sleep(forTimeInterval: 1.5) } }
        XCTAssertTrue(app.buttons["care-menu"].waitForExistence(timeout: 90), "the room is up")
        Thread.sleep(forTimeInterval: 1)
        try? "go".write(toFile: out + "/" + scene + ".mark", atomically: true, encoding: .utf8)          // (the host script starts its video here)
        let t0 = Date()
        var n = 0
        while Date().timeIntervalSince(t0) < secs {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: URL(fileURLWithPath: String(format: "%@/f_%06d.png", dir, ms)))
            n += 1
        }
        XCTAssertGreaterThan(n, 5, "frames were captured")
        app.terminate()
    }
}
