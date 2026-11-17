//
//  SocialMoreTests.swift
//  social-more-r1: group emotes ~2x and pair emotes ~1.5x as often (SocialMoreTuning.swift), everything else kept (>= 0.9x). The measuring soak runs only with TEST_RUNNER_SOCIAL_MORE=1
//  (TEST_RUNNER_SOCIAL_MORE_SEEDS=n default 4, TEST_RUNNER_SOCIAL_MORE_SECONDS=n default 300); the table goes to MotionLog.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class SocialMoreTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() {
        ParkVisitPlan.current = .all
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
        HopscotchLine.shared.prune(keeping: [])
        BlobBrain.pickBudgetSeconds = .infinity
        SocialTuning.pickChance = 0.9
    }
    override func tearDown() {
        SocialMore.on = true
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
        DecorField.shared.clear(); ToyTuning.settle = 5; HopscotchTuning.joinChance = 0.35
        HopscotchLine.shared.prune(keeping: []); ParkPlayTuning.seesawInPark = true
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    func testSwitchRestoresOldWaits() {
        let b = MotionRig(game: true).brain
        SocialMore.on = false
        XCTAssertEqual(b.moreGroupWaitMul, 1); XCTAssertEqual(b.morePairWaitMul, 1)
        SocialMore.on = true
        XCTAssertEqual(b.moreGroupWaitMul, SocialMore.homeGroupWait); XCTAssertEqual(b.morePairWaitMul, SocialMore.homePairWait)
        b.outingPlay = true
        XCTAssertEqual(b.moreGroupWaitMul, SocialMore.parkGroupWait); XCTAssertEqual(b.morePairWaitMul, SocialMore.parkPairWait)
    }

    struct Run { var group = 0, pair = 0, solo = 0, toys = 0, wander = 0, zoom = 0; var idleSec: Float = 0 }

    private func soak(park: Bool, n: Int, seconds: Float, seed: UInt64, more: Bool) -> Run {
        SocialMore.on = more
        ParkPlayTuning.toyRateNew = true; ParkPlayTuning.socialNew = true; ParkPlayTuning.seesawInPark = false
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); HopscotchLine.shared.prune(keeping: []); SeesawRide.shared.reset()
        if park { HopscotchTuning.joinChance = ParkPlayTuning.hopscotchJoin; RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0) }
        else { RoomLayout.apply(RoomCatalog.home); GameCamera.configureRoom(count: n); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        let pts: [SIMD2<Float>] = park ? [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(1.6, 1.2), SIMD2(-1.6, 1.6)] : SocialTests.starts
        let lab = SocialTests.Lab(n: n, positions: Array(pts.prefix(n)), quiet: false, seed: seed)
        Self.keep.append(lab)
        for (k, r) in lab.rigs.enumerated() {
            if park { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius }
            r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = park; r.skinner.autoBlink = false; r.renderSamples = false
            r.brain.feature = JellyRoster.feature(k % 5)
            r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
            for (j, o) in lab.rigs.enumerated() where o !== r { r.brain.socialBook.close[o.brain.steerID] = (park && (j >= 3 || k >= 3)) ? 0.55 : 1 }
        }
        WearBody.install(MotionRig.renderMesh)
        let field = DecorField.shared
        if park { field.set(ParkVisitPlan.placedToday); field.toys.news.removeAll() }
        var out = Run(), prev = [IdleKind?](repeating: nil, count: n), prevWalk = [Bool](repeating: false, count: n), seen = Set<ObjectIdentifier>(), keepAlive: [SocialSession] = []
        let dt: Float = 1.0 / 60
        for _ in 0..<Int(seconds * 60) {
            lab.tick(watching: false); field.tick(dt: dt)
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain, now = b.idleState.kind
                if prev[i] != now, let k = now, b.social == nil {
                    switch k {
                    case .decorSlide, .decorHopscotch, .decorSit: out.toys += 1
                    default: out.solo += 1
                    }
                }
                prev[i] = now
                let walking = b.activity == .walking && b.social == nil
                if walking && !prevWalk[i] { out.wander += 1 }
                prevWalk[i] = walking
                if now == nil, b.scriptIsNone, b.social == nil, b.activity != .walking { out.idleSec += dt }
                if let s = b.social, !seen.contains(ObjectIdentifier(s)) { seen.insert(ObjectIdentifier(s)); keepAlive.append(s)
                    if s.kind.isGroup { out.group += 1 } else if s.kind == .zoomies { out.zoom += 1 } else if s.kind != .look { out.pair += 1 } }
            }
        }
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        field.clear(); HopscotchLine.shared.prune(keeping: [])
        return out
    }

    private func med(_ v: [Float]) -> Float { v.isEmpty ? 0 : v.reduce(0, +) / Float(v.count) }          // (the mean over the seeds: counts per run are small, a median is too coarse)

    func testSocialMoreSoak() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SOCIAL_MORE"] != nil else { throw XCTSkip("set TEST_RUNNER_SOCIAL_MORE=1") }
        let seconds = Float(env["SOCIAL_MORE_SECONDS"].flatMap { Float($0) } ?? 300)
        let seedCount = env["SOCIAL_MORE_SEEDS"].flatMap { Int($0) } ?? 4
        let seeds: [UInt64] = (0..<seedCount).map { 41 + 7 * UInt64($0) }
        for (label, park, n) in [("home 3", false, 3), ("park 3 + 2 visitors", true, 5)] {
            var o: [Run] = [], w: [Run] = []
            for s in seeds {
                o.append(soak(park: park, n: n, seconds: seconds, seed: s, more: false))
                w.append(soak(park: park, n: n, seconds: seconds, seed: s, more: true))
            }
            let perMin = 60 / seconds / Float(n) * Float(n)          // per minute (whole group of n)
            MotionLog.write("SOCIALMORE \(label) | per minute, whole group, median over \(seeds.count) seeds x \(Int(seconds)) s | metric | before | after | ratio")
            func row(_ name: String, _ f: (Run) -> Float) {
                let a = med(o.map(f)) * perMin, b = med(w.map(f)) * perMin
                MotionLog.write(String(format: "SOCIALMORE %@ | %@ | %.2f | %.2f | %.2f", label, name, a, b, a > 0 ? b / a : 0))
            }
            row("group emote starts", { Float($0.group) }); row("pair emote starts", { Float($0.pair) })
            row("solo idle starts", { Float($0.solo) }); row("toy uses (decor)", { Float($0.toys) })
            row("wander legs", { Float($0.wander) }); row("zoomies", { Float($0.zoom) })
            row("standing still (s)", { $0.idleSec })
        }
    }
}
