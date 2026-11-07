//
//  RaceArmsTests.swift
//  "The arms come off during the track meets" (user, 2026-11-06: Lavender at the start line, countdown "1", both stub arms floating a visible gap away from the body).
//  A whole race with hurdles, three bodies, the glue exactly as the game does it (like RaceFeetTests), and in EVERY frame of the countdown, the sprint, the jump and the landing the
//  DRAWN arm of each racer is measured against the DRAWN body skin: the root pole of the arm capsule (the deepest point of the buried end) must lie inside the drawn skin by at least
//  ArmCapTests' bound (1.5 cm: "the arm base stays buried in the body (fused, no gap)"). A pole outside the drawn skin is a stub floating off the body.
//  Before the fix (BlobBrain's hopPlay branch returned without driving the arms) the pole was 40-46 cm OUTSIDE the skin through every hurdle jump; Panda shares Teddy's body (feature .ears).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RaceArmsTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    /// The bound ArmCapTests holds every move to (root centre buried 1.5 cm); here it is the drawn root POLE against the drawn skin.
    static let minDepth: Float = 0.015

    struct Worst { var depth = Float.infinity, frames = 0, at = "", rootDepthFit = Float.infinity, worstSide = 0 }

    /// Signed depth (+ = inside) of the drawn root pole of arm `side` below the drawn body skin (nearest skin vertex, its normal); nil when the capsule is not out.
    static func poleDepth(_ a: JellyActor, dyn: [Float], side: Int) -> Float? {
        guard let b = a.brain, b.armG > 0.5, let info = MotionRig.renderMesh.armCapsule else { return nil }
        let pole = info.firstVertex[side] + ArmCapsule.vertexCount - 1, bodyEnd = info.firstVertex[0]
        let P = SIMD3(dyn[6 * pole], dyn[6 * pole + 1], dyn[6 * pole + 2])
        var best = Float.infinity, depth: Float = 0
        dyn.withUnsafeBufferPointer { d in
            for v in 0..<bodyEnd {
                let o = 6 * v
                let dx = P.x - d[o], dy = P.y - d[o + 1], dz = P.z - d[o + 2]
                let l2 = dx * dx + dy * dy + dz * dz
                if l2 < best { best = l2; depth = -(dx * d[o + 3] + dy * d[o + 4] + dz * d[o + 5]) }
            }
        }
        return depth
    }

    /// Runs a race with the given features on the three bodies and measures each racer's arms every frame. Returns the worst per phase per racer.
    func race(_ name: String, features: [JellyFeature], course tier: CourseTier, seed: UInt64, taps: Float, jump: Bool) {
        let room = RaceTripTests.Room()
        Self.keep.append(room)
        let care = room.care, rm = MotionRig.renderMesh
        for (k, f) in features.enumerated() {
            let a = room.actors[k]
            a.brain?.feature = f; a.skinner.configureTail(rm); a.skinner.tailOn = f == .spines; a.brain?.skinnerRef = a.skinner
            a.brain?.amplitude = 1
        }
        for b in CourseTier.allCases where b.index < tier.index { care.race.progress.records[b] = CourseProgress.Record(races: 1, wins: 1, topTwo: 1) }
        care.race.courseTier = tier
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.7)
        care.race.autoRate = nil
        var dyn = room.actors.map { _ in [Float](repeating: 0, count: rm.vertexCount * 6) }
        care.startRace(jelly: 0, seed: seed)
        var worst: [[String: Worst]] = [[:], [:], [:]]
        let dt = room.actors[0].sim.stepDt
        var n = 0, foot = 0, tapT: Float = 0
        while n < 60 * 120, care.race.active, !(care.race.hasResults && n > 0 && care.race.sim?.phase == .results) {
            n += 1
            if let sim = care.race.sim, care.race.phase == .racing, sim.phase == .running || sim.phase == .finishing {
                if jump { care.race.sim?.autoJumpPlayer = true }
                tapT += dt; while tapT >= 1 / taps { tapT -= 1 / taps; _ = care.race.tap(foot: foot); foot = 1 - foot }
            }
            room.step()
            for (k, a) in room.actors.enumerated() {
                a.brain?.refitBeans(a.sim, a.skinner)
                guard let sim = care.race.sim, care.raceBook.racers.contains(k), let b = a.brain, b.race.active, sim.phase != .results else { continue }
                a.skinner.update(x: a.sim.x, index: rm.index, into: &dyn[k])
                let phase = sim.phase == .countdown ? "countdown" : b.race.jumping ? "jump \(b.gait.phase)" : b.race.jumpQueued ? "jump queued" : "sprint"
                for side in 0..<2 {
                    guard let d = Self.poleDepth(a, dyn: dyn[k], side: side) else { continue }
                    var w = worst[k][phase] ?? Worst()
                    w.frames += 1
                    if d < w.depth { w.depth = d; w.worstSide = side; w.at = String(format: "t=%.2f n=%d armG %.2f armLift %.2f armWalkWant %.1f", Float(n) * dt, n, b.armG, b.armLift, b.armWalkWant) }
                    worst[k][phase] = w
                }
            }
        }
        for k in 0..<3 {
            for ph in worst[k].keys.sorted() {
                let w = worst[k][ph]!
                MotionLog.write(String(format: "RACEARMS %@ racer %d (%@) | %@ | frames %d | min root-pole depth below the drawn skin %.2f cm (side %d) | %@", name, k, "\(features[k])", ph, w.frames, w.depth * 100, w.worstSide, w.at))
                XCTAssertGreaterThanOrEqual(w.depth, Self.minDepth, "\(name) racer \(k) (\(features[k])) \(ph): an arm root pole is \(String(format: "%.1f", w.depth * 100)) cm below the drawn skin (need >= \(Self.minDepth * 100)): the stub floats off the body (\(w.at))")
            }
            XCTAssertTrue(worst[k].keys.contains("countdown"), "\(name) racer \(k): the countdown was measured")
            XCTAssertTrue(worst[k].keys.contains("sprint"), "\(name) racer \(k): the sprint was measured")
            if jump && k == 0 { XCTAssertTrue(worst[k].keys.contains { $0.hasPrefix("jump ") }, "\(name): the jump was measured") }
        }
    }

    func testArmsStayOnBobPipLavenderWave() { race("wave BobPipLavender", features: [.none, .spines, .wings], course: .wave, seed: 9, taps: 3, jump: true) }
    func testArmsStayOnTeddyMossBobSplash() { race("splash TeddyMossBob", features: [.ears, .daisy, .none], course: .splash, seed: 5, taps: 3, jump: true) }
    func testArmsStayOnLavenderPipTeddyWave() { race("wave LavenderPipTeddy", features: [.wings, .spines, .ears], course: .wave, seed: 9, taps: 3, jump: true) }
}
