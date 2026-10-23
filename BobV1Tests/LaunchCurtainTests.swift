//
//  LaunchCurtainTests.swift
//  The launch gate's timing rules (injected clock) and the curtain's captures (portrait and landscape, day and night).
//

import XCTest
import SwiftUI
@testable import BobV1

@MainActor
final class LaunchCurtainTests: XCTestCase {
    private final class Clock { var t: TimeInterval = 100 }
    /// (MainActor objects are kept alive: their isolated deinit crashes the runtime under test, like the other suites' `keep`.)
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func gate(_ c: Clock) -> LaunchGate { let g = LaunchGate(clock: { c.t }); Self.keep.append(g); return g }

    func testHidesOnlyAfterMinShowStageTickAndSettle() {
        let c = Clock()
        let g = gate(c)
        XCTAssertTrue(g.visible)
        c.t += 0.5; g.stageTicked()
        XCTAssertTrue(g.visible, "not before minShow")
        c.t += 0.5; g.evaluate()
        XCTAssertFalse(g.visible, "minShow passed and the stage ticked")
    }

    func testWaitsForTheStage() {
        let c = Clock()
        let g = gate(c)
        c.t += 2; g.evaluate()
        XCTAssertTrue(g.visible, "no tick yet")
        g.stageTicked()
        XCTAssertFalse(g.visible)
    }

    func testCapsAtMaxShow() {
        let c = Clock()
        let g = gate(c)
        c.t += LaunchGate.maxShow + 0.1; g.evaluate()
        XCTAssertFalse(g.visible, "never longer than the hard cap, even if the stage never ticked")
    }

    func testResumeHoldShowsAtLeastItsMinimumAndWaitsForSettle() {
        let c = Clock()
        let g = gate(c)
        c.t += 1; g.stageTicked()
        XCTAssertFalse(g.visible)
        g.hold(.resume)
        XCTAssertTrue(g.visible)
        c.t += 0.2; g.stageTicked()
        XCTAssertTrue(g.visible, "0.35 s minimum")
        c.t += 0.2; g.stageTicked()
        XCTAssertTrue(g.visible, "still settling")
        g.settled(true)
        XCTAssertFalse(g.visible, "settled")
    }

    func testHoldDuringTheLaunchCurtainStillWaitsForTheFirstStageTick() {
        let c = Clock()
        let g = gate(c)
        g.hold(.launch)          // greetIfAway on a cold launch, before the stage has run
        g.settled(false)
        c.t += LaunchGate.settleCap + 0.5; g.evaluate()
        XCTAssertTrue(g.visible, "the room has not built or drawn yet: the settle cap must not lift it")
        g.stageTicked()
        c.t += LaunchGate.settleCap + 0.1; g.stageTicked()
        XCTAssertFalse(g.visible)
    }

    func testSettleCapEndsTheWait() {
        let c = Clock()
        let g = gate(c)
        c.t += 1; g.stageTicked()
        g.hold(.resume)
        c.t += LaunchGate.settleCap + 0.1; g.stageTicked()
        XCTAssertFalse(g.visible, "2 s cap")
    }

    func testAPlainResumeNeverShowsIt() {
        let c = Clock()
        let g = gate(c)
        c.t += 1; g.stageTicked()
        XCTAssertFalse(g.visible)
        for _ in 0..<10 { c.t += 1; g.stageTicked(); g.evaluate() }
        XCTAssertFalse(g.visible)
    }

    func testCapture() throws {
        guard let dir = ProcessInfo.processInfo.environment["LAUNCH_CAP_DIR"] else { throw XCTSkip("set TEST_RUNNER_LAUNCH_CAP_DIR") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, hour) in [("day", 13.0), ("night", 23.0)] {
            for (orient, size) in [("portrait", CGSize(width: 440, height: 956)), ("landscape", CGSize(width: 956, height: 440))] {
                let r = ImageRenderer(content: LaunchCurtainArt(hour: hour, bounce: true).frame(width: size.width, height: size.height))
                r.scale = 3
                let png = r.uiImage?.pngData()
                XCTAssertNotNil(png)
                try png?.write(to: URL(fileURLWithPath: "\(dir)/launch_\(name)_\(orient).png"))
            }
        }
    }
}
