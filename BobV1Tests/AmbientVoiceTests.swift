import XCTest
@testable import BobV1

/// 2026-11-05, "they need to make 30% more Jelbie noises while at home": the home silence filler (AmbientVoice.swift) on the seeded roaming soak, before (filler off) and after
/// (filler on) on the SAME seeds, played past every guard (unmuted hub on the sim clock, no real audio).
@MainActor
final class AmbientVoiceTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() {
        AudioHub.firedTap = nil; AudioHub.requestSrcTap = nil; AudioHub.requestTap = nil; HomeVoiceTuning.contextFloor = 0.45; AudioHub.dropTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }; AmbientVoiceTuning.enabled = true
        HomeVoiceTuning.enabled = true; HomeVoiceTuning.floorEnabled = true; AmbientVoiceTuning.newDaySet = true; SnoreScheduler.speedUp = 1.35; IdleTuning.treatGap = (200 / IdleTuning.treatSpeedUp)...(380 / IdleTuning.treatSpeedUp)
        AudioHub.shared.atHome = false
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// (below 10_000: RoomSFXCountTests.testPlayedRoomSounds starts the shared hub's clock at 10_000 and a LATER-than-that gap stamp would hush every sound there)
    nonisolated(unsafe) static var clockBase = 1_000.0
    struct Result { var played: [String: Int] = [:]; var voices = 0, newVoices = 0, ambientTags = 0, ctxReq = 0, jellyCount = 0; var drops: [String: Int] = [:]; var minVoiceGap = 999.0, minAnyGap = 999.0; var minutes = 0.0 }

    /// One soak: `n` Jelbies (features from `chars`), 3 seeds x 3 min, `situation` fed every 6 steps like the stage does (10 Hz).
    func soak(n: Int, chars: [Int]?, ambient: Bool, night: Bool = false, floor: Bool = true) -> Result {
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        var simNow = Self.clockBase; AudioHub.clock = { simNow }          // (one shared clock across soaks: the hub's per-sound gaps must see time only move forward)
        defer { Self.clockBase = simNow + 120 }
        AmbientVoiceTuning.enabled = ambient; HomeVoiceTuning.enabled = ambient; HomeVoiceTuning.floorEnabled = ambient && floor; AmbientVoiceTuning.newDaySet = ambient && floor        // (the whole home-voice boost: filler, context chance x1.3, emote treat gap, snore pace)
        IdleTuning.treatGap = ambient ? (200 / IdleTuning.treatSpeedUp)...(380 / IdleTuning.treatSpeedUp) : 200...380
        SnoreScheduler.speedUp = ambient ? 1.35 : 1
        let seeds = night ? Array(RoomSFXCountTests.seeds.prefix(1)) : Array(RoomSFXCountTests.seeds.prefix(3))          // (3 seeds x 3 min; the night soak 1)
        var res = Result()
        var lastByChar: [String: Double] = [:], lastAnyByChar: [String: Double] = [:]
        AudioHub.requestTap = { if $0.hasPrefix("voice:") { res.ctxReq += 1 } }
        AudioHub.dropTap = { what, why in if what.hasPrefix("voice:") || what.hasPrefix("chirp") || what.hasPrefix("babble") { res.drops["\(what)|\(why ?? "PLAYED")", default: 0] += 1 } }
        AudioHub.firedTap = { name in
            var k = name; if let r = k.range(of: #"_\d+$"#, options: .regularExpression) { k.removeSubrange(r) }
            res.played[k, default: 0] += 1
            let isVoice = name.hasPrefix("chirp_") || name.hasPrefix("babble_")
            let isContext = JellyVoice.allCases.contains { $0.isContext && name.hasPrefix("\($0.rawValue)_jelly") }
            if isVoice || isContext { res.voices += 1 }
            if ["giggle_", "curious_", "ooh_", "hum_", "hmm_", "wheee_"].contains(where: { name.hasPrefix($0) }) { res.newVoices += 1 }
            if isVoice || isContext, let r = name.range(of: #"jelly\d+"#, options: .regularExpression) {          // (any voice of one Jelbie: the design floor is the 1.0 s context gap)
                let who = String(name[r]); if let l = lastAnyByChar[who] { res.minAnyGap = min(res.minAnyGap, simNow - l) }; lastAnyByChar[who] = simNow
            }
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
        let nB = Double(before.newVoices), nA = Double(after.newVoices)
        print("AMBIENT \(label): new-sound voices (giggle+curious+ooh+hum) per 9 sim-min x \(n): before \(before.newVoices) after \(after.newVoices) (x\(String(format: "%.2f", nA / max(nB, 1)))); min gap any voice \(after.minAnyGap)")
        XCTAssertGreaterThanOrEqual(nA, 1.3 * nB, "\(label): giggle+curious+ooh+hum \(nA) vs \(nB)")
        // (by the existing design a context voice waits 1.0 s after a chirp, but a chirp waits only 0.5 s after a context voice: the floor for ANY pair is 0.5 s; the filler itself speaks only after 20 s of silence)
        XCTAssertGreaterThanOrEqual(after.minAnyGap, 0.5 - 1e-6, "\(label): two voices of one Jelbie closer than the 0.5 s context hush")
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

    /// 2026-11-06: context voices at home (floor 0.45 + the 50 % day mix) vs the 2230db85 behaviour (filler + x1.3, no floor, old mix), same seeds.
    func reportFloor(_ label: String, n: Int, chars: [Int]?) {
        let prev = soak(n: n, chars: chars, ambient: true, floor: false), now = soak(n: n, chars: chars, ambient: true, floor: true)
        let perPrev = Double(prev.newVoices) / Double(n) / prev.minutes, perNow = Double(now.newVoices) / Double(n) / now.minutes
        let totPrev = Double(prev.voices) / Double(n) / prev.minutes, totNow = Double(now.voices) / Double(n) / now.minutes
        let isV: (String) -> Bool = { n in n.hasPrefix("chirp_") || n.hasPrefix("babble_") || JellyVoice.allCases.contains { v in v.isContext && n.hasPrefix("\(v.rawValue)_jelly") } }
        let sumP = prev.played.filter { !isV($0.key) }.values.reduce(0, +), sumN = now.played.filter { !isV($0.key) }.values.reduce(0, +)
        print("CTXFLOOR \(label): context voices (giggle+curious+hmm+hum+wheee+ooh) per Jelbie per min: 2230db85 \(String(format: "%.3f", perPrev)) (\(prev.newVoices)) -> now \(String(format: "%.3f", perNow)) (\(now.newVoices)) x\(String(format: "%.2f", perNow / max(perPrev, 0.001)))")
        print("CTXFLOOR \(label): all vocals per Jelbie per min: \(String(format: "%.3f", totPrev)) -> \(String(format: "%.3f", totNow)); non-vocal sounds \(sumP) -> \(sumN); min any-voice gap off \(prev.minAnyGap) on \(now.minAnyGap), min chirp gap \(now.minVoiceGap)")
        let voices = ["happy", "babble", "giggle", "curious", "hum", "ooh", "hmm", "yawn", "sad"]
        func cnt(_ r: Result, _ v: String) -> Int { r.played.filter { $0.key.hasPrefix(v == "happy" ? "chirp_" : "\(v)_") }.values.reduce(0, +) }
        func chirpKind(_ r: Result, _ v: String) -> Int { cnt(r, v) }
        print("CTXFLOOR \(label) PLAYED per voice (off -> on, 3 seeds x 3 min, \(n) Jelbies): " + voices.map { "\($0) \(chirpKind(prev, $0))->\(chirpKind(now, $0))" }.joined(separator: ", "))
        for (nm, r) in [("off", prev), ("on", now)] {
            let reasons = ["PLAYED", "hush lastVoice", "hush context", "hush emote", "chance"]
            var line: [String] = []
            for v in voices where v != "happy" && v != "babble" {
                line.append("\(v)[" + reasons.map { "\($0.replacingOccurrences(of: "hush ", with: "h:"))=\(r.drops["voice:\(v)|\($0)", default: 0])" }.joined(separator: " ") + "]")
            }
            print("CTXFLOOR \(label) drops \(nm): " + line.joined(separator: "; "))
            print("CTXFLOOR \(label) ALLDROPS \(nm): " + r.drops.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))
        }
        for k in ["footstep", "jump", "squish", "boop", "wobble", "zoomies", "ring_chime"] {
            let kp = prev.played.filter { $0.key.hasPrefix(k) }.values.reduce(0, +), kn = now.played.filter { $0.key.hasPrefix(k) }.values.reduce(0, +)
            print("CTXFLOOR \(label) nonvoice \(k) \(kp)->\(kn)")
            if kp >= 100 { XCTAssertGreaterThanOrEqual(Double(kn), 0.9 * Double(kp), "\(label): \(k) \(kn) vs \(kp)") }
        }
        let each = ["giggle", "curious", "hum", "ooh", "hmm"].map { Double(cnt(now, $0)) / Double(n) / (now.minutes / 5) }
        print("CTXFLOOR \(label) per Jelbie per 5 min on: giggle/curious/hum/ooh/hmm = " + each.map { String(format: "%.2f", $0) }.joined(separator: " / "))
        XCTAssertGreaterThanOrEqual(perNow, 1.3 * perPrev, "\(label): context voices per Jelbie per minute \(perNow) vs \(perPrev)")
        XCTAssertGreaterThan(totNow, totPrev, "\(label): total vocals still rise")
        XCTAssertGreaterThanOrEqual(Double(sumN), 0.9 * Double(sumP), "\(label): non-vocal sounds \(sumN) vs \(sumP)")
        XCTAssertGreaterThanOrEqual(now.minAnyGap, 1.0 - 1e-6, "\(label): two voices of one Jelbie too close")
        XCTAssertGreaterThanOrEqual(now.minVoiceGap, 2.2 - 1e-6, "\(label): two chirps of one Jelbie within 2.2 s")
    }
    func testContextFloorDefaultRoster() { reportFloor("default3", n: 3, chars: nil) }
    func testContextFloorTeddyPanda() { reportFloor("teddy+panda", n: 2, chars: [JellyRoster.teddyID, JellyRoster.pandaID]) }
    /// (Sleepers get no ambient / day voices: testNoAmbientWhileAsleep below runs the night soak with the floor and the new mix on.)
    func testFloorMath() {
        XCTAssertEqual(HomeVoiceTuning.contextFloor, 0.45)
        XCTAssertEqual(HomeVoiceTuning.homeChance(0.15), 0.45)
        XCTAssertEqual(HomeVoiceTuning.homeChance(0.18), 0.45)
        XCTAssertEqual(HomeVoiceTuning.homeChance(0.4), 0.52, accuracy: 1e-9)
        XCTAssertEqual(HomeVoiceTuning.homeChance(0.05), 0.065, accuracy: 1e-9, "wander lala / pfft stay at x1.3")
        XCTAssertEqual(HomeVoiceTuning.homeChance(0.9), 1)
        var rnd = SystemRandomNumberGenerator(); var hush = 0
        for _ in 0..<2000 { if AmbientVoiceTuning.pick(night: 0, grumpy: false, random: { Double.random(in: $0, using: &rnd) }) == .hmm { hush += 1 } }
        XCTAssertGreaterThan(hush, 0)
        for _ in 0..<500 { XCTAssertNotEqual(AmbientVoiceTuning.pick(night: 0, grumpy: true, random: { Double.random(in: $0, using: &rnd) }), .giggle) }
    }

    func testHomeVocalsRiseDefaultRoster() { report("default3", n: 3, chars: nil) }
    func testHomeVocalsRiseTeddyPanda() { report("teddy+panda", n: 2, chars: [JellyRoster.teddyID, JellyRoster.pandaID]) }

    /// Night: the sleepers (put to bed at 10 s) never get an ambient chirp; an awake one may.
    func testNoAmbientWhileAsleep() { _ = soak(n: 3, chars: nil, ambient: true, night: true) }

    /// Snores (asleep only): the same napping Jelbies for two simulated hours, old pace vs new, on fresh hubs. Awake Jelbies never snore.
    func testSnoresMoreOftenAsleepOnly() {
        func run(speed: Double, napping: Bool) -> Int {
            SnoreScheduler.speedUp = speed
            let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
            hub._openForTest(); AudioHub.dryRun = true
            var now = 30_000.0; AudioHub.clock = { now }
            var snores = 0
            AudioHub.firedTap = { if $0.hasPrefix("snore_") { snores += 1 } }
            for _ in 0..<(7200 * 30) { hub.situation(napping: [napping, napping, napping], playing: false, xs: [-1, 0, 1], moods: [.okay, .okay, .okay]); now += 1.0 / 30 }
            return snores
        }
        defer { SnoreScheduler.speedUp = 1.35 }
        let before = run(speed: 1, napping: true), after = run(speed: 1.35, napping: true)
        print("SNORES 3 sleepers 120 sim-min: before \(before) after \(after) (x\(String(format: "%.2f", Double(after) / Double(max(before, 1)))))")
        XCTAssertGreaterThan(before, 100)
        XCTAssertGreaterThanOrEqual(Double(after), 1.3 * Double(before), "snores asleep: \(after) vs \(before)")
        XCTAssertEqual(run(speed: 1.35, napping: false), 0, "no snores while awake")
    }

    /// The scheduler alone: waits for the quiet roll, never two in one pass, retries when the room just voiced, and holds off after being ineligible.
    func testSchedulerRules() {
        var s = AmbientVoiceScheduler()
        let mid: (ClosedRange<Double>) -> Double = { ($0.lowerBound + $0.upperBound) / 2 }
        XCTAssertEqual(s.due(eligible: [true, true, true], since: [10, 10, 10], now: 100, night: 0, random: mid), [], "not quiet long enough (24 s needed)")
        XCTAssertEqual(s.due(eligible: [true, true, true], since: [40, 40, 40], now: 101, night: 0, random: mid), [0], "one slot per pass, never two at once")
        XCTAssertEqual(s.due(eligible: [true, true, true], since: [40, 40, 40], now: 101.1, night: 0, random: mid), [], "the others retry 1-2 s later, the first waits out afterFire")
        XCTAssertEqual(s.due(eligible: [true, true, true], since: [1, 40, 40], now: 104, night: 0, random: mid), [], "the room voiced 1 s ago: nobody speaks on top of it")
        var t = AmbientVoiceScheduler()
        XCTAssertEqual(t.due(eligible: [false, true, true], since: [99, 10, 10], now: 200, night: 0, random: mid), [])
        XCTAssertEqual(t.due(eligible: [true, true, true], since: [99, 10, 10], now: 201, night: 0, random: mid), [], "just woke / came home: 6 s hold-off")
        XCTAssertEqual(t.due(eligible: [true, true, true], since: [99, 10, 10], now: 207, night: 0, random: mid), [0])
        var u = AmbientVoiceScheduler()
        XCTAssertEqual(u.due(eligible: [true], since: [30], now: 300, night: 1, random: mid), [], "night: 24 x 1.5 = 36 s needed")
        XCTAssertEqual(u.due(eligible: [true], since: [40], now: 301, night: 1, random: mid), [0])
    }

    /// The home room's walking / running sounds play 1.3x (capped at 1); the park, race, cafe (any scene) and trips play the catalog volume; voices never change.
    func testHomeMoveSoundLevels() {
        let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
        hub._openForTest(); AudioHub.dryRun = true
        var now = 70_000.0; AudioHub.clock = { now }
        var vols: [String: Float] = [:]
        AudioHub.firedVolumeTap = { n, v in vols[n.replacingOccurrences(of: #"_\d+$"#, with: "", options: .regularExpression)] = v }
        defer { AudioHub.firedVolumeTap = nil }
        func play(_ s: SFX, volume: Float = 1) -> Float { vols = [:]; now += 5; hub.play(s, jelly: 0, x: 0, volume: volume); return vols[s.rawValue] ?? -1 }
        func voice() -> Float { vols = [:]; now += 5; hub.chirp(jelly: 0, .happy); return vols.first { $0.key.hasPrefix("chirp_") }?.value ?? -1 }
        let moves: [(SFX, Float)] = [(.footstep, 0.8), (.footstep, 1.2), (.zoomies, 1), (.squish, 1), (.wobble, 0.6), (.jump, 1), (.boop, 0.7)]
        for (s, v) in moves {
            hub.situation(napping: [], playing: false, xs: [], moods: [], home: false)
            let away = play(s, volume: v)
            hub.situation(napping: [], playing: false, xs: [], moods: [], home: true)
            XCTAssertTrue(hub.atHome)
            let home = play(s, volume: v)
            XCTAssertGreaterThan(away, 0)
            XCTAssertEqual(home, min(1, away * HomeMoveSoundTuning.gainMul), accuracy: 1e-5, "\(s) x\(v): home \(home) vs away \(away)")
            print("LEVEL \(s.rawValue) volume \(v): away \(away) home \(home)")
        }
        hub.situation(napping: [], playing: false, xs: [], moods: [], home: false)
        let voiceAway = voice()
        hub.situation(napping: [], playing: false, xs: [], moods: [], home: true)
        XCTAssertEqual(voice(), voiceAway, "chirps are not boosted")
        let chompHome = play(.chomp)
        hub.atHome = false
        XCTAssertEqual(chompHome, play(.chomp), "a non-movement sound is not boosted")
        for scene in [MusicScene.park, .cafe, .race, .raceFinal, .shop, .town] {
            hub.situation(napping: [], playing: false, xs: [], moods: [], scene: scene, home: true)
            XCTAssertFalse(hub.atHome, "\(scene) is not home")
        }
        hub.situation(napping: [], playing: false, xs: [], moods: [], home: false)
        XCTAssertFalse(hub.atHome, "a trip / bath (the stage passes home: false)")
    }
}
