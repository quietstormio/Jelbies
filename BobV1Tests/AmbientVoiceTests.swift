import XCTest
@testable import BobV1

/// 2026-11-05, "they need to make 30% more Jelbie noises while at home": the home silence filler (AmbientVoice.swift) on the seeded roaming soak, before (filler off) and after
/// (filler on) on the SAME seeds, played past every guard (unmuted hub on the sim clock, no real audio).
@MainActor
final class AmbientVoiceTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() {
        AudioHub.firedTap = nil; AudioHub.requestSrcTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }; AmbientVoiceTuning.enabled = true
        AudioHub.shared.atHome = false
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// (below 10_000: RoomSFXCountTests.testPlayedRoomSounds starts the shared hub's clock at 10_000 and a LATER-than-that gap stamp would hush every sound there)
    nonisolated(unsafe) static var clockBase = 1_000.0
    struct Result { var played: [String: Int] = [:]; var voices = 0, ambientTags = 0; var minVoiceGap = 999.0; var minutes = 0.0 }

    /// One soak: `n` Jelbies (features from `chars`), 3 seeds x 3 min, `situation` fed every 6 steps like the stage does (10 Hz).
    func soak(n: Int, chars: [Int]?, ambient: Bool, night: Bool = false) -> Result {
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        var simNow = Self.clockBase; AudioHub.clock = { simNow }          // (one shared clock across soaks: the hub's per-sound gaps must see time only move forward)
        defer { Self.clockBase = simNow + 120 }
        AmbientVoiceTuning.enabled = ambient
        let seeds = night ? Array(RoomSFXCountTests.seeds.prefix(1)) : Array(RoomSFXCountTests.seeds.prefix(3))          // (3 seeds x 3 min; the night soak 1)
        var res = Result()
        var lastByChar: [String: Double] = [:]
        AudioHub.firedTap = { name in
            var k = name; if let r = k.range(of: #"_\d+$"#, options: .regularExpression) { k.removeSubrange(r) }
            res.played[k, default: 0] += 1
            let isVoice = name.hasPrefix("chirp_") || name.hasPrefix("babble_")
            let isContext = JellyVoice.allCases.contains { $0.isContext && name.hasPrefix("\($0.rawValue)_jelly") }
            if isVoice || isContext { res.voices += 1 }
            if isVoice, let r = name.range(of: #"jelly\d+"#, options: .regularExpression) {          // (chirp / babble: the 2.2 s per-Jelbie gap is a hard guard)
                let who = String(name[r]); if let l = lastByChar[who] { res.minVoiceGap = min(res.minVoiceGap, simNow - l) }; lastByChar[who] = simNow
            }
        }
        let cueSink = RecordingHapticSink(); HapticDriver.room = HapticDriver(sinks: [cueSink]); HapticDriver.roomBusy = nil; HapticDriver.jitter = { 1 }
        HapticDriver.clock = { simNow }; HapticDriver.after = { _, f in f() }
        defer { HapticDriver.room = nil; HapticDriver.clock = { CACurrentMediaTime() }; HapticDriver.after = { d, f in DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } } }; HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) } }
        for seed in seeds {
            let lab = SocialTests.Lab(n: n, quiet: false, seed: seed)
            for (i, r) in lab.rigs.enumerated() {
                r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = .happy; r.brain.restTimer = 0.5 + Float(i)
                if let c = chars, i < c.count { r.brain.feature = JellyRoster.feature(c[i]) }
                if night { r.brain.idleNight = 1 }
            }
            var sleepers = 0, violations = 0
            AudioHub.requestSrcTap = { what, slot in
                guard what.hasSuffix("@ambient") else { return }
                res.ambientTags += 1
                if slot < lab.rigs.count, !lab.rigs[slot].brain.ambientVoiceOK { violations += 1 }
            }
            for t in 0..<(180 * 60) {
                if night, t == 600 { for r in lab.rigs.prefix(2) { if r.brain.idleState.kind == nil { _ = r.brain.idleStart(.sleep, r.sim) } } }
                lab.tick(); simNow += 1.0 / 60
                if t % 6 == 0 {
                    let napping = lab.rigs.map { $0.brain.isNapping }
                    if night, t > 1800 { sleepers = max(sleepers, lab.rigs.filter { $0.brain.idleState.kind == .sleep }.count) }
                    hub.situation(napping: napping, playing: false, xs: lab.rigs.map { $0.brain.px }, moods: lab.rigs.map { _ in .happy }, home: true,
                                  ambient: lab.rigs.map { $0.brain.ambientVoiceOK }, night: night ? 1 : 0)
                }
            }
            if night { XCTAssertGreaterThan(sleepers, 0, "the night soak has sleepers (seed \(seed))"); XCTAssertEqual(violations, 0, "ambient chirp from a sleeping / held Jelbie (seed \(seed))") }
            simNow += 60          // (the gaps of the previous run are over)
        }
        res.minutes = Double(seeds.count) * 3
        return res
    }

    func report(_ label: String, n: Int, chars: [Int]?) {
        let before = soak(n: n, chars: chars, ambient: false), after = soak(n: n, chars: chars, ambient: true)
        let perB = Double(before.voices) / Double(n) / before.minutes, perA = Double(after.voices) / Double(n) / after.minutes
        print("AMBIENT \(label): vocals/Jelbie/min before \(String(format: "%.2f", perB)) after \(String(format: "%.2f", perA)) (x\(String(format: "%.2f", perA / max(perB, 0.001)))); ambient requests \(after.ambientTags); min chirp gap \(after.minVoiceGap)")
        var others: [String] = []
        // (single rare kinds are chaotic run to run: wobble 20 vs 13 with the filler off in both; so the 90 % gate is on the sum of every non-voice sound and on the big kinds)
        let isV: (String) -> Bool = { n in n.hasPrefix("chirp_") || n.hasPrefix("babble_") || JellyVoice.allCases.contains { v in v.isContext && n.hasPrefix("\(v.rawValue)_jelly") } }
        for (k, b) in before.played.sorted(by: { $0.key < $1.key }) where !isV(k) && b >= 5 {
            let a = after.played[k, default: 0]; others.append("\(k) \(b)->\(a)")
            if b >= 100 { XCTAssertGreaterThanOrEqual(Double(a), 0.9 * Double(b), "\(label): \(k) \(a) vs \(b)") }
        }
        let sumB = before.played.filter { !isV($0.key) }.values.reduce(0, +), sumA = after.played.filter { !isV($0.key) }.values.reduce(0, +)
        others.append("ALL non-voice \(sumB)->\(sumA)")
        XCTAssertGreaterThanOrEqual(Double(sumA), 0.9 * Double(sumB), "\(label): every other sound together \(sumA) vs \(sumB)")
        print("AMBIENT \(label) other sounds per 15 sim-min: " + others.joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(perA, 1.3 * perB, "\(label): vocals per Jelbie per minute \(perA) vs \(perB)")
        XCTAssertGreaterThanOrEqual(after.minVoiceGap, 2.2 - 1e-6, "\(label): two chirps / babbles of one Jelbie within 2.2 s")
        XCTAssertEqual(before.ambientTags, 0)
    }

    func testHomeVocalsRiseDefaultRoster() { report("default3", n: 3, chars: nil) }
    func testHomeVocalsRiseTeddyPanda() { report("teddy+panda", n: 2, chars: [JellyRoster.teddyID, JellyRoster.pandaID]) }

    /// Night: the sleepers (put to bed at 10 s) never get an ambient chirp; an awake one may.
    func testNoAmbientWhileAsleep() { _ = soak(n: 3, chars: nil, ambient: true, night: true) }

    /// The scheduler alone: waits for the quiet roll, never two in one pass, retries when the room just voiced, and holds off after being ineligible.
    func testSchedulerRules() {
        var s = AmbientVoiceScheduler()
        let mid: (ClosedRange<Double>) -> Double = { ($0.lowerBound + $0.upperBound) / 2 }
        XCTAssertEqual(s.due(eligible: [true, true, true], since: [10, 10, 10], now: 100, night: 0, random: mid), [], "not quiet long enough (26 s needed)")
        XCTAssertEqual(s.due(eligible: [true, true, true], since: [40, 40, 40], now: 101, night: 0, random: mid), [0], "one slot per pass, never two at once")
        XCTAssertEqual(s.due(eligible: [true, true, true], since: [40, 40, 40], now: 101.1, night: 0, random: mid), [], "the others retry 1-2 s later, the first waits out afterFire")
        XCTAssertEqual(s.due(eligible: [true, true, true], since: [1, 40, 40], now: 104, night: 0, random: mid), [], "the room voiced 1 s ago: nobody speaks on top of it")
        var t = AmbientVoiceScheduler()
        XCTAssertEqual(t.due(eligible: [false, true, true], since: [99, 10, 10], now: 200, night: 0, random: mid), [])
        XCTAssertEqual(t.due(eligible: [true, true, true], since: [99, 10, 10], now: 201, night: 0, random: mid), [], "just woke / came home: 6 s hold-off")
        XCTAssertEqual(t.due(eligible: [true, true, true], since: [99, 10, 10], now: 207, night: 0, random: mid), [0])
        var u = AmbientVoiceScheduler()
        XCTAssertEqual(u.due(eligible: [true], since: [30], now: 300, night: 1, random: mid), [], "night: 26 x 1.5 = 39 s needed")
        XCTAssertEqual(u.due(eligible: [true], since: [40], now: 301, night: 1, random: mid), [0])
    }
}
