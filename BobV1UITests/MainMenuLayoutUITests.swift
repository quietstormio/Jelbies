//
//  MainMenuLayoutUITests.swift
//  The title screen keeps ONE composition on every screen (the iPhone portrait design scaled by min(w/440, h/956), centred): logo on top, Continue
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
        var portraitNorm: [String: CGFloat] = [:]          // frame values / scale, from the first orientation
        for (name, o) in [("portrait", UIDeviceOrientation.portrait), ("landscape", .landscapeLeft)] {
            XCUIDevice.shared.orientation = o
            sleep(4)
            let win = app.windows.firstMatch.frame
            XCTAssertEqual(win.width > win.height, name == "landscape", "window is \(name): \(win)")
            let s = max(min(win.width / 440, win.height / 956), 0.72)
            let primary = save ? app.buttons["menu-continue"] : app.buttons["menu-start"]
            let logo = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Jelbies' AND elementType != %d", XCUIElement.ElementType.button.rawValue)).firstMatch
            XCTAssertTrue(primary.waitForExistence(timeout: 5))
            XCTAssertTrue(logo.exists, "the logo is an accessibility element")
            var frames = [("logo", logo.frame), ("primary", primary.frame)]
            if save { frames.append(("new", app.buttons["menu-new"].frame)) }
            for (n, f) in frames {
                XCTAssertTrue(win.insetBy(dx: -1, dy: -1).contains(f), "\(name) \(n) on screen: \(f) in \(win)")
                XCTAssertLessThan(abs(f.midX - win.midX), 3, "\(name) \(n) centred: \(f)")
            }
            // same order, stacked
            XCTAssertLessThan(logo.frame.minY, primary.frame.minY, "\(name): logo above the first button")
            if save { XCTAssertLessThan(primary.frame.maxY, app.buttons["menu-new"].frame.minY + 1, "\(name): Continue above New Game") }
            XCTAssertGreaterThanOrEqual(primary.frame.height, 44, "\(name) tap height")
            if save { XCTAssertGreaterThanOrEqual(app.buttons["menu-new"].frame.height, 44, "\(name) New Game tap height") }
            XCTAssertEqual(primary.frame.width, 300 * s, accuracy: 3, "\(name) button width is the portrait 300 x scale")
            // same proportions: positions / scale match across orientations unless the short screen tightened the spacing (scale floor)
            let squeezed = win.height / 956 < 0.72 || win.width / 440 < 0.72
            let norm = ["primaryTop": primary.frame.minY / s, "logoW": logo.frame.width / s]
            if name == "portrait" { portraitNorm = norm }
            else if !squeezed {
                for (k, v) in norm { XCTAssertEqual(v, portraitNorm[k] ?? v, accuracy: 6, "\(k) in landscape matches portrait") }
            }
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
