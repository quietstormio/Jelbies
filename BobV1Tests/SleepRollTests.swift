//
//  SleepRollTests.swift
//  2026-11-06 "more random moving when sleeping, side to side like they're rolling over, NOT left and right": sleepers roll about their own lying axis up to
//  `SleepTuning.maxRoll` (0.75 rad; was 0.30), about every 9...22 s, to a random side, back to the back, or over to the other side, always as a slow smoothstep
//  (>= 1.8 s, never faster than `rollRateMax`). A roll toward a close neighbour / in a hand-hold stays at the measured `rollNearMax` (0.30).
//  Measured on the DRAWN skin in the real sim: the roll does not slide the body across the floor, and no two skins (snuggle row, hand-hold pair) come closer than a few mm.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepRollTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let logPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/5a467ba3-0e07-4f0a-81a4-9f51bd9e9c14/scratchpad/sleeproll.log"
    static func log(_ s: String) {
        NSLog("SLEEPROLL %@", s)
        guard let d = (s + "\n").data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: URL(fileURLWithPath: logPath)) }
    }

    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() {
        SleepTuning.holdChance = 0.4; SleepTuning.cuddleChance = 0.3
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    private func tick(_ l: SocialTests.Lab) {
        l.tick(watching: false)
        for r in l.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
    }

    /// The tuning numbers the user's ask rests on.
    func testRollTuning() {
        XCTAssertEqual(SleepTuning.maxRoll, 0.75, "clearly onto a side (was 0.30)")
        XCTAssertEqual(SleepTuning.shiftEvery, 9...22)
        XCTAssertEqual(SleepTuning.driftMax, 0.22, "the left/right slide is NOT raised")
        XCTAssertGreaterThanOrEqual(SleepTuning.tossTime.lowerBound, 1.8, "a smoothstep over >= 1.8 s")
    }

    /// Drawn skin vertices (x, y, z) of one actor, every `stride`th vertex.
    private func skin(_ a: JellyActor, _ dyn: inout [Float], stride: Int = 3) -> [SIMD3<Float>] {
        dyn.withUnsafeMutableBufferPointer { a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: $0.baseAddress!) }
        return Swift.stride(from: 0, to: MotionRig.renderMesh.vertexCount, by: stride).map { SIMD3(dyn[6 * $0], dyn[6 * $0 + 1], dyn[6 * $0 + 2]) }
    }
    private func minDistance(_ a: [SIMD3<Float>], _ b: [SIMD3<Float>]) -> Float {
        var m = Float.infinity
        for p in a { for q in b { m = min(m, simd_distance_squared(p, q)) } }
        return m.squareRoot()
    }

    struct Stats { var rollMin: [Float], rollMax: [Float], rolls: [Int], timeSide: [[Float]], minSkin: Float, minSkinPair: String, lateralMax: Float, forwardMax: Float, maxAttLag: Float, maxStep: Float, simSeconds: Float, modes: [String] }

    /// Three sleepers (bedtime, as the game runs it; `hold`: hand-holding forced where a partner spot exists), `secs` simulated seconds of fidgets after all lie.
    private func measure(seed: UInt64, hold: Bool, secs: Float) -> Stats? {
        SleepTuning.holdChance = hold ? 1 : 0; SleepTuning.cuddleChance = 0
        let r = RaceTripTests.Room()
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
        var st = Stats(rollMin: [0, 0, 0], rollMax: [0, 0, 0], rolls: [0, 0, 0], timeSide: [[0, 0, 0], [0, 0, 0], [0, 0, 0]], minSkin: .infinity, minSkinPair: "", lateralMax: 0, forwardMax: 0, maxAttLag: 0, maxStep: 0, simSeconds: 0, modes: brains.map { "\($0.sleep.mode)" })
        var dyn = [[Float]](repeating: [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6), count: 3)
        var prevKind = [0, 0, 0], prevRoll: [Float] = [0, 0, 0]
        let frames = Int(secs * 60)
        for k in 0..<frames {
            step()
            for (i, a) in r.actors.enumerated() {
                let b = brains[i], f = b.sleep.fid
                st.rollMin[i] = min(st.rollMin[i], f.rollOff); st.rollMax[i] = max(st.rollMax[i], f.rollOff)
                if f.kind == 3 && prevKind[i] != 3 { st.rolls[i] += 1 }
                prevKind[i] = f.kind
                st.timeSide[i][f.rollOff > 0.3 ? 2 : (f.rollOff < -0.3 ? 0 : 1)] += 1 / 60
                st.maxStep = max(st.maxStep, abs(f.rollOff - prevRoll[i])); prevRoll[i] = f.rollOff
                // the centroid against his spot, split across / along the heading (a slide across = the left-right the user excluded)
                let c = a.sim.centroid(), d = SIMD2(c.x, c.z) - b.sleep.spot, y = b.yaw
                st.lateralMax = max(st.lateralMax, abs(simd_dot(d, SIMD2(cosf(y), -sinf(y))))); st.forwardMax = max(st.forwardMax, abs(simd_dot(d, SIMD2(sinf(y), cosf(y)))))
                let q = a.sim.bodyPose(iterations: 4).rotation, att = a.sim.attractor.rotation          // (how far the real soft body is from the commanded rotation)
                st.maxAttLag = max(st.maxAttLag, 2 * acosf(min(1, abs(simd_dot(q.vector, att.vector)))))
            }
            if k % 12 == 0 {
                let sk = r.actors.enumerated().map { skin($1, &dyn[$0]) }
                for (i, j) in [(0, 1), (0, 2), (1, 2)] {
                    let g = minDistance(sk[i], sk[j])
                    if g < st.minSkin { st.minSkin = g; st.minSkinPair = "\(i)-\(j) at \(Float(k) / 60) s, rolls \(brains[i].sleep.fid.rollOff),\(brains[j].sleep.fid.rollOff)" }
                }
            }
            st.simSeconds = Float(k + 1) / 60
        }
        return st
    }

    func testRollOversAreBigRandomBothSidesNoSlideAndSkinsNeverTouch() {
        for (hold, seeds) in [(false, [8, 9, 10]), (true, [5, 6])] as [(Bool, [UInt64])] {
            for seed in seeds {
                guard let s = measure(seed: seed, hold: hold, secs: 240) else { XCTFail("never all asleep (hold \(hold) seed \(seed))"); continue }
                Self.log(String(format: "%@ seed %d (%.0f sim s): roll min %@ max %@ rollovers %@ modes %@ s on left/flat/right %@ | min skin gap %.3f m (%@) | centroid off spot: across <= %.2f along <= %.2f | body-vs-command lag <= %.3f rad | max roll step/frame %.5f", hold ? "HOLD" : "ROW", Int(seed), s.simSeconds, s.rollMin.map { String(format: "%.2f", $0) }.description, s.rollMax.map { String(format: "%.2f", $0) }.description, s.rolls.description, s.modes.description, s.timeSide.map { $0.map { String(format: "%.0f", $0) }.joined(separator: "/") }.description, s.minSkin, s.minSkinPair, s.lateralMax, s.forwardMax, s.maxAttLag, s.maxStep))
                XCTAssertLessThan(s.maxStep, 0.0095, "never a pop: the roll moves at most 0.0095 rad per 60 Hz frame (SleepCalmTests bound)")
                XCTAssertGreaterThan(s.minSkin, 0.0, "skins never intersect")
                XCTAssertGreaterThan(s.rolls.reduce(0, +), 3 * 6, "rolls over often")
            }
        }
    }
}
