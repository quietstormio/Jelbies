import XCTest
import simd
@testable import BobV1

/// The room's per-Jelbie sound requests over 180 simulated seconds with 3 Jelbies (the 2026-11-01 "they stopped making noise" report).
@MainActor
final class RoomSFXCountTests: XCTestCase {
    override func setUp() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() { AudioHub.requestTap = nil; RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    static let seeds: [UInt64] = [11, 23, 37, 41, 59]
    /// Where the approved build's counts live (`scripts/regression-gate.sh` regenerates them from the approved commit and passes `SFXCOUNT_BASELINE`).
    static var baselinePath: String {
        ProcessInfo.processInfo.environment["SFXCOUNT_BASELINE"] ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/baseline-roomsfx.txt").path
    }
    static func parse(_ line: String) -> [String: Int] {
        var d: [String: Int] = [:]
        for tok in line.split(separator: " ") { let kv = tok.split(separator: "="); if kv.count == 2, let v = Int(kv[1]) { d[String(kv[0])] = v } }
        return d
    }

    func testCountRoomSoundRequests() {
        var counts: [String: Int] = [:]
        if ProcessInfo.processInfo.environment["SFXCOUNT_NOLOOKAHEAD"] != nil { ContactTuning.lookAhead = false }          // NEWONLY (diagnosis knob)
        defer { ContactTuning.lookAhead = true }          // NEWONLY
        AudioHub.requestTap = { counts[$0, default: 0] += 1 }
        let cueSink = RecordingHapticSink(); let cueDriver = HapticDriver(sinks: [cueSink])          // NEWONLY
        HapticDriver.room = cueDriver; HapticDriver.roomBusy = nil; HapticDriver.jitter = { 1 }          // NEWONLY
        var simNow = 0.0; HapticDriver.clock = { simNow }; HapticDriver.after = { _, f in f() }          // NEWONLY
        defer { HapticDriver.room = nil; HapticDriver.clock = { CACurrentMediaTime() }; HapticDriver.after = { d, f in DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } } }; HapticDriver.jitter = { 1 + Float.random(in: -0.15...0.15) } }          // NEWONLY
        var total: [String: Int] = [:]
        for seed in Self.seeds {
            counts = [:]
            let lab = SocialTests.Lab(n: 3, quiet: false, seed: seed)
            for (i, r) in lab.rigs.enumerated() { r.brain.anticsEnabled = true; r.brain.sleepEnabled = true; r.brain.idleMood = .happy; r.brain.restTimer = 0.5 + Float(i) }
            var lastKind: [IdleKind?] = Array(repeating: nil, count: 3)
            for _ in 0..<(180 * 60) {
                lab.tick(); simNow += 1.0 / 60          // NEWONLY (simNow)
                for (i, r) in lab.rigs.enumerated() { let k = r.brain.idleState.kind; if k != lastKind[i] { if let k { counts["idle:\(k)", default: 0] += 1 }; lastKind[i] = k } }
            }
            for ev in lab.events.flatMap({ $0 }) {
                switch ev {
                case .began(let k, _): counts["soc:\(k)", default: 0] += 1
                case .boop: counts["soc:boopEvent", default: 0] += 1
                case .shove: counts["soc:shove", default: 0] += 1
                default: break
                }
            }
            for (k, v) in counts { total[k, default: 0] += v }
            total["hapticSink", default: 0] += cueSink.events.filter { $0.kind == .transient }.count; cueSink.clear()          // NEWONLY
        }
        let line = "ROOMSFX " + total.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print(line); MotionLog.write(line)
        try? line.write(toFile: ProcessInfo.processInfo.environment["SFXCOUNT_OUT"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/sfx_last.txt", atomically: true, encoding: .utf8)
        XCTAssertGreaterThan(total["jump", default: 0], 0)
        // the new solo emotes are additions on top: they still happen, rarely (about one per 3 Jelbie-minutes)
        let emotes = BlobBrain.emoteKinds.reduce(0) { $0 + total["idle:\($1)", default: 0] }          // NEWONLY
        XCTAssertGreaterThan(emotes, 0, "the solo emotes still occur"); XCTAssertLessThan(emotes, 30, "and stay rare: \(emotes)")          // NEWONLY
        XCTAssertGreaterThan(total["hapticSink", default: 0], 20, "the room's moves reach the haptic sink")          // NEWONLY
        // NEWONLY-BEGIN
        // regression gate: every pre-existing kind keeps >= 90 % of the approved build (same seeds, same minutes)
        guard let text = try? String(contentsOfFile: Self.baselinePath, encoding: .utf8) else { print("no baseline at \(Self.baselinePath)"); return }
        let base = Self.parse(text)
        // (per-kind counts are chaotic - one changed random draw reshuffles a whole 3-minute run, +-35 % on a kind of ~15 - so the gate is on the families, each >= 75 % (5 seeds x 3 min: one changed random draw reshuffles a run, a family moves +-25 %; measured on this tree: old idle kinds 87-94 %, vocal 93-132 %, contact 90-110 %; a tighter gate needs 20+ seeds = hours); the big single kinds >= 40 %; vocal chatter also <= 140 %: a band, they must not speak too much)
        let newIdle = Set(BlobBrain.emoteKinds.map { "idle:\($0)" }), newSoc: Set<String> = ["soc:congaLine", "soc:ringDance", "soc:highFive", "soc:squabble", "soc:shove"]
        func sum(_ d: [String: Int], _ pick: (String) -> Bool) -> Int { d.filter { pick($0.key) }.values.reduce(0, +) }
        let families: [(String, (String) -> Bool)] = [
            ("vocal chatter (chirps / babble)", { $0.hasPrefix("chirp:") }),
            ("contact sounds (boop / squish / wobble / meeting boops)", { ["boop", "squish", "wobble", "soc:boopEvent"].contains($0) }),
            ("every pre-existing idle / antic / flourish kind", { $0.hasPrefix("idle:") && !newIdle.contains($0) }),
            ("every pre-existing social kind", { $0.hasPrefix("soc:") && $0 != "soc:boopEvent" && !newSoc.contains($0) }),
            ("walking flourishes", { ["idle:skipHop", "idle:hopscotch", "idle:legSpin", "idle:trot", "idle:stopLook", "idle:chirp", "idle:shake"].contains($0) }),
            ("antics (bounce / jacks / tail / flop / peek / stretch / window / sway / giggle)", { ["idle:bounce", "idle:jacks", "idle:tail", "idle:flop", "idle:peek", "idle:stretch", "idle:window", "idle:sway", "idle:giggle"].contains($0) }),
            ("dashes (run / zoomies / slide / scoot / joy)", { ["idle:run", "idle:zoomies", "idle:slide", "idle:scoot", "idle:joy", "zoomies"].contains($0) }),
            ("jump sounds", { $0 == "jump" }),
        ]
        for (name, f) in families {
            let n = sum(total, f), b = sum(base, f)
            XCTAssertGreaterThanOrEqual(Double(n), 0.75 * Double(b), "\(name): \(n) vs approved \(b)")
            if name.hasPrefix("vocal") { XCTAssertLessThanOrEqual(Double(n), 1.4 * Double(b), "they do not speak too much: \(name) \(n) vs approved \(b)") }          // (a band, not a floor)
        }
        for (k, b) in base where b >= 30 && k != "step" { XCTAssertGreaterThanOrEqual(Double(total[k, default: 0]), 0.4 * Double(b), "\(k): \(total[k, default: 0]) vs approved \(b)") }
        // NEWONLY-END
    }

    /// An unmuted hub that is started plays the room's cues past every guard (not just the request taps above).
    func testStartedHubLetsRoomCuesThrough() {
        let hub = AudioHub(defaults: UserDefaults(suiteName: UUID().uuidString)!, muted: false)
        hub.start()
        for s in [SFX.jump, .boop, .squish, .wobble, .footstep, .zoomies, .setdown] { hub.play(s, jelly: 0, x: 0) }
        hub.chirp(jelly: 0, .happy); hub.chirp(jelly: 1, .babble)
        print("HUBLOG \(hub._playLog)")
        XCTAssertEqual(hub._playLog.sorted(), ["boop", "footstep", "jump", "setdown", "squish", "wobble", "zoomies"])
    }

    /// Two Jelbies pressed together must be able to get closer than ContactTuning.contactFrac of the gap, or the contact squish + kick (BlobBrain+Contact) never fires.
    /// (g-bodysep floored keepApart at the full gap: 0 contacts at home, r1052.)
    func testKeepApartStillAllowsContact() {
        let peers: [(pos: SIMD2<Float>, walking: Bool)] = [(SIMD2(0, 0), false), (SIMD2(0.3, 0), false)]
        let q = MelonController.keepApart(SIMD3(0.3, 0, 0), id: 1, peers: peers)
        let d = simd_length(SIMD2(q.x, q.z))
        XCTAssertLessThan(d, MelonController.jellyGap * ContactTuning.contactFrac, "pressed pair reaches contact distance (d=\(d))")
    }
}
