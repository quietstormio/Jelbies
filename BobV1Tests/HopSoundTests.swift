import XCTest
@testable import BobV1

/// 2026-11-06, "why no noises when they jump": the generic hop sound + landing thump + landing haptic (BlobBrain+HopSound.swift), before (detector off) vs after (on) on the SAME
/// seeds, counted past every guard (unmuted hub on the sim clock, no real audio).
@MainActor
final class HopSoundTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() {
        AudioHub.firedTap = nil; AudioHub.firedJellyTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() }; AudioHub.shared.atHome = false
        BlobBrain.hopEventTap = nil; HapticDriver.hopTap = nil; HopSoundTuning.enabled = true
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }
    nonisolated(unsafe) static var clockBase = 50_000.0
    struct Result {
        var played: [String: Int] = [:]; var genericJump = 0, genericLand = 0, takeoffs = 0, takeoffsSounded = 0, landings = 0, landingsSounded = 0
        var sleepEvents = 0, hapticTaps = 0, hapticSink = 0, maxTap: Float = 0, minHapticGap = 999.0, minutes = 0.0, jelbies = 0
        var heights: [Float] = []
    }

    func soak(n: Int, chars: [Int]?, on: Bool) -> Result {
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true; hub.atHome = true
        var simNow = Self.clockBase; AudioHub.clock = { simNow }
        defer { Self.clockBase = simNow + 120 }
        HopSoundTuning.enabled = on
        var res = Result(); res.jelbies = n
        var jumpLog: [(Int, Double)] = [], squishLog: [(Int, Double)] = []
        AudioHub.firedTap = { name in var k = name; if let r = k.range(of: #"_\d+$"#, options: .regularExpression) { k.removeSubrange(r) }; res.played[k, default: 0] += 1 }
        AudioHub.firedJellyTap = { sfx, j, generic in
            if generic { if sfx == "jump" { res.genericJump += 1 } else { res.genericLand += 1 } }
            if sfx == "jump" { jumpLog.append((j ?? -1, simNow)) }
            if sfx == "squish" { squishLog.append((j ?? -1, simNow)) }
        }
        let cueSink = RecordingHapticSink(); HapticDriver.room = HapticDriver(sinks: [cueSink]); HapticDriver.roomBusy = nil; HapticDriver.jitter = { 1 }
        HapticDriver.clock = { simNow }; HapticDriver.after = { _, f in f() }
        var lastTap = -999.0
        HapticDriver.hopTap = { i in res.hapticTaps += 1; res.maxTap = max(res.maxTap, i); res.minHapticGap = min(res.minHapticGap, simNow - lastTap); lastTap = simNow }
        defer { HapticDriver.room = nil; HapticDriver.hopTap = nil; HapticDriver.clock = { CACurrentMediaTime() }; HapticDriver.after = { d, f in DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } } }; HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) } }
        var lab: SocialTests.Lab!
        var takeoffAt: [(Int, Double)] = [], landAt: [(Int, Double)] = []
        BlobBrain.hopEventTap = { j, kind, v in
            if lab.rigs[j].brain.isSleeping { res.sleepEvents += 1 }
            if kind == "takeoff" { takeoffAt.append((j, simNow)); res.heights.append(v) } else { landAt.append((j, simNow)) }
        }
        let seeds = Array(RoomSFXCountTests.seeds.prefix(3))
        for seed in seeds {
            lab = SocialTests.Lab(n: n, quiet: false, seed: seed)
            for (i, r) in lab.rigs.enumerated() {
                r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = .happy; r.brain.restTimer = 0.5 + Float(i)
                if let c = chars, i < c.count { r.brain.feature = JellyRoster.feature(c[i]) }
            }
            for _ in 0..<(180 * 60) { lab.tick(); simNow += 1.0 / 60 }
            simNow += 60
        }
        // per event: did a sound for THAT Jelbie get played (take-off: a .jump within [-0.5 s, +0.1 s]; landing: a .squish within [0, +0.1 s])
        for (j, t) in takeoffAt { res.takeoffs += 1; if jumpLog.contains(where: { $0.0 == j && $0.1 >= t - 0.5 && $0.1 <= t + 0.1 }) { res.takeoffsSounded += 1 } }
        for (j, t) in landAt { res.landings += 1; if squishLog.contains(where: { $0.0 == j && $0.1 >= t - 0.001 && $0.1 <= t + 0.1 }) { res.landingsSounded += 1 } }
        res.hapticSink = cueSink.events.filter { $0.kind == .transient }.count
        res.minutes = Double(seeds.count) * 3
        return res
    }

    func report(_ label: String, n: Int, chars: [Int]?) {
        // the "before" run still measures the airborne events: detection runs in both, only the sound/haptic is off
        let before = soak(n: n, chars: chars, on: false), after = soak(n: n, chars: chars, on: true)
        func cnt(_ r: Result, _ k: String) -> Int { r.played[k, default: 0] }
        let jm = Double(n) * after.minutes
        func f(_ d: Double) -> String { String(format: "%.2f", d) }
        print("HOPSND \(label) PLAYED jump \(cnt(before, "jump")) -> \(cnt(after, "jump")) (per Jelbie-min \(f(Double(cnt(before, "jump")) / jm)) -> \(f(Double(cnt(after, "jump")) / jm))); squish \(cnt(before, "squish")) -> \(cnt(after, "squish")) (generic landings played \(after.genericLand), generic take-offs played \(after.genericJump)); per Jelbie-min landings played \(f(Double(after.genericLand) / jm))")
        print("HOPSND \(label) airborne events (after run): take-offs \(after.takeoffs) sounded \(after.takeoffsSounded) = \(f(100 * Double(after.takeoffsSounded) / Double(max(after.takeoffs, 1)))) %; landings \(after.landings) sounded \(after.landingsSounded) = \(f(100 * Double(after.landingsSounded) / Double(max(after.landings, 1)))) %; before run: take-offs \(before.takeoffs) sounded \(before.takeoffsSounded) = \(f(100 * Double(before.takeoffsSounded) / Double(max(before.takeoffs, 1)))) %")
        let hs = after.heights.sorted(); print("HOPSND \(label) first-frame heights cm: median \(hs.isEmpty ? 0 : hs[hs.count / 2] * 100) max \((hs.last ?? 0) * 100)")
        print("HOPSND \(label) haptics: landings \(after.landings) hop taps fired \(after.hapticTaps) (sink transients incl. other cues \(before.hapticSink) -> \(after.hapticSink)), max tap intensity \(after.maxTap), min gap between taps \(after.minHapticGap) s; sleeping events \(after.sleepEvents)")
        var others: [String] = []
        for (k, b) in before.played.sorted(by: { $0.key < $1.key }) where k != "jump" && k != "squish" && b >= 5 { let a = after.played[k, default: 0]; others.append("\(k) \(b)->\(a) (\(f(Double(a) / Double(b))))"); XCTAssertGreaterThanOrEqual(Double(a), 0.9 * Double(b), "\(label): \(k) \(a) vs \(b)") }
        let realSquishAfter = cnt(after, "squish") - after.genericLand
        others.append("squish(non-generic) \(cnt(before, "squish"))->\(realSquishAfter) (\(f(Double(realSquishAfter) / Double(max(cnt(before, "squish"), 1))))")
        print("HOPSND \(label) other sounds before->after: " + others.joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(Double(realSquishAfter), 0.9 * Double(cnt(before, "squish")), "\(label): squish displaced")
        XCTAssertGreaterThanOrEqual(cnt(after, "jump"), cnt(before, "jump"))
        XCTAssertGreaterThan(after.takeoffs, 20, "\(label): the soak sees hops")
        XCTAssertGreaterThanOrEqual(Double(after.takeoffsSounded), 0.9 * Double(after.takeoffs), "\(label): hops above 2.5 cm that got a sound")
        XCTAssertEqual(after.sleepEvents, 0, "\(label): no hop sound while asleep")
        XCTAssertGreaterThanOrEqual(after.minHapticGap, 0.25 - 1e-6, "\(label): hop haptics at least 0.25 s apart")
        XCTAssertLessThanOrEqual(after.maxTap, 0.4 + 1e-6)
        XCTAssertEqual(before.genericJump + before.genericLand, 0)
    }

    func testDefaultRoster() { report("default", n: 3, chars: nil) }
    func testTeddyPanda() { report("teddy+panda", n: 3, chars: [4, 6, 4]) }
}
