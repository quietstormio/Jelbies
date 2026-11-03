//
//  MainMenuLayoutUITests.swift
//  The title screen keeps ONE composition on every screen (the iPhone portrait design grown to fill the screen, centred): logo on top, Continue
//  then New Game stacked below, all centred, fully on screen, tap targets >= 44 pt. Run on iPhone or iPad; checks portrait and landscape.
//  Set MENU_SHOTS to a directory to also write a PNG per orientation (landscape PNGs from XCUIScreen come out rotated).
//

import XCTest

final class MainMenuLayoutUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

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
            let primary = save ? app.buttons["menu-continue"] : app.buttons["menu-start"]
            let logo = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Jelbies' AND elementType != %d", XCUIElement.ElementType.button.rawValue)).firstMatch
            XCTAssertTrue(primary.waitForExistence(timeout: 5))
            XCTAssertTrue(logo.exists, "the logo is an accessibility element")
            var frames = [("logo", logo.frame), ("primary", primary.frame)]
            if save { frames.append(("new", app.buttons["menu-new"].frame)) }
            for (n, f) in frames {
                // the logo's frame has transparent room above the mascot, which short-wide mode lets rise a little past the top edge
                let slack: CGFloat = (n == "logo" && win.width / win.height > 1.6) ? win.height * 0.08 : 1
                XCTAssertTrue(win.insetBy(dx: -1, dy: -slack).contains(f), "\(name) \(n) on screen: \(f) in \(win)")
                XCTAssertLessThan(abs(f.midX - win.midX), 3, "\(name) \(n) centred: \(f)")
            }
            // same order, stacked
            XCTAssertLessThan(logo.frame.minY, primary.frame.minY, "\(name): logo above the first button")
            if save { XCTAssertLessThan(primary.frame.maxY, app.buttons["menu-new"].frame.minY + 1, "\(name): Continue above New Game") }
            XCTAssertGreaterThanOrEqual(primary.frame.height, 44, "\(name) tap height")
            if save { XCTAssertGreaterThanOrEqual(app.buttons["menu-new"].frame.height, 44, "\(name) New Game tap height") }
            // the composition fills the screen: width fractions (portrait ~ the iPhone design, landscape limited by the height)
            let logoFrac = logo.frame.width / win.width, btnFrac = primary.frame.width / win.width
            let lastBottomShort = save ? app.buttons["menu-new"].frame.maxY : primary.frame.maxY
            if name == "portrait" {
                XCTAssertTrue((0.70...0.92).contains(logoFrac), "portrait logo is \(logoFrac) of the width")
                XCTAssertTrue((0.55...0.78).contains(btnFrac), "portrait buttons are \(btnFrac) of the width")
            } else {
                if win.width / win.height > 1.6 {          // a short, wide screen (iPhone landscape) spans most of the width
                    XCTAssertGreaterThanOrEqual(logoFrac, 0.34, "short landscape logo fraction \(logoFrac)")
                    XCTAssertLessThanOrEqual(lastBottomShort, win.height * 0.92 - 17 * 3.6 - 4 + 1, "buttons stay above the face's brows and eyes")
                    XCTAssertTrue((0.28...0.48).contains(btnFrac), "short landscape button fraction \(btnFrac)")
                }
                XCTAssertTrue((0.28...0.60).contains(logoFrac), "landscape logo is \(logoFrac) of the width")
                XCTAssertTrue((0.22...0.62).contains(btnFrac), "landscape buttons are \(btnFrac) of the width")
            }
            let lastBottom = save ? app.buttons["menu-new"].frame.maxY : primary.frame.maxY
            XCTAssertLessThanOrEqual(lastBottom, win.height * (win.width / win.height > 1.6 ? 0.80 : 0.80), "\(name): buttons leave room for the face")
            if name == "landscape" || win.height > 900 { XCTAssertGreaterThan(lastBottom, win.height * 0.45, "\(name): the stack uses the height") }
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
