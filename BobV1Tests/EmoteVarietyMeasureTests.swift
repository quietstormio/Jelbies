//
//  EmoteVarietyMeasureTests.swift
//  The emote-variety soak (emote-variety-r1): 3 happy Jelmiko in the lively room (antics + a watching player), 30 sim-minutes per seed. Every start (a Jelmiko's label
//  changes to a new idle / social / play kind) is logged to a .txt (raw events) and the six variety metrics are printed:
//    distinct kinds per 10 minutes, top-5 share, each look-alike cluster's share, the longest same-cluster run per Jelmiko, room repeats (the same kind by two
//    Jelmiko within 25 s, outside joint sessions), and total starts per minute.
//  The cluster map lives HERE (by raw name) so the same file measures the build before and after the change.
//  Env: TEST_RUNNER_VARIETY_TAG (file tag, default "run"), TEST_RUNNER_VARIETY_DIR (output directory).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class EmoteVarietyMeasureTests: XCTestCase {
    static let clusters: [String: [String]] = [
        "hop": ["idle:bounce", "idle:scoot", "idle:jacks", "idle:joy", "idle:skipHop", "idle:hopscotch", "idle:flapHop", "social:hopAlong", "social:bellyBounce", "play:hop"],
        "spin": ["idle:tail", "idle:legSpin", "idle:oneLegSpin", "social:twirl", "play:spin"],
        "hug": ["social:groupHug", "social:swayHug", "social:spinHug", "social:cuddleLean", "social:cuddle", "social:nuzzle"],
        "dance": ["social:dance", "social:danceOff", "social:mirrorDance", "social:circleDance", "social:ringDance", "social:ringAround"],
        "chase": ["social:chase", "social:tag", "social:keepAway", "social:littleRace"],
        "dash": ["idle:zoomies", "idle:run", "idle:slide", "idle:trot", "idle:stumble", "social:zoomies"],
    ]
    static func cluster(_ l: String) -> String? { clusters.first { $0.value.contains(l) }?.key }

    struct Ev { var t: Float; var rig: Int; var label: String }

    static func run(seed: UInt64, seconds: Int, mood: BlobMood = .happy) -> [Ev] {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        let lab = SocialTests.Lab(quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            r.brain.idleMood = mood; r.brain.socialBook.cooldown = 8; r.brain.idleState.cooldown = 9; r.brain.restTimer = 0.5 + Float(i)
            AnticsLabTests.lively(r.brain)
        }
        var prev = [String?](repeating: nil, count: 3)
        var ev: [Ev] = []
        for f in 0..<(60 * seconds) {
            lab.tick(watching: false)
            let t = Float(f) / 60
            for (i, r) in lab.rigs.enumerated() {
                let l = AnticsLabTests.label(r.brain)
                if let l, l != prev[i], l != "idle:wander", l != "idle:sleep", l != "wave" { ev.append(Ev(t: t, rig: i, label: l)) }
                prev[i] = l
            }
        }
        return ev
    }

    struct Metrics {
        var starts = 0, minutes: Float = 0
        var distinctPer10: [Int] = []
        var top5: Float = 0
        var clusterShare: [String: Float] = [:]
        var longestRun = 0
        var roomRepeats = 0
        var counts: [String: Int] = [:]
        var dashStarts = 0
    }

    static func metrics(_ ev: [Ev], seconds: Int) -> Metrics {
        var m = Metrics()
        m.starts = ev.count; m.minutes = Float(seconds) / 60
        for e in ev { m.counts[e.label, default: 0] += 1 }
        for w in 0..<(seconds / 600) {
            let lo = Float(w * 600), hi = lo + 600
            m.distinctPer10.append(Set(ev.filter { $0.t >= lo && $0.t < hi }.map { $0.label }).count)
        }
        let top = m.counts.values.sorted(by: >).prefix(5).reduce(0, +)
        m.top5 = ev.isEmpty ? 0 : Float(top) / Float(ev.count)
        for (c, ks) in clusters { m.clusterShare[c] = ev.isEmpty ? 0 : Float(ev.filter { ks.contains($0.label) }.count) / Float(ev.count) }
        for r in 0..<3 {
            var run = 0, cur: String?
            for e in ev where e.rig == r {
                let c = cluster(e.label)
                if let c, c == cur { run += 1 } else { run = c == nil ? 0 : 1 }
                cur = c; m.longestRun = max(m.longestRun, run)
            }
        }
        // room repeats: same kind by two different Jelmiko within 25 s, not a joint start (a social label started by both within 1.5 s)
        func joint(_ a: Ev) -> Bool { a.label.hasPrefix("social:") && ev.contains { $0.rig != a.rig && $0.label == a.label && abs($0.t - a.t) < 1.5 } }
        for (i, a) in ev.enumerated() {
            guard !joint(a) else { continue }
            for b in ev[(i + 1)...] where b.t - a.t < 25 { if b.rig != a.rig, b.label == a.label, !joint(b) { m.roomRepeats += 1; break } }
        }
        m.dashStarts = ev.filter { ["idle:zoomies", "idle:run", "idle:slide", "social:zoomies"].contains($0.label) }.count
        return m
    }

    /// The park (1 home Jelmiko + 3 visitors, closeness 0.55 as a first visit): one seed, same set-up as ParkPlayTests.soak.
    static func runPark(seed: UInt64, seconds: Int) -> [Ev] {
        ParkPlayTuning.toyRateNew = true; ParkPlayTuning.socialNew = true; ParkPlayTuning.seesawInPark = false
        ParkVisitPlan.current = .all
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); HopscotchLine.shared.prune(keeping: []); SeesawRide.shared.reset()
        BlobBrain.pickBudgetSeconds = .infinity
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        defer {
            BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
            DecorField.shared.clear(); HopscotchLine.shared.prune(keeping: [])
            ParkPlayTuning.seesawInPark = true
            GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
            GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
        }
        let n = 4
        let pts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(1.6, 1.2)]
        let lab = SocialTests.Lab(n: n, positions: pts, quiet: false, seed: seed)
        for (k, r) in lab.rigs.enumerated() {
            r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true; r.skinner.autoBlink = false; r.renderSamples = false
            r.brain.feature = JellyRoster.feature(k % 5)
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            for (j, o) in lab.rigs.enumerated() where o !== r && (j >= 1 || k >= 1) { r.brain.socialBook.close[o.brain.steerID] = 0.55 }
        }
        WearBody.install(MotionRig.renderMesh)
        let field = DecorField.shared
        field.set(ParkVisitPlan.placedToday); field.toys.news.removeAll()
        var prev = [String?](repeating: nil, count: n), ev: [Ev] = []
        for f in 0..<(60 * seconds) {
            lab.tick(watching: false); field.tick(dt: 1.0 / 60)
            let t = Float(f) / 60
            for (i, r) in lab.rigs.enumerated() {
                let l = AnticsLabTests.label(r.brain)
                if let l, l != prev[i], l != "idle:wander", l != "idle:sleep", l != "wave" { ev.append(Ev(t: t, rig: i, label: l)) }
                prev[i] = l
            }
        }
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        field.clear()
        return ev
    }

    func testParkMeasure() throws {
        let tag = ProcessInfo.processInfo.environment["VARIETY_TAG"] ?? "run"
        let dir = ProcessInfo.processInfo.environment["VARIETY_DIR"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/49d32754-b08a-4bfd-999b-3f9f0cada45f/scratchpad/variety"
        let ev = Self.runPark(seed: 41, seconds: 900)
        let m = Self.metrics(ev, seconds: 900)
        var s = "PARK seed 41, 900 s, 1 home + 3 visitors: starts \(m.starts) (\(String(format: "%.2f", Float(m.starts) / m.minutes))/min), dash starts \(m.dashStarts), distinct/10min \(m.distinctPer10), top5 \(String(format: "%.1f", m.top5 * 100))%, room repeats \(m.roomRepeats), clusters \(m.clusterShare.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.1f", $0.value * 100))%" }.joined(separator: ", "))\n"
        s += "  counts: \(m.counts.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))\n"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try s.write(toFile: "\(dir)/park_\(tag).txt", atomically: true, encoding: .utf8)
        MotionLog.write(s)
    }

    func testSoakMeasure() throws {
        let tag = ProcessInfo.processInfo.environment["VARIETY_TAG"] ?? "run"
        let dir = ProcessInfo.processInfo.environment["VARIETY_DIR"] ?? "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/49d32754-b08a-4bfd-999b-3f9f0cada45f/scratchpad/variety"
        let secs = Int(ProcessInfo.processInfo.environment["VARIETY_SECONDS"] ?? "1800") ?? 1800
        var raw = "", summary = ""
        var all: [Metrics] = []
        let seedList = (ProcessInfo.processInfo.environment["VARIETY_SEEDS"] ?? "101,202,303").split(separator: ",").compactMap { UInt64($0) }
        for seed in seedList {
            let ev = Self.run(seed: seed, seconds: secs)
            for e in ev { raw += "\(seed)\t\(String(format: "%.2f", e.t))\t\(e.rig)\t\(e.label)\n" }
            let m = Self.metrics(ev, seconds: secs)
            all.append(m)
            summary += "seed \(seed): starts \(m.starts) (\(String(format: "%.2f", Float(m.starts) / m.minutes))/min), dash starts \(m.dashStarts), distinct/10min \(m.distinctPer10), top5 \(String(format: "%.1f", m.top5 * 100))%, longest same-cluster run \(m.longestRun), room repeats \(m.roomRepeats), clusters \(m.clusterShare.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.1f", $0.value * 100))%" }.joined(separator: ", "))\n"
            summary += "  counts: \(m.counts.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))\n"
        }
        let n = Float(all.count)
        let avgDistinct = Float(all.flatMap { $0.distinctPer10 }.reduce(0, +)) / Float(all.flatMap { $0.distinctPer10 }.count)
        summary += "ALL: starts/min \(String(format: "%.2f", all.map { Float($0.starts) / $0.minutes }.reduce(0, +) / n)), dash starts/min \(String(format: "%.2f", all.map { Float($0.dashStarts) / $0.minutes }.reduce(0, +) / n)), distinct/10min \(String(format: "%.1f", avgDistinct)), top5 \(String(format: "%.1f", all.map { $0.top5 }.reduce(0, +) / n * 100))%, longest run max \(all.map { $0.longestRun }.max() ?? 0), room repeats total \(all.map { $0.roomRepeats }.reduce(0, +))\n"
        var cs = ""
        for c in Self.clusters.keys.sorted() { cs += "\(c) \(String(format: "%.1f", all.map { $0.clusterShare[c] ?? 0 }.reduce(0, +) / n * 100))%  " }
        summary += "ALL clusters: \(cs)\n"
        var tot: [String: Int] = [:]
        for m in all { for (k, v) in m.counts { tot[k, default: 0] += v } }
        let groups = ["social:groupHug", "social:groupCheer", "social:conga", "social:circleDance"].map { ($0, tot[$0] ?? 0) }
        let gs = max(1, groups.reduce(0) { $0 + $1.1 })
        summary += "ALL group share (participant starts): \(groups.map { "\($0.0)=\(String(format: "%.1f", Float($0.1) / Float(gs) * 100))%" }.joined(separator: " "))\n"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try raw.write(toFile: "\(dir)/events_\(tag).txt", atomically: true, encoding: .utf8)
        try summary.write(toFile: "\(dir)/summary_\(tag).txt", atomically: true, encoding: .utf8)
        MotionLog.write("VARIETY \(tag)\n\(summary)")
    }
}

/// Stargazing could never fire: it needs night >= 0.6 but the treat slot refused to roll at night >= 0.6. Through the real scheduler (`idleMaybeStart`), an awake Jelmiko
/// at night 0.8 (and exactly 0.6) now reaches it.
@MainActor
final class StargazingNightTests: XCTestCase {
    func testStargazingFiresAtNightThroughTheTreatSlot() {
        XCTAssertFalse(BlobBrain.windowXs().isEmpty, "the room has a window to look out of")
        for night: Float in [0.8, 0.6] {
            var seen = false
            for seed in [5, 6, 7] as [UInt64] where !seen {
                let lab = SocialTests.Lab(n: 1, quiet: false, seed: seed)
                let b = lab.rigs[0].brain
                b.anticsEnabled = true; b.sleepEnabled = false; b.idleMood = .happy; b.idleNight = night; b.idleDeepNight = 0
                b.idleState.cooldown = 0; b.idleState.treat = 0; b.restTimer = 0.5
                for f in 0..<(60 * 900) {
                    lab.tick(watching: false)
                    if b.idleState.kind == .stargazing { seen = true; break }
                    if f % 600 == 0 { XCTAssertNotEqual(b.idleState.kind, .sleep) }
                }
            }
            XCTAssertTrue(seen, "stargazing fires at night \(night) from the treat slot")
        }
    }
}
