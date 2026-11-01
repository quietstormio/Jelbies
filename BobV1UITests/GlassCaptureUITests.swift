//
//  GlassCaptureUITests.swift
//  Before / after captures of the HUD with Liquid Glass (-NoMaterials 0) and the opaque HUD (-NoMaterials 1): room, roster panel, focus, shop.
//  Screenshots go to GLASS_OUT (default the gpuframe scratchpad).
//

import XCTest
import UIKit

final class GlassCaptureUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["GLASS_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gpuframe/hud"

    private func save(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(name).png"))
    }

    @MainActor
    func testCaptureHUDBothWays() throws {
        for (mode, tag) in [("0", "glass"), ("1", "opaque")] {
            let app = XCUIApplication()
            app.launchArguments += ["-Mute", "1", "-SetRoster", "pip,moss,lavender", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-BlobNoWander", "1", "-NoMaterials", mode]
            app.launch()
            XCUIDevice.shared.orientation = .portrait
            sleep(12)
            save("\(tag)_1_room")
            let roster = app.descendants(matching: .any)["roster-button"]
            if roster.waitForExistence(timeout: 5) { roster.tap(); sleep(3); save("\(tag)_2_roster"); roster.tap(); sleep(1) }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.6)).tap()          // a Jelbie: the focus close-up
            sleep(4)
            save("\(tag)_3_focus")
            if app.buttons["care-menu"].exists { app.buttons["care-menu"].tap(); sleep(2); save("\(tag)_4_menu"); app.buttons["care-menu"].tap() }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap(); sleep(2)
            if app.buttons["go-out"].waitForExistence(timeout: 5) {
                app.buttons["go-out"].tap()
                if app.buttons["town-shop"].waitForExistence(timeout: 8) { save("\(tag)_5_town"); app.buttons["town-shop"].tap(); sleep(3); save("\(tag)_6_shop") }
            }
            app.terminate()
        }
    }
}
