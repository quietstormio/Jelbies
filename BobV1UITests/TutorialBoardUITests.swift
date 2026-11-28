//
//  TutorialBoardUITests.swift
//  Real-app pictures of every card style (for the side-by-side board): the tip card, the message bar line, the Show's Pick a move, the How to play sheet, the first-hungry reminder. Into TUT_OUT.
//

import XCTest

final class TutorialBoardUITests: XCTestCase {
    private var out = ""
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = true; out = ProcessInfo.processInfo.environment["TUT_OUT"] ?? NSTemporaryDirectory() + "tut"; try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true) }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }
    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func centre(_ e: XCUIElement) -> XCUICoordinate { let f = e.frame; return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)) }
    private func shot(_ n: String) { try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out + "/\(n).png")) }
    private func cfg() -> (String, UIDeviceOrientation, [String]) {
        switch ProcessInfo.processInfo.environment["TUT_CONFIG"] ?? "portrait" {
        case "landscape": return ("landscape", .landscapeLeft, [])
        case "ax": return ("ax", .portrait, ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        case "ipad": return ("ipad", .portrait, [])
        default: return ("portrait", .portrait, [])
        }
    }
    private func launch(_ args: [String]) -> String {
        let (name, o, extra) = cfg()
        app = XCUIApplication(); XCUIDevice.shared.orientation = o
        app.launchArguments += ["-SkipIntro", "1", "-Mute", "1"] + args + extra
        app.launch()
        return name
    }

    func testTipCard() {
        let n = launch(["-NewGame", "bob", "-MainMenu", "0", "-ClockHour", "12", "-TipsReset", "1", "-TipShow", "feed", "-BlobNoWander", "1"])
        XCTAssertTrue(el("tip-feed").waitForExistence(timeout: 120)); shot("\(n)_tip")
    }

    func testHowToSheet() {
        let n = launch(["-SetRoster", "pip,moss,lavender", "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-LobbyAuto", "volley", "-BlobNoWander", "1", "-volley.partner", "99", "-LobbySeed", "reset dress"])
        XCTAssertTrue(el("volley-lobby").waitForExistence(timeout: 60)); sleep(6)
        centre(el("volley-help")).tap(); XCTAssertTrue(el("lobby-how").waitForExistence(timeout: 10)); shot("\(n)_howto")
    }

    func testPickAMove() {
        let n = launch(["-SetRoster", "pip,moss,lavender", "-MainMenu", "0", "-Intro", "0", "-BlobDrops.v1", "1024", "-BlobNoWander", "1", "-ClockHour", "12", "-ShowStart", "1", "-ShowAuto", "1", "-ShowRank", "puddle"])
        let end = Date().addingTimeInterval(240)
        while Date() < end, !el("trick-tutorial").exists { usleep(500_000) }
        XCTAssertTrue(el("trick-tutorial").exists, "Pick a move never showed"); shot("\(n)_pickamove")
    }

    func testMessageBarLine() {
        let n = launch(["-NewGame", "bob", "-MainMenu", "0", "-ClockHour", "12", "-TutorialAuto", "1", "-TutorialStep", "cuddle.tap", "-BlobNoWander", "1"])
        XCTAssertTrue(el("tutorial-skip").waitForExistence(timeout: 90)); sleep(3)
        centre(el("jelbie-0")).doubleTap(); XCTAssertTrue(el("hud-come").waitForExistence(timeout: 20)); sleep(1)
        centre(el("tutorial-skip")).tap(); sleep(2)
        centre(el("hud-come")).tap()
        XCTAssertTrue(el("focus-release").waitForExistence(timeout: 60))
        shot("\(n)_message_bar")          // (the line is on the bar for 3 s from the moment the close-up opens)
    }

    func testHungryReminder() {
        let n = launch(["-NewGame", "bob", "-MainMenu", "0", "-ClockHour", "12", "-NeedsLow", "1", "-BlobNoWander", "1", "-Jelbies.tutorial.state.v1", "done", "-Jelbies.firstDayTour.done.v1", "1"])
        let card = el("tutorial-card")
        XCTAssertTrue(card.waitForExistence(timeout: 120), "no hungry reminder"); sleep(1); shot("\(n)_hungry_1_heart")
        centre(el("care-menu")).tap()
        let end = Date().addingTimeInterval(20)
        while Date() < end, !(el("tutorial-card").exists && el("coach-text").exists && el("coach-text").label.hasPrefix("Tap Feed")) { usleep(400_000) }
        shot("\(n)_hungry_2_feed")
    }
}
