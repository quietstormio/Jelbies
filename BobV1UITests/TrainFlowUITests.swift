//
//  TrainFlowUITests.swift
//  The Train card walkthrough with the fake mic (r1023-train): roster -> paw -> Train -> chip -> pips 1/3, 2/3, 3/3 -> learned -> Try it -> done, then the room
//  command. Portrait and landscape; a screenshot per step goes to $TRAIN_OUT (default /tmp/train_flow). Picks the Jelbie through the roster (a tap on a
//  roaming Jelbie is flaky).
//

import XCTest
import UIKit

final class TrainFlowUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["TRAIN_OUT"] ?? "/tmp/train_flow"

    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }
    private func launch(_ extra: [String], orient: UIDeviceOrientation) -> XCUIApplication {
        XCUIDevice.shared.orientation = orient
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "pip,moss,lavender", "-VoiceFakeMic", "1", "-NeedsHappy", "1", "-VoiceTipSeen", "1", "-ClockHour", "17"] + extra
        app.launch()
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func step(_ app: XCUIApplication) -> String { (el(app, "train-card").value as? String) ?? "-" }
    private func waitStep(_ app: XCUIApplication, _ s: String, _ t: TimeInterval = 40) -> Bool {
        let end = Date().addingTimeInterval(t)
        while Date() < end { if step(app) == s { return true }; usleep(200_000) }
        return false
    }
    private func pips(_ app: XCUIApplication) -> String { (el(app, "train-pips").value as? String) ?? "-" }

    @MainActor func testTrainFlowPortrait() throws { try flow(.portrait, "P") }
    @MainActor func testTrainFlowLandscape() throws { try flow(.landscapeLeft, "L") }

    @MainActor
    private func flow(_ o: UIDeviceOrientation, _ tag: String) throws {
        // `-TrainJelly 1` = what paw -> Train does for slot 1 (Moss), a few seconds after launch (the menu route is covered by the HUD tests)
        var app = launch(["-VoiceReset", "1", "-VoiceFakeSeq", "sit|sit|sit|sit", "-TrainJelly", "1"], orient: o)
        XCTAssertTrue(app.buttons["voice-mic"].waitForExistence(timeout: 240))
        XCTAssertTrue(el(app, "train-card").waitForExistence(timeout: 300), "the Train card appears on arrival")
        XCTAssertTrue(waitStep(app, "pick"))
        save("\(tag)_01_pick")

        let chip = app.buttons["train-chip-sit"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5)); chip.tap()
        usleep(400_000); save("\(tag)_02_demo")
        for i in 1...3 {
            XCTAssertTrue(waitStep(app, "listen"), "rep \(i): say-it-now step")
            usleep(600_000); save("\(tag)_03_say_now_\(i)")
            XCTAssertTrue(waitStep(app, "heard", 20) || waitStep(app, "learned", 5), "rep \(i): the fake mic heard it")
            if i < 3 { XCTAssertEqual(pips(app), "\(i)/3"); save("\(tag)_04_pips_\(i)") }
        }
        XCTAssertTrue(waitStep(app, "learned", 10)); XCTAssertTrue(el(app, "train-learned").exists)
        XCTAssertEqual(pips(app), "3/3")
        save("\(tag)_05_learned")
        XCTAssertTrue(waitStep(app, "tryIt", 20)); usleep(600_000); save("\(tag)_06_tryit")
        XCTAssertTrue(waitStep(app, "tried", 20)); XCTAssertTrue(el(app, "train-tryit-ok").exists)
        save("\(tag)_07_tried")
        app.buttons["train-done"].tap()
        sleep(3)
        app.terminate()

        // relaunch without a reset: Pip still knows sit; a plain "sit" in the room reaches him
        app = launch(["-VoiceFakeText", "sit"], orient: o)
        XCTAssertTrue(app.buttons["care-menu"].waitForExistence(timeout: 240)); sleep(3)
        app.buttons["voice-mic"].press(forDuration: 1.2)
        sleep(2); save("\(tag)_08_room")
        app.terminate()
    }
}
