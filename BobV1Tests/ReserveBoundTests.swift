//
//  ReserveBoundTests.swift
//  A meal that keeps failing is served again at most GameCare.maxReserves (2) times, then given up on: the tray poofs and he is left at rest.
//  (endMeal used to zero the retry count, so a Blob who was displaced every time got a new tray forever.)
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ReserveBoundTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = [] }
    override func tearDown() { RoomLayout.dynamicBoxes = [] }

    /// Displaces him (a grab and a put-down 1.7 u nearer the camera) every single time he starts eating.
    func testReServeLoopIsBounded() {
        let m = MealRun()
        m.brain.requestNow(.goTo(SIMD2(0, 0.2)))
        m.run(10) { m.brain.activity == .idle && simd_distance(m.brain.position, SIMD2(0, 0.2)) < 0.3 }
        m.run(0.8)
        m.care.feed("berries")
        var trays = 0, displaced = 0, prev = DiningSet.Phase.absent, done = false
        for _ in 0..<(60 * 150) {
            m.tick()
            if prev == .absent, m.tray.phase == .popping { trays += 1 }
            prev = m.tray.phase
            if m.brain.activity == .eating, m.tray.phase == .present, displaced < 8 {
                displaced += 1
                m.brain.abortScript(m.rig.sim, m.rig.skinner)
                for i in 0..<m.rig.sim.x.count / 3 { m.rig.sim.x[3 * i + 2] += 1.7 }
                for i in m.rig.sim.v.indices { m.rig.sim.v[i] = 0 }
                m.brain.currentPose(m.rig.sim)
            }
            if displaced > 0, !m.care.trayOut, m.tray.phase == .absent { done = true; break }
        }
        MotionLog.write("RESERVE trays \(trays) displaced \(displaced) done \(done)")
        XCTAssertTrue(done, "the loop ends: the tray is gone and nothing is pending")
        XCTAssertLessThanOrEqual(trays, 1 + GameCare.maxReserves, "the first tray plus at most \(GameCare.maxReserves) re-serves")
        XCTAssertEqual(trays, 1 + GameCare.maxReserves, "it did re-serve the allowed number of times")
        XCTAssertFalse(m.care.trayOut)
        XCTAssertEqual(m.tray.phase, .absent)
        XCTAssertTrue(RoomLayout.dynamicBoxes.isEmpty, "no collider left")
        m.run(3)
        XCTAssertTrue(m.brain.activity == .idle || m.brain.activity == .lookingAround || m.brain.activity == .steppingInPlace, "he is at rest, not stuck in a meal (\(m.brain.activity))")
        // a fresh tap gets a fresh budget
        m.care.feed("berries")
        var ate = false
        for _ in 0..<(60 * 60) { m.tick(); if m.brain.activity == .eating { ate = true; break } }
        XCTAssertTrue(ate, "a new tap is served again (the budget restarts on a fresh tap)")
    }
}
