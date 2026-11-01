//
//  RosterCaptureUITests.swift
//  Captures the "Your Jelbies" panel in portrait and landscape with boosts seeded (-StoreSeed 2: Pip two, Moss one, Lavender none).
//  Screenshots go to ROSTER_OUT / <ROSTER_TAG>_portrait|landscape.png.
//

import XCTest

final class RosterCaptureUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["ROSTER_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/roster"
    static let tag = ProcessInfo.processInfo.environment["ROSTER_TAG"] ?? "after"

    @MainActor
    func testCaptureRosterPanel() throws {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        for (orient, name) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            let app = XCUIApplication()
            app.launchArguments += ["-Mute", "1", "-SetRoster", "pip,moss,lavender", "-MainMenu", "0", "-Intro", "0", "-Jelbies.started.v1", "YES", "-BlobDrops.v1", "300", "-BlobNoWander", "1", "-StoreSeed", "2"]
            app.launch()
            XCUIDevice.shared.orientation = orient
            sleep(10)
            let roster = app.descendants(matching: .any)["roster-button"]
            XCTAssertTrue(roster.waitForExistence(timeout: 10))
            roster.tap(); sleep(3)
            try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(Self.tag)_\(name).png"))
            if name == "portrait" { for id in 0..<3 { print("ROSTER LABEL", app.buttons["roster-card-\(id)"].label) } }
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
