//
//  YawnBedtimeTests.swift
//  Owner 2026-11-19: "random bug when the last one goes to sleep he yawns twice for no reason". The rule: from the moment a bedtime starts until he is asleep, each Jelmiko
//  yawns exactly once, one animation and one sound, whatever the source (bedtime yawn, sleepy idle yawn, contagious yawn, ambient voice).
//  `measure` counts, per bedtime, per Jelmiko in the order they fall asleep, every yawn animation start and every yawn sound that PLAYED past the audio guards
//  (AudioHub.firedTap, dry run, sim clock), tagged by source.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class YawnBedtimeTests: XCTestCase {
    private var savedHour: Double?
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); SleepOrder.reset()
        savedHour = DayClock.shared.forcedHour
        DayClock.shared.forcedHour = 23
    }
    override func tearDown() {
        DayClock.shared.forcedHour = savedHour
        AudioHub.firedTap = nil; AudioHub.requestSrcTap = nil; AudioHub.dropTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }
        AudioHub.shared.atHome = false
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); SleepOrder.reset()
    }

    nonisolated(unsafe) static var clockBase = 2_000.0
    static let seeds: [UInt64] = Array(1...20).map { UInt64($0) * 13 + 5 }
    static let sources = ["bed1", "bed2", "idle", "react", "ambient", "other"]

    struct Bedtime {
        var anim: [[String: Int]]          // by sleeper order (0 = first asleep)
        var sound: [[String: Int]]
        var asleepOrder: [Int]
        var allAsleep = true
    }

    /// `natural`: no Bedtime order; each Jelmiko goes to sleep by his own night rule (the last one up sees the others fall asleep). The count window per Jelmiko is
    /// [his own sleep start - 15 s, asleep]; with the Bedtime order it is the whole run (everybody starts at 0).
    func measure(seed: UInt64, natural: Bool = false) -> Bedtime {          // natural = a STRAGGLER: two are sent to bed at once, the third 4...13.6 s later (busy / woken / held: the NightRest retry), re-sent every 3 s, lively beforehand
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        var simNow = Self.clockBase; AudioHub.clock = { simNow }
        defer { Self.clockBase = simNow + 120 }
        let lab = SocialTests.Lab(quiet: false, seed: seed)
        let brains = lab.rigs.map(\.brain)
        for r in lab.rigs {
            r.brain.sleepEnabled = true; r.brain.watching = true
            r.brain.idleNight = 1; r.brain.idleDeepNight = 1
            r.brain.idleState.cooldown = 0; r.brain.restTimer = 0.5; r.brain.socialBook.cooldown = 1e6
        }
        var ambientSlot: Int?
        var soundsThisTick: [Int?] = []          // ambient slot (nil = not ambient) per yawn sound that played this tick
        AudioHub.requestSrcTap = { what, slot in if what == "voice:yawn@ambient" { ambientSlot = slot } }
        AudioHub.firedTap = { name in if name.hasPrefix("yawn_") { soundsThisTick.append(ambientSlot); ambientSlot = nil } }
        func feed() {
            hub.situation(napping: brains.map { $0.isNapping }, playing: false, xs: brains.map { $0.px }, moods: brains.map { _ in .happy }, home: true,
                          ambient: brains.map { $0.ambientVoiceOK }, walking: brains.map { $0.activity == .walking || $0.activity == .coming }, night: 1)
        }
        for t in 0..<(natural ? 300 + Int(seed % 5) * 70 : 120) { lab.tick(watching: false); simNow += 1.0 / 60; if t % 6 == 0 { feed() } }
        // (the pre-bedtime warm-up above may play a yawn: the count starts at the order)
        var anim = [[String: Int]](repeating: [:], count: 3), sound = anim
        var asleepAt = [Float?](repeating: nil, count: 3)
        var seen1 = [Bool](repeating: false, count: 3), seen2 = seen1
        var wasYawnIdle = [Bool](repeating: false, count: 3)
        var soundLog: [(Int, String)] = []          // per brain index: source (before sleeper ordering)
        var animIdx = [[String: Int]](repeating: [:], count: 3), soundIdx = animIdx
        var retryT = [Float](repeating: 0, count: 3)
        var mouthUp = [Bool](repeating: false, count: 3), bedEdges = [0, 0, 0]
        var yawn2Seen = [Bool](repeating: false, count: 3)
        if !natural { NightRestTuning.sendToBed(brains) }
        var sleepStart = [Float?](repeating: nil, count: 3)
        var ev: [(t: Float, i: Int, kind: String, isSound: Bool)] = []
        let dt: Float = 1.0 / 60
        var t: Float = 0
        while t < (natural ? 200 : 45), !(asleepAt.allSatisfy { $0 != nil }) {
            soundsThisTick = []
            if natural { for (i, b) in brains.enumerated() where !b.isSleeping && t >= (i == 2 ? 4 + Float(seed % 7) * 1.6 : 0) { retryT[i] -= dt; if retryT[i] <= 0 { b.commandedGoodnight = true; retryT[i] = NightRestTuning.retry } } }
            lab.tick(watching: false); simNow += Double(dt); t += dt
            var yawnStarters: [Int] = []
            for (i, b) in brains.enumerated() {
                if asleepAt[i] != nil { continue }
                let s = b.sleep
                if sleepStart[i] == nil, b.idleState.kind == .sleep { sleepStart[i] = t }
                if s.yawn2 && s.staggerSet { yawn2Seen[i] = true }
                if b.mouthOpen > 0.3, !mouthUp[i] {          // (the animation itself: a rising edge of the mouth, tagged by what he is doing)
                    mouthUp[i] = true
                    if b.idleState.kind == .sleep, s.stage == 1, s.turned { bedEdges[i] += 1; ev.append((t, i, bedEdges[i] == 1 ? "bed1" : "bed2", false)) }
                    else if b.idleState.kind == nil || b.idleState.kind == .sleep || b.idleState.kind == .stretch { ev.append((t, i, "other", false)); print("YAWNOTHER seed \(seed) \(natural ? "straggler" : "order") brain \(i) t \(t) kind \(String(describing: b.idleState.kind)) activity \(b.activity) mouth \(b.mouthOpen) stage \(s.stage)") }          // (an idle yawn is counted by its own start below; a playful open mouth in another move, e.g. a scoot, is not a yawn)
                } else if b.mouthOpen < 0.1 { mouthUp[i] = false }
                let y = b.idleState.kind == .yawn
                if y, !wasYawnIdle[i] { yawnStarters.append(i); ev.append((t, i, b.idleState.reaction == .yawn ? "react" : "idle", false)) }
                wasYawnIdle[i] = y
            }
            for a in soundsThisTick {
                if let a, a < 3 { ev.append((t, a, "ambient", true)) }
                else if let i = yawnStarters.first { ev.append((t, i, brains[i].idleState.reaction == .yawn ? "react" : "idle", true)) }
                else { ev.append((t, 0, "other", true)) }          // (unattributed: put on slot 0's "other"; none expected)
            }
            if Int(t * 60) % 6 == 0 { feed() }
            for (i, b) in brains.enumerated() where asleepAt[i] == nil && b.isNapping { asleepAt[i] = t }
        }
        for e in ev {
            let from = (sleepStart[e.i] ?? 0) - (natural ? 15 : 1000), to = asleepAt[e.i] ?? 1e9
            guard e.t >= from, e.t <= to + 0.001 else { continue }
            if e.isSound { soundIdx[e.i][e.kind, default: 0] += 1 } else { animIdx[e.i][e.kind, default: 0] += 1 }
        }
        let order = (0..<3).sorted { (asleepAt[$0] ?? 99) < (asleepAt[$1] ?? 99) }
        for (rank, i) in order.enumerated() { anim[rank] = animIdx[i]; sound[rank] = soundIdx[i] }
        _ = soundLog
        MotionLog.write("YAWNSEED \(natural ? "natural" : "order") seed \(seed) yawn2 \(yawn2Seen) asleep \(asleepAt.map { $0.map { String(format: "%.1f", $0) } ?? "-" })")
        return Bedtime(anim: anim, sound: sound, asleepOrder: order, allAsleep: asleepAt.allSatisfy { $0 != nil })
    }

    private func table(_ runs: [Bedtime]) -> String {
        var out = "YAWNTABLE bedtimes \(runs.count) all asleep \(runs.filter { $0.allAsleep }.count)\n"
        for rank in 0..<3 {
            var a: [String: Int] = [:], s: [String: Int] = [:], a1 = 0, s1 = 0, aBad = 0, sBad = 0
            for r in runs {
                for (k, v) in r.anim[rank] { a[k, default: 0] += v }
                for (k, v) in r.sound[rank] { s[k, default: 0] += v }
                let na = r.anim[rank].values.reduce(0, +), ns = r.sound[rank].values.reduce(0, +)
                a1 += na; s1 += ns; if na != 1 { aBad += 1 }; if ns != 1 { sBad += 1 }
            }
            let n = Double(runs.count)
            out += "  sleeper \(rank + 1): anim/bedtime \(String(format: "%.2f", Double(a1) / n)) \(Self.sources.map { "\($0)=\(a[$0, default: 0])" }.joined(separator: " ")) | bedtimes != 1: \(aBad)\n"
            out += "              sound/bedtime \(String(format: "%.2f", Double(s1) / n)) \(Self.sources.map { "\($0)=\(s[$0, default: 0])" }.joined(separator: " ")) | bedtimes != 1: \(sBad)\n"
        }
        return out
    }

    /// The measuring run (prints the 20 + 20 bedtime table; no assertions, so it also runs on a build where the rule is false).
    func testPrintYawnTable() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YAWN_TABLE"] != nil, "the 40-bedtime table (about 7 min): run with TEST_RUNNER_YAWN_TABLE=1")
        let text = table(Self.seeds.map { measure(seed: $0) }) + "STRAGGLER (third sent to bed 4-13.6 s after the first two)\n" + table(Self.seeds.map { measure(seed: $0, natural: true) })
        print(text)
        MotionLog.write(text)
    }

    /// Positive control: the sound tap really sees a played yawn (so a 0 in the table is a real 0).
    func testSoundTapSeesAnIdleYawn() {
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        var simNow = Self.clockBase; AudioHub.clock = { simNow }
        defer { Self.clockBase = simNow + 120 }
        var played = 0
        AudioHub.firedTap = { if $0.hasPrefix("yawn_") { played += 1 } }
        let lab = SocialTests.Lab(quiet: true, seed: 3)
        hub.situation(napping: [false, false, false], playing: false, xs: [0, 0, 0], moods: [.happy, .happy, .happy], home: true, night: 1)
        for _ in 0..<40 where played == 0 {
            let b = lab.rigs[0].brain
            b.idleFinish(lab.rigs[0].skinner); b.abortScript(lab.rigs[0].sim, lab.rigs[0].skinner)
            _ = b.idleStart(.yawn, lab.rigs[0].sim)
            for _ in 0..<60 { lab.tick(watching: false); simNow += 1.0 / 60 }
            simNow += 5
        }
        XCTAssertGreaterThan(played, 0, "an idle yawn's voice reaches firedTap")
    }

    /// The rule: every sleeper, every bedtime (both paths): exactly one yawn animation and never more than one yawn sound, from any source.
    func testEverySleeperYawnsExactlyOnce() {
        let runs = Self.seeds.prefix(8).map { measure(seed: $0) } + Self.seeds.prefix(4).map { measure(seed: $0, natural: true) }
        print(table(runs))
        for (n, r) in runs.enumerated() {
            XCTAssertTrue(r.allAsleep, "bedtime \(n): all three fall asleep")
            for rank in 0..<3 {
                XCTAssertEqual(r.anim[rank].values.reduce(0, +), 1, "bedtime \(n) sleeper \(rank + 1): yawn animations \(r.anim[rank])")
                XCTAssertLessThanOrEqual(r.sound[rank].values.reduce(0, +), 1, "bedtime \(n) sleeper \(rank + 1): yawn sounds \(r.sound[rank]) (the bedtime yawn itself has no voice, so at most one)")
            }
        }
    }
}
