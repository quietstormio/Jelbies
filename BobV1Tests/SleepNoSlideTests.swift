//
//  SleepNoSlideTests.swift
//  2026-11-06 "when they start turning they pull towards each other, their whole body slides": a roll is a turn in place about the body's own lying axis.
//  Measured on the real soft-body centroid and the drawn skins: no roll moves a sleeper across the floor and no two sleepers ever move into each other.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepNoSlideTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let logPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/5a467ba3-0e07-4f0a-81a4-9f51bd9e9c14/scratchpad/sleepnoslide.log"
    static func log(_ s: String) {
        NSLog("SLEEPNOSLIDE %@", s)
        guard let d = (s + "\n").data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: URL(fileURLWithPath: logPath)) }
    }
    // (2026-11-12: `TEST_RUNNER_SLOWWAKE_OFF=1` runs this suite with `slowWakeEverywhere` off, to attribute a difference to the staged wake.)
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); BlobBrain.slowWakeEverywhere = ProcessInfo.processInfo.environment["SLOWWAKE_OFF"] != "1" }
    override func tearDown() {
        SleepTuning.holdChance = 0.4; SleepTuning.cuddleChance = 0.3; SleepTuning.maxRoll = 0.75
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    private func skin(_ a: JellyActor, _ dyn: inout [Float], stride: Int = 3) -> [SIMD3<Float>] {
        dyn.withUnsafeMutableBufferPointer { a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: $0.baseAddress!) }
        return Swift.stride(from: 0, to: MotionRig.renderMesh.vertexCount, by: stride).map { SIMD3(dyn[6 * $0], dyn[6 * $0 + 1], dyn[6 * $0 + 2]) }
    }
    private func minDistance(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>]) -> Float {
        var m = Float.infinity
        for p in a { for q in b { m = min(m, simd_distance_squared(p, q)) } }
        return m.squareRoot()
    }

    nonisolated(unsafe) static var trace = false
    struct Result { var perRoll: Float = 0, total: Float = 0, spotTravel: Float = 0, gap0: Float = .infinity, gapMin: Float = .infinity, rolls = 0, drifts = 0, simS: Float = 0 }

    private func measure(count: Int, seed: UInt64, hold: Bool, secs: Float) -> Result? {
        SleepTuning.holdChance = hold ? 1 : 0; SleepTuning.cuddleChance = 0
        let r = RaceThreeTests.Room(count: count)
        Self.keep.append(r)
        let brains = r.actors.compactMap(\.brain)
        for a in r.actors {
            guard let b = a.brain else { continue }
            b.sleepEnabled = true; b.autonomy = true
            b.seed = seed &+ UInt64(a.id) &* 7919
            b.socialOthers = { [unowned r] in r.actors.compactMap(\.brain) }
        }
        func step() {
            for b in brains { b.idleNight = DayClock.shared.nightFactor; b.idleMorning = DayClock.shared.morningFactor; b.idleDeepNight = DayClock.shared.deepNightFactor }
            r.step()
        }
        r.care.bedtimeAll()
        var n = 0
        while !brains.allSatisfy({ $0.isNapping }) && n < 90 * 60 { step(); n += 1 }
        guard brains.allSatisfy({ $0.isNapping }) else { return nil }
        for _ in 0..<(3 * 60) { step() }
        for b in brains { b.sleep.hold = 590 }          // (nobody wakes in the window (> 600 would wake in the morning); the wake roll-up walks them off the spot and is not what is measured)
        var res = Result()
        var dyn = [[Float]](repeating: [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6), count: count)
        func gaps() -> Float {
            let sk = r.actors.enumerated().map { skin($1, &dyn[$0]) }
            var m = Float.infinity
            for i in 0..<count { for j in (i + 1)..<count { m = min(m, minDistance(sk[i], sk[j])) } }
            return m
        }
        func cen(_ a: JellyActor) -> SIMD2<Float> { let c = a.sim.centroid(); return SIMD2(c.x, c.z) }
        res.gap0 = gaps(); res.gapMin = res.gap0
        let c0 = r.actors.map(cen), spot0 = brains.map(\.position)
        var rollStart = [SIMD2<Float>?](repeating: nil, count: count), prevKind = [Int](repeating: 0, count: count)
        let frames = Int(secs * 60)
        for k in 0..<frames {
            step()
            for (i, a) in r.actors.enumerated() {
                let f = brains[i].sleep.fid, c = cen(a)
                if f.kind == 3 && prevKind[i] != 3 { rollStart[i] = c; res.rolls += 1 }
                if f.kind == 4 && prevKind[i] != 4 { res.drifts += 1 }
                if f.kind == 3, let s = rollStart[i] { res.perRoll = max(res.perRoll, simd_distance(c, s)) }
                if f.kind != 3 { rollStart[i] = nil }
                prevKind[i] = f.kind
                res.total = max(res.total, simd_distance(c, c0[i]))
                res.spotTravel = max(res.spotTravel, simd_distance(brains[i].position, spot0[i]))
            }
            if Self.trace, k % 120 == 0 {
                let l = r.actors.enumerated().map { (i, a) -> String in let b = brains[i], c = cen(a); return String(format: "[%d kind %d roll %.2f off-spot (%.3f,%.3f) vs-c0 (%.3f,%.3f)]", i, b.sleep.fid.kind, b.sleep.fid.rollOff, c.x - b.position.x, c.y - b.position.y, c.x - c0[i].x, c.y - c0[i].y) }
                Self.log(String(format: "T %.0f ", Float(k) / 60) + l.joined(separator: " "))
            }
            if k % 12 == 0 { res.gapMin = min(res.gapMin, gaps()) }
            res.simS = Float(k + 1) / 60
        }
        return res
    }

    private func check(count: Int, seeds: [UInt64], hold: Bool) {
        for seed in seeds {
            guard let s = measure(count: count, seed: seed, hold: hold, secs: 240) else { XCTFail("never all asleep (\(count) hold \(hold) seed \(seed))"); continue }
            Self.log(String(format: "n=%d hold=%d seed=%d maxRoll=%.2f (%.0f sim s): rolls %d drifts %d | max centroid travel in one roll %.3f m | total from lie-down %.3f m | spot travel %.3f | skin gap at lie-down %.3f min %.3f", count, hold ? 1 : 0, Int(seed), SleepTuning.maxRoll, s.simS, s.rolls, s.drifts, s.perRoll, s.total, s.spotTravel, s.gap0, s.gapMin))
            XCTAssertGreaterThan(s.rolls, count * 4, "rolls happen")
            XCTAssertLessThanOrEqual(s.perRoll, 0.03, "a roll is a turn in place: <= 3 cm of centroid travel (n=\(count) seed \(seed))")
            XCTAssertLessThanOrEqual(s.total, 0.08, "<= 8 cm total travel in 240 s (n=\(count) seed \(seed))")
            // (a hand-hold pair's drawn skin gap narrows by the reaching arm nub / rolled shoulder with BOTH centroids still: the centres not moving is the no-slide proof there)
            if hold { XCTAssertGreaterThan(s.gapMin, 0.0, "skins never touch (n=\(count) seed \(seed))") }
            else { XCTAssertGreaterThanOrEqual(s.gapMin, s.gap0 - 0.01, "the skin gap never shrinks (n=\(count) seed \(seed))") }
        }
    }

    func testTwoSleepersSideBySideDoNotSlide() { check(count: 2, seeds: [8, 9, 10], hold: false) }
    func testTwoHandHoldersDoNotSlide() { check(count: 2, seeds: [5, 6], hold: true) }
    func testThreeSleeperRowDoesNotSlide() { check(count: 3, seeds: [8, 9], hold: false) }

    /// Diagnostic only: the same two-sleeper run at the old roll (0.30) for the before/after numbers.
    /// Diagnostic only: the same two-sleeper run at the old roll (0.30) for the before/after numbers.
    func testTraceSeed9() {
        Self.trace = true; defer { Self.trace = false }
        _ = measure(count: 2, seed: 9, hold: false, secs: 240)
    }

    func testOldRollForComparison() {
        SleepTuning.maxRoll = 0.30
        for seed: UInt64 in [8, 9, 10] {
            guard let s = measure(count: 2, seed: seed, hold: false, secs: 240) else { continue }
            Self.log(String(format: "OLD n=2 seed=%d maxRoll=0.30: rolls %d drifts %d | one roll %.3f | total %.3f | spot %.3f | gap0 %.3f min %.3f", Int(seed), s.rolls, s.drifts, s.perRoll, s.total, s.spotTravel, s.gap0, s.gapMin))
        }
    }
}
