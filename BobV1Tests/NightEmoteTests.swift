//
//  NightEmoteTests.swift
//  night-emotes-r1: the five calm night solos (BlobBrain+NightEmotes.swift). Table: picked at night, never by day, the wander share and the non-wander total unchanged.
//  Run: each starts, ends free (eyes / mouth / arms released) and cancels cleanly (a gate yield and a hard abort). Bedtime: a goodnight while one runs puts him to bed
//  as fast as it does from a plain sit. The feet / arms invariants run per kind in EmoteFeetTests (testNight...: NightEmoteFeetTests.swift) and the idle table of OnePieceInvariantTests.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class NightEmoteTests: XCTestCase {
    static let out = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/49d32754-b08a-4bfd-999b-3f9f0cada45f/scratchpad/nightemotes/"
    let kinds = NightEmoteTuning.kinds

    override func setUp() { super.setUp(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    private func w(_ m: IdleMood, night: Float) -> [(kind: IdleKind, weight: Float)] {
        IdleTable.weights(m, night: night, morning: 0, sleep: true, antics: true, music: false)
    }

    func testTableNightOnlyAndTotalUnchanged() throws {
        var report = "mood night | kind weights | non-wander total | wander\n"
        for m in [IdleMood.happy, .okay] {
            for night in [Float(0), 0.01, 0.2, 0.5, 1.0] {
                let t = w(m, night: night)
                let before = IdleTable.weights(m, night: night, morning: 0, sleep: true, antics: false, music: false)
                _ = before
                let nw = t.filter { $0.kind != .wander }.reduce(0) { $0 + $1.weight }
                let wander = t.first { $0.kind == .wander }?.weight ?? 0
                let mine = kinds.map { k in t.first { $0.kind == k }?.weight ?? 0 }
                report += String(format: "%@ %.3f | %@ | %.3f | %.3f\n", "\(m)", night, mine.map { String(format: "%.3f", $0) }.joined(separator: " "), nw, wander)
                if night == 0 { XCTAssertTrue(mine.allSatisfy { $0 == 0 }, "\(m): a night kind is in the day table") }
                else { XCTAssertTrue(mine.allSatisfy { $0 > 0 }, "\(m) night \(night): every night kind has weight") }
                // "add, never displace": the table without the hook (share = 0) has the same weights for every existing kind; the table grows by <= 8 %
                let saved = NightEmoteTuning.share; NightEmoteTuning.share = 0
                let base = w(m, night: night); NightEmoteTuning.share = saved
                for e in base where e.kind != .wander { XCTAssertEqual(t.first { $0.kind == e.kind }?.weight ?? -1, e.weight, accuracy: 1e-6, "\(m) \(night): \(e.kind) weight changed") }
                let tb = base.reduce(0) { $0 + $1.weight }, tt = t.reduce(0) { $0 + $1.weight }
                XCTAssertLessThanOrEqual(tt, tb * 1.0801, "\(m) \(night): the table grew by more than 8 %")
                report += String(format: "   existing kinds keep %.1f %% of their picks (table %.3f -> %.3f)\n", 100 * tb / tt, tb, tt)
            }
        }
        // grumpy never gets them
        XCTAssertTrue(kinds.allSatisfy { k in !w(.grumpy, night: 1).contains { $0.kind == k } })
        try? report.write(toFile: Self.out + "table_weights.txt", atomically: true, encoding: .utf8)
    }

    func testEachKindCanBePickedAtNightAndNeverByDay() {
        for m in [IdleMood.happy, .okay] {
            for night in [Float(0.5), 1] {
                var seen = Set<IdleKind>()
                for i in 0..<4000 { seen.insert(IdleTable.pick(m, last: nil, r: Float(i) / 4000, night: night, morning: 0, sleep: true, antics: true, music: false)) }
                for k in kinds { XCTAssertTrue(seen.contains(k), "\(k) is never picked at night \(night) (\(m))") }
            }
            for i in 0..<4000 {
                let k = IdleTable.pick(m, last: nil, r: Float(i) / 4000, night: 0, morning: 0.3, sleep: true, antics: true, music: false)
                XCTAssertFalse(NightEmoteTuning.kindSet.contains(k), "\(k) picked by day")
            }
        }
    }

    private func play(_ kind: IdleKind, seed: UInt64 = 11, cancelAt: Float? = nil, hard: Bool = false) -> (rig: MotionRig, duration: Float) {
        let r = MotionRig(game: true)
        r.brain.seed = seed; r.brain.expr.enabled = false; r.brain.idleForced = true; r.brain.amplitude = 1
        r.brain.idleNight = 1
        XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) starts")
        let t0 = r.t
        if let c = cancelAt {
            r.run(c)
            XCTAssertNotNil(r.brain.idleState.kind, "\(kind) still running at \(c) s")
            if hard { r.brain.abortAll(r.sim, r.skinner) } else { r.brain.autonomy = false; r.brain.idleForced = false }          // (the gate yields it)
            r.run(2.0, until: { r.brain.idleState.kind == nil })
        } else {
            r.run(40, until: { r.brain.idleState.kind == nil })
        }
        return (r, r.t - t0)
    }

    private func assertFree(_ r: MotionRig, _ name: String) {
        XCTAssertNil(r.brain.idleState.kind, "\(name): ended")
        r.run(1.0)
        XCTAssertEqual(r.brain.mouthOpen, 0, "\(name): mouth")
        XCTAssertEqual(r.brain.armDirW, 0, "\(name): arms released")
        XCTAssertEqual(r.brain.runW, 0)
        XCTAssertGreaterThan(r.skinner.openness.left, 0.99, "\(name): eyes open")
        XCTAssertFalse(r.sim.hasNonFinite())
        if case .none = r.brain.script {} else { XCTFail("\(name): script not none") }
    }

    func testEachRunsEndsFreeAndCancelsCleanly() throws {
        var report = "kind | duration s (run to the end) | free after cancel (gate yield) | after hard abort\n"
        for k in kinds {
            let a = play(k)
            XCTAssertLessThan(a.duration, 30, "\(k) takes too long (\(a.duration) s)")
            XCTAssertGreaterThan(a.duration, 4, "\(k) is too short to be seen (\(a.duration) s)")
            assertFree(a.rig, "\(k) run")
            for (hard, name) in [(false, "yield"), (true, "abort")] {
                for at in [Float(1.5), 4.5, 7.5] {
                    let b = play(k, cancelAt: at, hard: hard)
                    if b.rig.brain.idleState.kind == nil || true { assertFree(b.rig, "\(k) \(name)@\(at)") }
                }
            }
            report += String(format: "%@ | %.1f | ok | ok\n", k.rawValue, a.duration)
        }
        try? report.write(toFile: Self.out + "run_cancel.txt", atomically: true, encoding: .utf8)
    }

    /// A goodnight while a night kind runs: asleep (lying, stage >= 2) as fast as from a plain sit (+ a small allowance).
    func testBedtimeOnTimeWithNightKindsRunning() throws {
        func secondsToBed(_ kind: IdleKind) -> Float {
            let r = MotionRig(game: true)
            r.brain.seed = 5; r.brain.expr.enabled = false; r.brain.amplitude = 1
            r.brain.sleepEnabled = true; r.brain.idleNight = 1; r.brain.idleDeepNight = 1; r.brain.idleForced = true
            XCTAssertTrue(r.brain.idleStart(kind, r.sim))
            r.run(4.0)
            r.brain.commandedGoodnight = true
            let t0 = r.t
            r.run(40, until: { r.brain.isNapping })
            XCTAssertTrue(r.brain.isNapping, "\(kind): never went to bed")
            return r.t - t0
        }
        let base = secondsToBed(.sit)
        var report = String(format: "sit baseline: %.1f s from goodnight to napping\n", base)
        for k in kinds {
            let s = secondsToBed(k)
            report += String(format: "%@: %.1f s\n", k.rawValue, s)
            XCTAssertLessThan(s, base + 3.0, "\(k): bedtime took \(s) s vs \(base) s from a sit")
        }
        try? report.write(toFile: Self.out + "bedtime.txt", atomically: true, encoding: .utf8)
    }

    // MARK: the room (three bodies, antics on, the real scheduler)

    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func room(hour: Double, seed: UInt64) -> RaceTripTests.Room {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        DayClock.shared.forcedHour = hour
        let r = RaceTripTests.Room(); Self.keep.append(r)
        for a in r.actors {
            guard let b = a.brain else { continue }
            b.sleepEnabled = true; b.autonomy = true; b.anticsEnabled = true; b.watching = true
            b.seed = seed &+ UInt64(a.id)
            b.socialOthers = { [unowned r] in r.actors.compactMap(\.brain) }
        }
        return r
    }
    private func stepRoom(_ r: RaceTripTests.Room) {
        for b in r.actors.compactMap(\.brain) { b.idleNight = DayClock.shared.nightFactor; b.idleMorning = DayClock.shared.morningFactor; b.idleDeepNight = DayClock.shared.deepNightFactor }
        r.step()
    }
    private func counts(hour: Double, minutes: Float, seed: UInt64) -> [IdleKind: Int] {
        NightRestTuning.idleBedtime = 100_000
        let r = room(hour: hour, seed: seed)
        for _ in 0..<Int(minutes * 3600) { stepRoom(r) }
        var c: [IdleKind: Int] = [:]
        for b in r.actors.compactMap(\.brain) { for (k, n) in b.idleState.counts { c[k, default: 0] += n } }
        return c
    }
    override func tearDown() { DayClock.shared.forcedHour = 12; NightRestTuning.idleBedtime = 180; DecorField.shared.clear(); super.tearDown() }

    func testRoomPicksThemAtNightAndNeverByDay() throws {
        let night = counts(hour: 20.5, minutes: 25, seed: 5)
        let day = counts(hour: 12, minutes: 25, seed: 5)
        var report = "kind | picks 20:30 (3 Jelmiko, 25 min) | picks 12:00\n"
        for k in kinds { report += "\(k.rawValue) | \(night[k] ?? 0) | \(day[k] ?? 0)\n" }
        report += "all picks night: \(night.values.reduce(0, +)), day: \(day.values.reduce(0, +))\n"
        try? report.write(toFile: Self.out + "room_counts.txt", atomically: true, encoding: .utf8)
        for k in kinds { XCTAssertEqual(day[k] ?? 0, 0, "\(k) by day") }
        XCTAssertGreaterThan(kinds.reduce(0) { $0 + (night[$1] ?? 0) }, 5, "the night kinds appear in the evening: \(report)")
    }

    func testIdleRuleBedtimeSameWithAndWithoutTheShare() throws {
        func toBed(share: Float) -> Float {
            let saved = NightEmoteTuning.share; NightEmoteTuning.share = share; defer { NightEmoteTuning.share = saved }
            NightRestTuning.idleBedtime = 30
            let r = room(hour: 23, seed: 7)
            var t: Float = 0
            while t < 150, !r.actors.compactMap(\.brain).allSatisfy({ $0.isNapping }) { stepRoom(r); t += 1.0 / 60 }
            return t
        }
        let a = toBed(share: 0.4), b = toBed(share: 0)
        try? "idle-rule bedtime to all napping: share 0.4 -> \(a) s, share 0 -> \(b) s\n".write(toFile: Self.out + "room_bedtime.txt", atomically: true, encoding: .utf8)
        XCTAssertLessThan(a, 150); XCTAssertLessThan(a, b + 6, "bedtime later with the night kinds: \(a) vs \(b)")
    }
}
