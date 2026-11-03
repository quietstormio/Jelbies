//
//  MainMenuLayoutUITests.swift
//  The title screen in portrait and landscape on whatever device the test runs on (iPhone or iPad): the logo, Continue and New Game are fully
//  on screen, and the buttons sit clear of the peeking face (the face's top is the design formula: eyes ~9% above the bottom edge).
//  Set MENU_SHOTS to a directory to also write a PNG per orientation.
//

import XCTest

final class MainMenuLayoutUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func faceTop(_ w: CGFloat, _ h: CGFloat) -> CGFloat {
        let portraitS = min(w / 440, h / 956)
        let sc = w > h ? min(h, 430) * 0.0072 : 4.8 * portraitS
        return 0.91 * h + 14 * sc - 65.5 * sc
    }

    private func check(save: Bool, shotDir: String?) {
        let app = XCUIApplication()
        app.launchArguments += save ? ["-Jelbies.started.v1", "YES"] : ["-ResetForAdoption", "1"]
        app.launch()
        XCTAssertTrue(app.otherElements["main-menu"].waitForExistence(timeout: 90), "menu shows after the intro")
        for (name, o) in [("portrait", UIDeviceOrientation.portrait), ("landscape", .landscapeLeft)] {
            XCUIDevice.shared.orientation = o
            sleep(4)
            let win = app.windows.firstMatch.frame
            XCTAssertEqual(win.width > win.height, name == "landscape", "window is \(name): \(win)")
            let top = faceTop(win.width, win.height)
            let primary = save ? app.buttons["menu-continue"] : app.buttons["menu-start"]
            let logo = app.staticTexts["Jelbies"].exists ? app.staticTexts["Jelbies"] : app.images["Jelbies"]
            XCTAssertTrue(primary.waitForExistence(timeout: 5))
            var frames = [("primary", primary.frame)]
            if save { frames.append(("new", app.buttons["menu-new"].frame)) }
            if logo.exists { frames.append(("logo", logo.frame)) }
            for (n, f) in frames {
                XCTAssertTrue(win.insetBy(dx: -1, dy: -1).contains(f), "\(name) \(n) on screen: \(f) in \(win)")
                if f.midX > win.width * 0.3 && f.midX < win.width * 0.7 || name == "portrait" {
                    XCTAssertLessThanOrEqual(f.maxY, top + 1, "\(name) \(n) clear of the face (top \(top)): \(f)")
                }
            }
            XCTAssertLessThan(abs(primary.frame.midX - win.midX), win.width * 0.3, "\(name) buttons centred-ish")
            if name == "portrait" { XCTAssertLessThan(abs(primary.frame.midX - win.midX), 2) }
            XCTAssertLessThanOrEqual(primary.frame.width, 480, "buttons capped on wide screens")
            if let dir = shotDir {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(save ? "continue" : "first")_\(name).png"))
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor func testMenuWithSave() { check(save: true, shotDir: ProcessInfo.processInfo.environment["MENU_SHOTS"]) }
    @MainActor func testMenuFirstLaunch() { check(save: false, shotDir: ProcessInfo.processInfo.environment["MENU_SHOTS"]) }
}
