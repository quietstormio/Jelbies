//
//  SleepCalmTests.swift
//  User 2026-11-05: "Their movement while sleep is glitchy and buggy, like they twitch. It needs to be natural tossing and turning, slow."
//  A sleeper's root, heading, lying rotation and body centroid must move smoothly: no frame-to-frame jerk above a calm bound, and at least one slow toss.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SleepCalmTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var room: RaceTripTests.Room!
    static let logPath = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/5a467ba3-0e07-4f0a-81a4-9f51bd9e9c14/scratchpad/sleepcalm.log"

    static func log(_ s: String) {
        NSLog("SLEEPCALM %@", s)
        guard let d = (s + "\n").data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: URL(fileURLWithPath: logPath)) }
    }

    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        DayClock.shared.forcedHour = 23
    }
    override func tearDown() {
        DayClock.shared.forcedHour = 12
        DecorField.shared.clear()
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    struct Rec { var px: Float, pz: Float, yaw: Float, c: SIMD3<Float>, q: simd_quatf, kind: Int, twU: Float, halfU: Float, yawOff: Float, rollOff: Float, wig: Float }

    static func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float { let d = (a.inverse * b).normalized; return 2 * atan2f(simd_length(d.imag), abs(d.real)) }

    /// Runs three sleepers for `secs` after all are napping; returns the per-frame records of each.
    private func record(seed: UInt64, secs: Float) -> [[Rec]]? {
        let r = RaceTripTests.Room()
        Self.keep.append(r); room = r
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
        for _ in 0..<(3 * 60) { step() }          // let the flop settle
        var out = [[Rec]](repeating: [], count: brains.count)
        for _ in 0..<Int(secs * 60) {
            step()
            for (i, a) in r.actors.enumerated() {
                let b = brains[i], f = b.sleep.fid
                out[i].append(Rec(px: b.px, pz: b.pz, yaw: b.yaw, c: a.sim.centroid(), q: a.sim.attractor.rotation, kind: f.kind, twU: f.twU, halfU: f.halfU, yawOff: f.yawOff, rollOff: f.rollOff, wig: f.rollW))
            }
        }
        return out
    }

    struct Stats { var rootAcc: Float = 0, yawAcc: Float = 0, cAcc: Float = 0, angAcc: Float = 0, rootAt = 0, angAt = 0, cAt = 0 }

    func stats(_ s: [Rec]) -> Stats {
        var st = Stats()
        let dt: Float = 1.0 / 60
        guard s.count > 3 else { return st }
        func wrap(_ x: Float) -> Float { var v = x; while v > .pi { v -= 2 * .pi }; while v < -.pi { v += 2 * .pi }; return v }
        for i in 2..<s.count {
            let a = s[i - 2], b = s[i - 1], c = s[i]
            let ra = simd_length(SIMD2(c.px - 2 * b.px + a.px, c.pz - 2 * b.pz + a.pz)) / (dt * dt)
            let ya = abs(wrap(c.yaw - b.yaw) - wrap(b.yaw - a.yaw)) / (dt * dt)
            let ca = simd_length(c.c - 2 * b.c + a.c) / (dt * dt)
            let w1 = Self.angle(a.q, b.q) / dt, w2 = Self.angle(b.q, c.q) / dt
            let aa = abs(w2 - w1) / dt
            if ra > st.rootAcc { st.rootAcc = ra; st.rootAt = i }
            st.yawAcc = max(st.yawAcc, ya)
            if ca > st.cAcc { st.cAcc = ca; st.cAt = i }
            if aa > st.angAcc { st.angAcc = aa; st.angAt = i }
        }
        return st
    }

    /// Awake idle baseline: one Jelbie standing about, no autonomy walks. Same stats over 30 s.
    private func awakeBaseline() -> Stats {
        let r = RaceTripTests.Room()
        Self.keep.append(r)
        DayClock.shared.forcedHour = 12
        let a = r.actors[0]
        var recs: [Rec] = []
        for _ in 0..<(30 * 60) {
            r.step()
            let b = a.brain!
            recs.append(Rec(px: b.px, pz: b.pz, yaw: b.yaw, c: a.sim.centroid(), q: a.sim.attractor.rotation, kind: 0, twU: 0, halfU: 0, yawOff: 0, rollOff: 0, wig: 0))
        }
        DayClock.shared.forcedHour = 23
        return stats(recs)
    }

    /// Calm bound. A toss is a smoothstep from one side to the other (at most 2 * maxRoll = 0.60 rad) over at least 1.8 s: peak angular acceleration
    /// 6 * 0.60 / 1.8^2 = 1.1 rad/s^2 (peak speed 0.5 rad/s = 0.0083 rad/frame). The old pop back to flat was 0.18 rad in one frame = 650 rad/s^2, the old
    /// wiggle start 5 rad/s^2. 2 rad/s^2 is ~1.8x over the worst legal toss and 300x under the pop. (The awake idle baseline is ~0: a standing Jelbie is
    /// nearly rigid; the awake WALK is far above this, so the bound is set by the toss design, not by a walk.) This measures the attractor (commanded
    /// rotation); the centroid is the real soft body.
    static let calmAng: Float = 2.0
    /// Root / centroid: a drift is a smoothstep of <= 0.22 m over >= 3 s (peak accel 6 * 0.22 / 9 = 0.15 m/s^2).
    /// The soft body's own centroid answers a toss start with up to ~0.55 m/s^2 (measured; 0.05 g); the old pop gave 1.7. 0.8 sits between them.
    static let calmRoot: Float = 0.3, calmCentroid: Float = 0.8

    func testSleepersMoveCalmlyAndToss() {
        let base = awakeBaseline()
        Self.log(String(format: "awake idle baseline: rootAcc %.3f yawAcc %.3f centAcc %.3f angAcc %.3f", base.rootAcc, base.yawAcc, base.cAcc, base.angAcc))
        var tossesAll = 0
        for seed in [1, 2, 3] as [UInt64] {
            guard let rec = record(seed: seed, secs: 150) else { XCTFail("never all asleep"); continue }
            for (i, s) in rec.enumerated() {
                let st = stats(s)
                let tosses = zip(s, s.dropFirst()).filter { $0.0.kind == 0 && $0.1.kind == 3 }.count
                tossesAll += tosses
                let maxStepRoll = zip(s, s.dropFirst()).map { abs($1.rollOff - $0.rollOff) }.max() ?? 0
                let starts = s.indices.dropFirst().filter { s[$0 - 1].kind == 0 && s[$0].kind != 0 }.map { "\($0)k\(s[$0].kind)" }
                Self.log(String(format: "seed %d j%d rootAcc %.3f yawAcc %.3f centAcc %.3f@%d(kind %d) angAcc %.3f@%d(kind %d) tosses %d maxRollStep %.5f starts %@", Int(seed), i, st.rootAcc, st.yawAcc, st.cAcc, st.cAt, s[st.cAt].kind, st.angAcc, st.angAt, s[st.angAt].kind, tosses, maxStepRoll, starts.joined(separator: ",")))
                XCTAssertLessThan(st.angAcc, Self.calmAng, "seed \(seed) j\(i): lying rotation jerk at frame \(st.angAt)")
                XCTAssertLessThan(st.rootAcc, Self.calmRoot, "seed \(seed) j\(i): root jerk at frame \(st.rootAt)")
                XCTAssertLessThan(st.yawAcc, 1.0, "seed \(seed) j\(i): yaw jerk")
                XCTAssertLessThan(st.cAcc, Self.calmCentroid, "seed \(seed) j\(i): body centroid jerk at frame \(st.cAt)")
                XCTAssertLessThan(maxStepRoll, 0.0095, "seed \(seed) j\(i): side tilt moved in a pop")
            }
        }
        XCTAssertGreaterThanOrEqual(tossesAll, 3, "sleepers do toss and turn")
    }
}
