//
//  HangoutTests.swift
//  The six hangout emotes (2026-11-09, BlobBrain+Hangout.swift): each runs start to finish and returns to idle (upright, its haptic beats, its vocals), the gates (asleep / preview room / social /
//  request / night), no immediate repeat, no two Jelbies on the same kind, the guaranteed one-shot voice at the chirp's gain, and the soak table (before / after: the old kinds keep their rate,
//  chirps + context voices keep theirs, the standing share drops, every new kind occurs and its voice PLAYS). Feet staying attached is EmoteFeetTests / OnePieceInvariantTests via the idleTable row.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HangoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GroupEmoteFeetTests.reset(); DayClock.shared.forcedHour = 12
        BlobBrain.pickBudgetSeconds = .infinity; RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
    }
    override func tearDown() {
        EmoteTreats.requestTap = nil; AudioHub.requestTap = nil; AudioHub.dropTap = nil; AudioHub.firedTap = nil; AudioHub.firedVolumeTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }
        HangoutTuning.enabled = true
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds; ContactField.reset(); RoomLayout.dynamicBoxes = []
        GroupEmoteFeetTests.reset(); DayClock.shared.forcedHour = nil
        super.tearDown()
    }

    private func lab(n: Int = 1, seed: UInt64 = 31) -> SocialTests.Lab {
        let l = SocialTests.Lab(n: n, positions: Array(SocialTests.starts.prefix(n)), seed: seed)
        for r in l.rigs { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true }
        return l
    }

    static let wanted: [(IdleKind, [String], [String])] = [
        (.humTune, ["humTune.hum", "humTune.lala"], ["hangout:hum", "hangout:lala"]),
        (.curiousPeek, ["curiousPeek.lean", "curiousPeek.lean2"], ["hangout:ooh"]),
        (.bigStretch, ["bigStretch.top", "bigStretch.settle"], ["hangout:aww"]),
        (.tailPeek, ["tailPeek.huh", "tailPeek.shrug"], ["hangout:huh"]),
        (.pawCheck, ["pawCheck.raise", "pawCheck.nod"], ["hangout:ooh"]),
        (.bugWatch, ["bugWatch.eep", "bugWatch.hop"], ["hangout:eep", "hangout:giggle"]),
    ]

    // MARK: each emote

    func testEachHangoutRunsToTheEndAndStaysUpright() {
        for (kind, beats, voices) in Self.wanted {
            let l = lab()
            let r = l.rigs[0]
            r.brain.idleForced = true
            let hub = AudioHub.shared; hub._openForTest(); AudioHub.dryRun = true
            var simNow = 50_000.0; AudioHub.clock = { simNow }
            var haptics: [String] = [], asked: [String] = []
            EmoteTreats.requestTap = { haptics.append($0) }
            AudioHub.requestTap = { asked.append($0) }
            XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) starts")
            var f = 0, tilt: Float = 0, began = false, midOffCam: Float = 0
            while f < 60 * 14 {
                l.tick(); f += 1; simNow += 1.0 / 60
                tilt = max(tilt, r.sim.bodyPose(iterations: 4).tilt)
                if r.brain.idleState.kind != nil { began = true; if r.brain.idleState.phase == 1 { midOffCam = max(midOffCam, abs(wrapAngle(r.brain.yaw - r.brain.faceCameraYaw()))) } }
                if began, r.brain.idleState.kind == nil, f > 10 { break }
            }
            let secs = Float(f) / 60
            XCTAssertNil(r.brain.idleState.kind, "\(kind) returns to idle (\(secs) s)")
            XCTAssertGreaterThanOrEqual(secs, 2.5, "\(kind) takes 2.5 s or more"); XCTAssertLessThanOrEqual(secs, 7.5, "\(kind) takes under 7.5 s incl. the turn")
            XCTAssertLessThanOrEqual(tilt, 0.5, "\(kind): tilt \(tilt) rad")
            for h in beats { XCTAssertTrue(haptics.contains(h), "\(kind): haptic \(h) in \(haptics)") }
            for v in voices { XCTAssertTrue(asked.contains(v), "\(kind): voice \(v) asked in \(asked)") }
            XCTAssertGreaterThan(r.brain.hang.voices[kind, default: 0], 0, "\(kind): its voice PLAYED")
            XCTAssertGreaterThan(midOffCam, 0.3, "\(kind): never square to the camera (max |yaw - camera yaw| \(midOffCam))")
            XCTAssertEqual(r.brain.mouthOpen, 0, accuracy: 1e-5, "\(kind): mouth closed again")
            AudioHub.requestTap = nil; EmoteTreats.requestTap = nil; AudioHub.dryRun = false
        }
    }

    func testHangoutVoiceIsGuaranteedAndAtTheChirpsGain() {
        let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
        hub._openForTest(); AudioHub.dryRun = true
        var simNow = 60_000.0; AudioHub.clock = { simNow }
        var fired: [(String, Float)] = []
        AudioHub.firedVolumeTap = { fired.append(($0, $1)) }
        // a chirp, and straight after it (inside its 2.2 s hush and inside a context voice's gap) a hangout voice: it still plays, every time, at the same gain
        hub.chirp(jelly: 0, .happy)
        let chirpGain = fired.first?.1
        for k in 0..<20 {
            simNow += 0.5
            XCTAssertTrue(hub.hangoutVoice(jelly: 0, .hum), "play \(k)")
        }
        XCTAssertEqual(fired.count, 21)
        for f in fired.dropFirst() { XCTAssertEqual(f.1, chirpGain ?? -1, accuracy: 1e-6, "same gain as the chirp: \(f)"); XCTAssertTrue(f.0.hasPrefix("hum_jelly"), f.0) }
        // its self-hush is the chirp's: a chirp right after it waits
        fired = []
        simNow += 5; XCTAssertTrue(hub.hangoutVoice(jelly: 1, .ooh)); simNow += 1.0
        hub.chirp(jelly: 1, .happy)
        XCTAssertEqual(fired.count, 1, "an ambient chirp 1 s after it is hushed (2.2 s, not the emote's 6 s)")
        simNow += 2.3; hub.chirp(jelly: 1, .happy)
        XCTAssertEqual(fired.count, 2, "and plays 2.3 s after")
        // a context voice that is not a context voice is refused
        XCTAssertFalse(hub.hangoutVoice(jelly: 0, .happy))
        // muted: silent
        let muted = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: true)
        XCTAssertFalse(muted.hangoutVoice(jelly: 0, .hum))
    }

    // MARK: scheduler

    /// A one-Jelbie lab, autonomy off, standing, with the hangout clock armed.
    private func armed(_ l: SocialTests.Lab, _ i: Int = 0) -> BlobBrain {
        let b = l.rigs[i].brain
        b.autonomy = false
        var f = 0
        while f < 600, !b.treat2Free { l.tick(); f += 1 }
        XCTAssertFalse(b.hangoutMaybeStart(l.rigs[i].sim), "the first call only arms the clock")
        XCTAssertGreaterThan(b.hang.next, b.variety.now)
        b.hang.next = 0
        return b
    }

    func testGates() {
        // free: it starts
        do { let l = lab(); let b = armed(l); XCTAssertTrue(b.hangoutMaybeStart(l.rigs[0].sim)); XCTAssertTrue(BlobBrain.hangoutKinds.contains(b.idleState.kind ?? .wander)) }
        // asleep / locked
        do { let l = lab(); let b = armed(l); b.sleepLocked = true; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "sleepLocked") }
        do { let l = lab(); let b = armed(l); b.idleState.kind = .sleep; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "asleep") }
        // preview room
        do { let l = lab(); let b = armed(l); b.anticsEnabled = false; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "anticsEnabled off") }
        // a request / job / pending / commanded
        do { let l = lab(); let b = armed(l); b.job = .wave; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "job") }
        do { let l = lab(); let b = armed(l); b.pending = .wave; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "pending") }
        do { let l = lab(); let b = armed(l); b.commandedFlip = true; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "commanded") }
        // held / blocked (a meal, focus mode)
        do { let l = lab(); let b = armed(l); b.idleBlocked = true; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "blocked") }
        do { let l = lab(); let b = armed(l); b.reserved = true; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "reserved") }
        // disabled
        do { let l = lab(); let b = armed(l); HangoutTuning.enabled = false; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "disabled"); HangoutTuning.enabled = true }
        // race / volley
        do { let l = lab(); let b = armed(l); b.race.active = true; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "race"); b.race.active = false }
        // night: none from 0.6, and a longer gap below it
        do { let l = lab(); let b = armed(l); b.idleNight = 0.7; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "night 0.7") }
        do {
            let l = lab(); let b = armed(l); b.idleNight = 0.3
            XCTAssertTrue(b.hangoutMaybeStart(l.rigs[0].sim))
            let gap = b.hang.next - b.variety.now
            XCTAssertGreaterThanOrEqual(gap, 40 * 2.5 - 0.5); XCTAssertLessThanOrEqual(gap, 70 * 2.5 + 0.5)
        }
        // not due yet
        do { let l = lab(); let b = armed(l); b.hang.next = b.variety.now + 30; XCTAssertFalse(b.hangoutMaybeStart(l.rigs[0].sim), "not due") }
        // in a social
        do {
            let l = lab(n: 2); let a = armed(l, 0)
            a.autonomy = true; l.rigs[1].brain.autonomy = true
            if l.rigs[0].brain.socialStart(.boop, with: l.rigs[1].brain, l.rigs[0].sim) {
                a.hang.next = 0
                XCTAssertFalse(a.hangoutMaybeStart(l.rigs[0].sim), "in a social")
            }
        }
    }

    func testNoImmediateRepeatAndGapBetweenOnes() {
        let l = lab(); let b = armed(l)
        b.idleForced = true
        var kinds: [IdleKind] = []
        for _ in 0..<24 {
            b.hang.next = 0
            b.kindCool = [:]          // (the cooldown of the kind is the scheduler's own second guard; the clock's no-repeat is under test)
            var f = 0
            while f < 600, !b.treat2Free { l.tick(); f += 1 }
            XCTAssertTrue(b.hangoutMaybeStart(l.rigs[0].sim))
            XCTAssertGreaterThanOrEqual(b.hang.next - b.variety.now, 40 - 0.01)
            XCTAssertLessThanOrEqual(b.hang.next - b.variety.now, 70 + 0.01)
            kinds.append(b.idleState.kind ?? .wander)
            f = 0
            while f < 60 * 12, b.idleState.kind != nil { l.tick(); f += 1 }
        }
        for (x, y) in zip(kinds, kinds.dropFirst()) { XCTAssertNotEqual(x, y, "no immediate repeat: \(kinds)") }
        XCTAssertGreaterThanOrEqual(Set(kinds).count, 5, "the kinds vary: \(kinds)")
    }

    func testTwoJelbiesNeverStartTheSameKindTogether() {
        for seed in [3, 5, 9, 14] as [UInt64] {
            let l = lab(n: 3, seed: seed)
            let bs = (0..<3).map { armed(l, $0) }
            var started: [IdleKind] = []
            for (i, b) in bs.enumerated() { b.hang.next = 0; if b.hangoutMaybeStart(l.rigs[i].sim), let k = b.idleState.kind { started.append(k) } }
            XCTAssertEqual(started.count, Set(started).count, "seed \(seed): \(started)")
        }
    }

    // MARK: touch

    func testATouchRequestOverridesAHangoutEmote() {
        let l = lab(); let r = l.rigs[0]
        r.brain.autonomy = true
        XCTAssertTrue(r.brain.idleStart(.bigStretch, r.sim))
        for _ in 0..<60 { l.tick() }
        XCTAssertEqual(r.brain.idleState.kind, .bigStretch)
        r.brain.request(.wave)          // (a request meant for him: the same path a touch / a care request takes)
        for _ in 0..<30 { l.tick() }
        XCTAssertNotEqual(r.brain.idleState.kind, .bigStretch, "the request ended the emote")
        XCTAssertEqual(r.brain.armDirW, 0, accuracy: 0.6)
    }

    // MARK: the soak table (before / after)

    struct Soak {
        var idle: [String: Int] = [:], req: [String: Int] = [:], played: [String: Int] = [:], hangVoices: [String: Int] = [:]
        var standingTicks = 0, freeTicks = 0
        var standing: Double { freeTicks == 0 ? 0 : Double(standingTicks) / Double(freeTicks) }
        func sum(_ d: [String: Int], _ f: (String) -> Bool = { _ in true }) -> Int { d.filter { f($0.key) }.values.reduce(0, +) }
        var old: Int { idle.filter { !BlobBrain.hangoutKinds.contains(IdleKind(rawValue: String($0.key.dropFirst(5))) ?? .wander) }.values.reduce(0, +) }
    }

    static var simBase = 20_000.0
    static let soakSeeds: [UInt64] = RoomSFXCountTests.seeds + [67, 71, 83]          // (8 seeds: the families move +-25 % per random reshuffle at 5)
    static let oldGaps = (leg: Float(1.5)...Float(3.5), special: Float(1.0)...Float(2.5), pick: Float(3)...Float(6))
    static let newGaps = (leg: Float(1.0)...Float(2.5), special: Float(0.7)...Float(1.8), pick: Float(2.5)...Float(4.5))

    /// 8 seeds x 180 simulated seconds x 3 Jelbies (the RoomSFXCountTests rig): request taps, the PLAYED taps (past every guard, sim clock, no real audio), idle starts, the standing share.
    func soak(hangout: Bool, gaps: (leg: ClosedRange<Float>, special: ClosedRange<Float>, pick: ClosedRange<Float>)) -> Soak {
        var out = Soak()
        let (oldLeg, oldSpecial, oldPick) = (IdleTuning.restAfterLeg, IdleTuning.restAfterSpecial, IdleTuning.wanderPickWait)
        IdleTuning.restAfterLeg = gaps.leg; IdleTuning.restAfterSpecial = gaps.special; IdleTuning.wanderPickWait = gaps.pick
        HangoutTuning.enabled = hangout
        defer { IdleTuning.restAfterLeg = oldLeg; IdleTuning.restAfterSpecial = oldSpecial; IdleTuning.wanderPickWait = oldPick; HangoutTuning.enabled = true }
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        var simNow = Self.simBase; AudioHub.clock = { simNow }          // (the shared hub keeps its voice gaps between soaks: the clock only ever moves forward)
        defer { Self.simBase = simNow + 1000 }
        AudioHub.requestTap = { out.req[$0, default: 0] += 1 }
        AudioHub.dropTap = { what, why in if why == nil { out.played[what.components(separatedBy: "@")[0], default: 0] += 1 } }
        AudioHub.firedTap = { n in if n.hasPrefix("emote_") { var k = n; if let r = k.range(of: #"_\d+$"#, options: .regularExpression) { k.removeSubrange(r) }; out.played["file:" + k, default: 0] += 1 } }
        defer { AudioHub.requestTap = nil; AudioHub.dropTap = nil; AudioHub.firedTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() } }
        let cueSink = RecordingHapticSink(); HapticDriver.room = HapticDriver(sinks: [cueSink]); HapticDriver.roomBusy = nil; HapticDriver.jitter = { 1 }
        HapticDriver.clock = { simNow }; HapticDriver.after = { _, f in f() }
        defer { HapticDriver.room = nil; HapticDriver.clock = { CACurrentMediaTime() }; HapticDriver.after = { d, f in DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } } }; HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) } }
        for seed in Self.soakSeeds {
            let l = SocialTests.Lab(n: 3, quiet: false, seed: seed)
            for (i, r) in l.rigs.enumerated() { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = .happy; r.brain.restTimer = 0.5 + Float(i) }
            var last: [IdleKind?] = [nil, nil, nil]
            for _ in 0..<(180 * 60) {
                l.tick(watching: false); simNow += 1.0 / 60
                for (i, r) in l.rigs.enumerated() {
                    let b = r.brain, k = b.idleState.kind
                    if k != last[i] { if let k { out.idle["idle:\(k)", default: 0] += 1 }; last[i] = k }
                    if !b.isSleeping, b.social == nil {
                        out.freeTicks += 1
                        if k == nil, case .none = b.script { out.standingTicks += 1 }
                    }
                }
            }
            for r in l.rigs { for (k, v) in r.brain.hang.voices { out.hangVoices["\(k)", default: 0] += v } }
            simNow += 60
        }
        return out
    }

    func testSoakBeforeAfterTable() {
        let before = soak(hangout: false, gaps: Self.oldGaps)
        let hangOnly = soak(hangout: true, gaps: Self.oldGaps)
        let after = soak(hangout: true, gaps: Self.newGaps)
        func line(_ name: String, _ s: Soak) -> String {
            let chirps = s.sum(s.played) { $0.hasPrefix("chirp:") }, ctx = s.sum(s.played) { $0.hasPrefix("voice:") }, hang = s.sum(s.played) { $0.hasPrefix("hangout:") }, emoteV = s.sum(s.played) { $0.hasPrefix("file:emote_") }
            return "\(name): oldIdleStarts=\(s.old) chirpsPLAYED=\(chirps) ctxVoicesPLAYED=\(ctx) hangoutVoicesPLAYED=\(hang) emoteVoiceFiles=\(emoteV) standing=\(String(format: "%.3f", s.standing)) hangoutStarts=\(s.sum(s.idle) { BlobBrain.hangoutKinds.contains(IdleKind(rawValue: String($0.dropFirst(5))) ?? .wander) })"
        }
        var report = "HANGOUTSOAK 8 seeds x 180 s x 3 Jelbies\n" + [line("BEFORE (hangout off, old gaps)", before), line("HANGOUT-ONLY (old gaps)", hangOnly), line("AFTER (hangout on, new gaps)", after)].joined(separator: "\n") + "\n"
        let kinds = IdleKind.allCases.map { "idle:\($0)" }.filter { before.idle[$0] != nil || after.idle[$0] != nil || hangOnly.idle[$0] != nil }
        report += "kind | before | hangout-only | after | after/before\n"
        for k in kinds { let b = before.idle[k, default: 0], h = hangOnly.idle[k, default: 0], a = after.idle[k, default: 0]; report += "\(k) | \(b) | \(h) | \(a) | \(b > 0 ? String(format: "%.2f", Double(a) / Double(b)) : "new")\n" }
        report += "hangout voices PLAYED per kind (after): \(after.hangVoices.sorted { $0.key < $1.key })\n"
        report += "request counts before: \(before.req.filter { $0.key.hasPrefix("chirp:") || $0.key.hasPrefix("voice:") }.sorted { $0.key < $1.key })\n"
        report += "request counts after: \(after.req.filter { $0.key.hasPrefix("chirp:") || $0.key.hasPrefix("voice:") || $0.key.hasPrefix("hangout:") }.sorted { $0.key < $1.key })\n"
        print(report)
        try? report.write(toFile: ProcessInfo.processInfo.environment["HANGOUT_OUT"] ?? NSTemporaryDirectory() + "hangout_soak.txt", atomically: true, encoding: .utf8)

        // add, never displace: every old family keeps >= 90 % (the families, not the chaotic single kinds), in both the hangout-only and the final configuration
        for (name, s) in [("hangout-only", hangOnly), ("after", after)] {
            XCTAssertGreaterThanOrEqual(Double(s.old), 0.9 * Double(before.old), "\(name): every pre-existing idle kind together \(s.old) vs \(before.old)")
            let (bc, sc) = (before.sum(before.played) { $0.hasPrefix("chirp:") }, s.sum(s.played) { $0.hasPrefix("chirp:") })
            XCTAssertGreaterThanOrEqual(Double(sc), 0.9 * Double(bc), "\(name): chirps PLAYED \(sc) vs \(bc)")
            let (bv, sv) = (before.sum(before.played) { $0.hasPrefix("voice:") }, s.sum(s.played) { $0.hasPrefix("voice:") })
            XCTAssertGreaterThanOrEqual(Double(sv), 0.9 * Double(bv), "\(name): context voices PLAYED \(sv) vs \(bv)")
            let (be, se) = (before.sum(before.played) { $0.hasPrefix("file:emote_") }, s.sum(s.played) { $0.hasPrefix("file:emote_") })
            XCTAssertGreaterThanOrEqual(Double(se), 0.9 * Double(be), "\(name): emote voices \(se) vs \(be)")
        }
        // every new kind occurs, with its voice PLAYED
        for k in BlobBrain.hangoutKinds {
            XCTAssertGreaterThan(after.idle["idle:\(k)", default: 0], 0, "\(k) occurs")
            XCTAssertGreaterThan(after.hangVoices["\(k)", default: 0], 0, "\(k): its voice PLAYED")
        }
        XCTAssertEqual(before.sum(before.idle) { BlobBrain.hangoutKinds.contains(IdleKind(rawValue: String($0.dropFirst(5))) ?? .wander) }, 0)
        // standing: clearly lower once the gaps shrink (the target is about half)
        XCTAssertLessThan(after.standing, 0.8 * before.standing, "standing share \(after.standing) vs \(before.standing)")
    }
}
