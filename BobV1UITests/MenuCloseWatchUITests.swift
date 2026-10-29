//
//  MenuCloseWatchUITests.swift
//  Not a regression test: drives the care menu through open / close-by-heart / close-by-outside-tap / close-by-row-tap while the host records the
//  simulator screen (xcrun simctl io <udid> recordVideo). Env-gated: MENUCLOSE_ORIENT (TEST_RUNNER_MENUCLOSE_ORIENT) = portrait | landscape;
//  MENUCLOSE_ROW = the row to tap in the last cycle (default hud-decor); MENUCLOSE_MARK = a file written when the sequence starts (MARK.done when it ends: the host stops the recording there).
//  Pass -HUDHighlight n in the launch arguments of the run to watch the individual menu (otherwise the group menu).
//

import XCTest

final class MenuCloseWatchUITests: XCTestCase {
    func testWatchMenuClose() throws {
        let env = ProcessInfo.processInfo.environment
        guard let orient = env["MENUCLOSE_ORIENT"] else { throw XCTSkip("MENUCLOSE_ORIENT not set") }
        let app = XCUIApplication()
        app.launchArguments += ["-SetRoster", "pip,moss,lavender"]
        if let extra = env["MENUCLOSE_ARGS"], !extra.isEmpty { app.launchArguments += extra.split(separator: " ").map(String.init) }
        app.launch()
        let cont = app.buttons["Continue"]
        if cont.waitForExistence(timeout: 60) {
            for _ in 0..<6 where cont.exists { Thread.sleep(forTimeInterval: 2); cont.tap(); Thread.sleep(forTimeInterval: 1.5) }
        }
        XCUIDevice.shared.orientation = orient == "landscape" ? .landscapeLeft : .portrait
        let menu = app.buttons["care-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 90), "the HUD is up")
        Thread.sleep(forTimeInterval: 8)
        if let mark = env["MENUCLOSE_MARK"] { try? "up".write(toFile: mark, atomically: true, encoding: .utf8) }
        func wait(_ s: Double = 3) { Thread.sleep(forTimeInterval: s) }
        func mark(_ what: String) {          // host clock of each tap, to line the recording up with (MARK.events)
            guard let m = env["MENUCLOSE_MARK"], let h = FileHandle(forWritingAtPath: m + ".events") ?? { FileManager.default.createFile(atPath: m + ".events", contents: nil); return FileHandle(forWritingAtPath: m + ".events") }() else { return }
            h.seekToEndOfFile(); h.write("\(what) \(Date().timeIntervalSince1970)\n".data(using: .utf8)!); try? h.close()
        }
        // 1: open, close with the heart
        mark("open1"); menu.tap(); wait(); mark("close_heart"); menu.tap(); wait()
        // 2: open, close by tapping outside (the scrim)
        mark("open2"); menu.tap(); wait(); mark("close_scrim"); app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.2)).tap(); wait()
        // 3: open, close by tapping a row
        mark("open3"); menu.tap(); wait()
        let row = app.buttons[env["MENUCLOSE_ROW"] ?? "hud-decor"]
        if row.waitForExistence(timeout: 3) { mark("close_row"); row.tap() }
        wait(4)
        if let mark = env["MENUCLOSE_MARK"] { try? "done".write(toFile: mark + ".done", atomically: true, encoding: .utf8) }
        wait(3)
    }
}
