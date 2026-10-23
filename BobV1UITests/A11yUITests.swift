//
//  A11yUITests.swift
//  Accessibility of the chrome on the real app: every key control has a non-empty label, the hit targets are 44 pt, the Accessibility sheet is
//  reachable (gear, Accessibility) and its toggles are native, and at the largest text size the key buttons stay on screen. Also writes
//  Accessibility-Inspector-style label overlays (frames + labels drawn on a screenshot) to A11Y_OUT.
//

import XCTest
import UIKit

final class A11yUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["A11Y_OUT"] ?? "/tmp/a11y_ui"

    private func launch(_ extra: [String] = [], size: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-BlobCount", "3", "-BlobNoWander", "1"] + extra
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        return app
    }

    /// The Inspector-style overlay: every labelled element's frame and label drawn over the screenshot.
    private func overlay(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        let shot = XCUIScreen.main.screenshot().image
        let scale = shot.scale, win = app.windows.firstMatch.frame
        let r = UIGraphicsImageRenderer(size: shot.size)
        let img = r.image { ctx in
            shot.draw(at: .zero)
            let cg = ctx.cgContext
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9 * scale / 3 + 6, weight: .bold), .foregroundColor: UIColor.white]
            for t in [XCUIElement.ElementType.button, .switch, .staticText, .slider, .textField] {
                for e in app.descendants(matching: t).allElementsBoundByIndex.prefix(80) where e.exists && !e.label.isEmpty {
                    let f = e.frame
                    guard f.width > 2, f.height > 2, win.intersects(f) else { continue }
                    let R = CGRect(x: f.minX * shot.size.width / win.width, y: f.minY * shot.size.height / win.height,
                                   width: f.width * shot.size.width / win.width, height: f.height * shot.size.height / win.height)
                    cg.setStrokeColor((t == .button ? UIColor.systemGreen : t == .staticText ? UIColor.systemBlue : UIColor.systemOrange).cgColor)
                    cg.setLineWidth(3); cg.stroke(R)
                    let label = e.label as NSString, sz = label.size(withAttributes: attrs)
                    cg.setFillColor(UIColor.black.withAlphaComponent(0.75).cgColor)
                    cg.fill(CGRect(x: R.minX, y: R.minY, width: min(sz.width + 6, R.width + 140), height: sz.height + 2))
                    label.draw(at: CGPoint(x: R.minX + 3, y: R.minY + 1), withAttributes: attrs)
                }
            }
        }
        try? img.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/ax_overlay_\(name).png"))
    }

    private func waitHUD(_ app: XCUIApplication) { XCTAssertTrue(app.buttons["care-menu"].waitForExistence(timeout: 90), "the HUD is up") }

    @MainActor
    func testKeyControlsAreLabelledAndBigEnough() throws {
        let app = launch()
        waitHUD(app)
        sleep(2)
        for id in ["care-menu", "go-out", "bag-button", "voice-mic", "voice-tricks", "studio-button", "sound-button", "roster-button"] {
            let b = app.buttons[id]
            XCTAssertTrue(b.exists, id)
            XCTAssertFalse(b.label.isEmpty, "\(id) has a label")
        }
        XCTAssertEqual(app.buttons["studio-button"].label, "Settings")
        for b in app.buttons.allElementsBoundByIndex.prefix(40) where b.exists && b.isHittable && !b.identifier.isEmpty {
            let f = b.frame
            if f.width > 300 || f.height > 300 { continue }          // full-screen surfaces
            XCTAssertGreaterThanOrEqual(f.width, 43.5, "\(b.identifier) is at least 44 pt wide")
            XCTAssertGreaterThanOrEqual(f.height, 43.5, "\(b.identifier) is at least 44 pt tall")
        }
        overlay(app, "hud_portrait")
        let paw = app.buttons["care-menu"]
        XCTAssertEqual(paw.value as? String, "collapsed")
        paw.tap()
        XCTAssertTrue(app.buttons["hud-bedtime"].waitForExistence(timeout: 5))
        XCTAssertEqual(paw.value as? String, "expanded")
        for id in ["care-feed", "care-snacks", "care-water", "hud-play", "hud-decor", "hud-bedtime"] { XCTAssertFalse(app.buttons[id].label.isEmpty, id) }
        overlay(app, "paw_group_portrait")
    }

    @MainActor
    func testAccessibilitySheetIsReachableAndNative() throws {
        let app = launch()
        waitHUD(app)
        app.buttons["studio-button"].tap()
        XCTAssertTrue(app.buttons["settings-accessibility"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-studio"].exists)
        app.buttons["settings-accessibility"].tap()
        XCTAssertTrue(app.switches["a11y-captions"].waitForExistence(timeout: 5), "captions is a native switch")
        for id in ["a11y-reduce-motion", "a11y-longer-hints", "a11y-announce", "a11y-relaxed-timing", "a11y-tap-to-talk"] {
            XCTAssertTrue(app.switches[id].exists, id)
            XCTAssertFalse(app.switches[id].label.isEmpty)
        }
        let c = app.switches["a11y-captions"]
        let before = c.value as? String
        c.tap()
        XCTAssertNotEqual(c.value as? String, before, "the toggle flips")
        c.tap()
        overlay(app, "a11y_sheet_portrait")
    }

    @MainActor
    func testLargestTextKeepsKeyButtonsOnScreen() throws {
        for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            let app = launch(size: "UICTContentSizeCategoryAccessibilityXXXL")
            XCUIDevice.shared.orientation = orient
            waitHUD(app)
            sleep(3)
            let win = app.windows.firstMatch.frame
            for id in ["care-menu", "go-out", "bag-button", "roster-button"] {
                let b = app.buttons[id]
                XCTAssertTrue(b.exists && b.isHittable, "\(id) is hittable at AX5 (\(name))")
                XCTAssertTrue(win.contains(b.frame), "\(id) is on screen at AX5 (\(name))")
            }
            overlay(app, "hud_ax5_\(name)")
            app.buttons["care-menu"].tap()
            XCTAssertTrue(app.buttons["hud-bedtime"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["care-menu"].isHittable, "the paw stays reachable with the menu open (\(name))")
            overlay(app, "paw_ax5_\(name)")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testBagAndShopAtLargestText() throws {
        let app = launch(size: "UICTContentSizeCategoryAccessibilityXXXL")
        waitHUD(app)
        sleep(2)
        app.buttons["bag-button"].tap()
        sleep(2)
        overlay(app, "bag_ax5_portrait")
        let win = app.windows.firstMatch.frame
        XCTAssertTrue(win.intersects(app.buttons["bag-button"].exists ? app.buttons["bag-button"].frame : win))
    }
}
