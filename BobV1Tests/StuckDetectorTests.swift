//
//  StuckDetectorTests.swift
//  no-stuck-r1: the dev stuck detector (Dev/StuckDetector.swift) must flag the two stuck bugs the owner hit (with their fixes switched off) and stay quiet on a normal room.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class StuckDetectorTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var savedHour: Double?
    private var saved: (Bool, Bool, Bool, Bool, Bool) = (false, false, false, false, false)

    override func setUp() {
        savedHour = DayClock.shared.forcedHour; DayClock.shared.forcedHour = 14
        saved = (StuckDetector.on, FocusGroup.handBackFix, FocusGroup.netEnabled, GameCare.unstickOn, GameCare.stuckReleaseOn)
        StuckDetector.on = true; StuckDetector.shared.reset()
    }
    override func tearDown() {
        DayClock.shared.forcedHour = savedHour
        (StuckDetector.on, FocusGroup.handBackFix, FocusGroup.netEnabled, GameCare.unstickOn, GameCare.stuckReleaseOn) = saved
        StuckDetector.shared.reset()
    }

    private var events: [String: Int] { StuckDetector.shared.events }
    private func dump() -> String { StuckDetector.shared.log.joined(separator: "\n") }

    // (a) Pink frozen: "Come here" for everyone, Cancel while Jelly 0 waits on his spot
    private func comeHereCancel(fixOn: Bool) -> FocusAnyRun {
        FocusGroup.handBackFix = fixOn; FocusGroup.netEnabled = fixOn
        GameCare.stuckReleaseOn = fixOn
        let r = FocusAnyRun(count: 3, peers: true); Self.keep.append(r); r.run(1)
        StuckDetector.shared.reset()
        let a = GameCamera.callSpot
        r.place(1, at: SIMD2(-2.2, -1.8)); r.place(2, at: SIMD2(2.2, -1.8)); r.place(0, at: SIMD2(a.x, a.y - 0.2))
        r.care.comeHereEveryone()
        XCTAssertTrue(r.run(4) { r.care.focusGroup.arrived.contains(0) && r.care.focus.phase == .approaching })
        r.care.cancelGroupAction()
        r.run(70)
        return r
    }

    func testFlagsTheComeHereFreezeBeforeTheFix() {
        _ = comeHereCancel(fixOn: false)
        XCTAssertGreaterThanOrEqual(events["autonomy-off", default: 0], 1, dump())
        XCTAssertGreaterThanOrEqual(events["motionless", default: 0], 1, dump())
    }

    func testQuietAfterTheComeHereFix() {
        _ = comeHereCancel(fixOn: true)
        XCTAssertEqual(events["autonomy-off", default: 0] + events["motionless", default: 0], 0, dump())
    }

    // (b) food / drink dead until a relaunch: a lost Come call left `callRunning` set
    private func room() -> DiningJellyTests.Room {
        let r = DiningJellyTests.Room(count: 3, wander: true)
        DiningJellyTests.keep.append(r.care); DiningJellyTests.keep.append(contentsOf: r.actors)
        DiningGroup.homeSeats = 3
        step(r, 1)
        StuckDetector.shared.reset()
        return r
    }
    private func step(_ r: DiningJellyTests.Room, _ s: Float) { for _ in 0..<Int(s * 60) { r.tick(); r.care.tickDecor(dt: 1 / 60); r.care.tickPlay(r.actors, dt: 1 / 60) } }

    private func staleCall(unstick: Bool) {
        GameCare.unstickOn = unstick
        let r = room()
        r.care.callRunning = true
        step(r, 10)
        for a in r.actors { a.profile?.needs.set(.hunger, 0.1) }
        r.care.feed()
        step(r, 100)
    }

    func testFlagsTheLostCallBeforeTheFix() {
        staleCall(unstick: false)
        XCTAssertGreaterThanOrEqual(events["call-lost", default: 0], 1, dump())          // (the stale lock itself; in this rig Jelly 0 is pinned, the others still eat, so the tap is "answered")
    }

    func testQuietAfterTheLostCallFix() {
        staleCall(unstick: true)
        XCTAssertEqual(events["call-lost", default: 0] + events["tap-no-effect", default: 0], 0, dump())
    }

    /// A normal room left alone (day and night) raises nothing.
    func testQuietRoom() {
        for hour in [14.0, 23.0] {
            DayClock.shared.forcedHour = hour
            let r = room()
            step(r, 240)
            XCTAssertEqual(events.values.reduce(0, +), 0, "hour \(hour):\n" + dump())
            StuckDetector.shared.reset()
        }
    }
}
