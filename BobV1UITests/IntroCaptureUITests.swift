//
//  IntroCaptureUITests.swift
//  Captures the launch intro at: Skip pill visible, video mid-play, final frame (held), mid-fade, menu; and a rotation during playback.
//  Needs a simulator (-IntroHold / -IntroFade stretch the hold and the fade so a screenshot can land in them).
//  Files go to INTRO_OUT / <INTRO_DEVICE>_<orientation>_<moment>.png.
//

import XCTest

final class IntroCaptureUITests: XCTestCase {
    static let out = ProcessInfo.processInfo.environment["INTRO_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/introfull"
    static let device = ProcessInfo.processInfo.environment["INTRO_DEVICE"] ?? "device"

    private func shot(_ name: String) {
        try? FileManager.default.createDirectory(atPath: Self.out, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(to: URL(fileURLWithPath: "\(Self.out)/\(Self.device)_\(name).png"))
    }

    private func run(_ orient: UIDeviceOrientation, _ tag: String, rotateTo: UIDeviceOrientation? = nil) {
        XCUIDevice.shared.orientation = orient
        sleep(1)
        let app = XCUIApplication()
        app.launchArguments += ["-Mute", "1", "-IntroHold", "5", "-IntroFade", "8"]
        app.launch()
        let t0 = Date()
        func at(_ s: Double, _ name: String) { let d = s - Date().timeIntervalSince(t0); if d > 0 { usleep(UInt32(d * 1e6)) }; shot("\(tag)_\(name)") }
        if let r = rotateTo {
            at(2.5, "rot0_before")
            XCUIDevice.shared.orientation = r
            at(3.6, "rot1_just_after"); at(5.0, "rot2_later")
        } else {
            at(2.0, "skipvisible_early")
            at(4.0, "midplay")
            at(11.0, "finalframe")
            for t in [13.0, 15.0, 17.0, 19.0, 21.0, 22.5] { at(t, t == 19.0 ? "midfade" : "fade_t\(Int(t * 10))") }
            at(25.0, "menu")
        }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor func testPortrait() { run(.portrait, "portrait") }
    @MainActor func testLandscape() { run(.landscapeLeft, "landscape") }
    @MainActor func testRotateDuringPlayback() { run(.portrait, "rotate", rotateTo: .landscapeLeft) }
}
