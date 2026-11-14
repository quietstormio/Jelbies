//
//  RacePullArmsTests.swift
//  "Arms and legs falling off" in the PULL race (the app's default control): every frame, the drawn root pole of each arm capsule against the drawn body skin (as RaceArmsTests
//  does for the taps race). In a pull race the body lags its attractor anchor 0.1-0.2 during the hops; the capsules used to root in the attractor pose, the feet in the fitted pose.
//  Measured 2026-11-14 (Splash, seed 7): every pole stays 7+ cm inside, in every phase, with the capsules rooted in the attractor pose, so no fix was needed; this is the guard.
//  Two cases: a roster of 3, and a roster of 1 with two temporary rival bodies (the room's wall step run every step). The measurement is per racer and per phase.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RacePullArmsTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    struct Worst { var depth = Float.infinity, frames = 0, gap: Float = 0, at = "" }

    /// Runs a pull race (steady release 0.80) and returns, per racer and phase, the worst pole depth / largest anchor-to-fitted gap.
    func race(roster: Int, tier: CourseTier, seed: UInt64, label: String) -> [[String: Worst]] {
        let room = RaceThreeTests.Room(count: roster)
        Self.keep.append(room)
        let care = room.care, rm = MotionRig.renderMesh
        for b in CourseTier.allCases where b.index < tier.index { care.race.progress.records[b] = CourseProgress.Record(races: 1, wins: 1, topTwo: 1) }
        care.race.courseTier = tier
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.7)
        care.race.autoRate = nil
        care.race.recentRivals = nil
        care.race.control = .pull
        for a in room.actors { a.brain?.amplitude = 1 }
        care.startRace(jelly: 0, seed: seed)
        var dyn = [[Float]](repeating: [Float](repeating: 0, count: rm.vertexCount * 6), count: 3)
        var worst: [[String: Worst]] = [[:], [:], [:]]
        let dt = room.actors[0].sim.stepDt
        var n = 0
        while n < 60 * 150, !care.race.hasResults {
            n += 1
            if let s = care.race.sim, care.race.phase == .racing, !s.pullState(0).buffered { _ = care.race.release(pull: 0.80) }
            room.step()
            if roster == 1 { MelonController.applyRoomArena(actors: room.actors, parkActors: room.park, bathFenceLifted: false) }
            guard let sim = care.race.sim, care.race.trackVisible, care.raceBook.racers.count == 3, sim.phase != .results else { continue }
            let all = room.actors + room.park
            for k in 0..<3 {
                let a = all[care.raceBook.racers[k]]
                guard let b = a.brain, b.race.active else { continue }
                b.refitBeans(a.sim, a.skinner)
                a.skinner.update(x: a.sim.x, index: rm.index, into: &dyn[k])
                let phase = sim.phase == .countdown ? "countdown" : b.raceHopFitted ? "\(b.gait.phase)" : "standing"
                let gap = simd_length(a.sim.attractor.anchor - a.sim.bodyPose(iterations: 3).centroid)
                for side in 0..<2 {
                    guard let d = RaceArmsTests.poleDepth(a, dyn: dyn[k], side: side) else { continue }
                    var w = worst[k][phase] ?? Worst()
                    w.frames += 1; w.gap = max(w.gap, gap)
                    if d < w.depth { w.depth = d; w.at = String(format: "t=%.2f n=%d armG %.2f", Float(n) * dt, n, b.armG) }
                    worst[k][phase] = w
                }
            }
        }
        for k in 0..<3 { for ph in worst[k].keys.sorted() { let w = worst[k][ph]!
            MotionLog.write(String(format: "RACEPULLARMS %@ racer %d | %@ | frames %d | min pole depth %.2f cm | max anchor-to-fitted %.3f | %@", label, 0, k, ph, w.frames, w.depth * 100, w.gap, w.at)) } }
        return worst
    }

    private func check(_ w: [[String: Worst]], _ label: String) {
        for k in 0..<3 {
            XCTAssertTrue(w[k].keys.contains("countdown"), "\(label) racer \(k): countdown measured")
            for (ph, v) in w[k] { XCTAssertGreaterThanOrEqual(v.depth, RaceArmsTests.minDepth, "\(label) racer \(k) \(ph): arm root pole \(String(format: "%.1f", v.depth * 100)) cm below the drawn skin (need >= 1.5): the stub floats off the body (\(v.at))") }
        }
        XCTAssertTrue(w.contains { $0.keys.contains("air") }, "\(label): a hop was measured")
    }

    func testPullRaceRoster3ArmsStayOn() { check(race(roster: 3, tier: .splash, seed: 7, label: "roster3 splash"), "roster3") }
    func testPullRaceRoster1TemporaryRivalsArmsStayOn() { check(race(roster: 1, tier: .splash, seed: 7, label: "roster1 splash"), "roster1") }
}
