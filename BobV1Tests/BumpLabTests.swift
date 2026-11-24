//
//  BumpLabTests.swift
//  move-crowd-r1 (11-24, "The collisions and crowding is killing the game"): the SCOREBOARD. A headless, seeded, deterministic soak of free roaming (the brains' own scheduler: goals, emotes,
//  pair / group moments) in four scenes: home with three (happy, grumpy), home with a guest (four, happy), the park (five + toys). Judged PER ENCOUNTER (fewer-bumps-r1 analysis):
//    encounter     two bodies whose centres come within 2.0 (sampled every tick; it ends after 2 s outside 2.0)
//    enter 1.4     the encounter's closest centre distance went under 1.4 (MelonStage.jellyGap, the push radius)
//    touch         the drawn skins met (ContactField gap <= +0.5 cm; the centre fallback where no profile exists is counted separately)
//    kind          "partners" = the two were in one social session at any time of the encounter (a pair / group moment: touching is designed there); "free" = all others
//                  (walk-walk / walk-stand / stand-stand at the closest moment)
//  plus hard stops and pushes per minute (MoveLog), the longest stand-off (a body on a walk that has not moved 3 cm in 0.25 s while another body is within 2.0, longest run in s),
//  moments (pair + group sessions finished) and emote starts per 10 minutes, walk seconds per u of arrived walks.
//  Opt-in: TEST_RUNNER_SCOREBOARD=1 (SCOREBOARD_SECONDS default 600, SCOREBOARD_SEEDS default 6, SCOREBOARD_ONLY = a scene name part). Lines `SCORE ...` go to MotionLog (TEST_RUNNER_MOTION_LOG).
//  The seeded episode lab of fewer-bumps-r1 (8 logged real-app bump episodes) is kept below as a mechanism check.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BumpLabTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { BlobBrain.pickBudgetSeconds = .infinity }
    override func tearDown() {
        MoveLog.on = false; MoveLog.writeFile = true
        BlobBrain.pickBudgetSeconds = BlobBrain.defaultPickBudgetSeconds
        DecorField.shared.clear(); HopscotchLine.shared.prune(keeping: [])
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    enum Scene: String, CaseIterable { case homeHappy = "home happy 3", homeGrumpy = "home grumpy 3", guest = "home guest 4", park = "park 5" }

    struct Score {
        var mins: Float = 0
        var enc = 0, enc14 = 0, encTouch = 0
        var free = 0, free14 = 0, freeTouch = 0
        var ww = 0, ww14 = 0, wwTouch = 0          // free, both walking at the closest moment
        var ws = 0, ws14 = 0, wsTouch = 0          // free, one walking
        var part = 0, part14 = 0, partTouch = 0
        var hard = 0, push = 0, standOff: Float = 0, moments = 0, emotes = 0, kinds = 0
        var walkSecPerU: Float = 0
        var gapNil = 0, gapAll = 0
        var f14Same = 0, f14Route = 0, f14After = 0          // free encounters entering 1.4: both walking the same way (< 90 deg), one on a waypoint leg, one left a moment within 6 s
        var cols: [Float] {
            let m = max(mins, 1e-3)
            func pc(_ a: Int, _ b: Int) -> Float { b == 0 ? 0 : Float(a) / Float(b) * 100 }
            return [Float(enc) / m, pc(enc14, enc), pc(encTouch, enc), Float(free) / m, pc(free14, free), pc(freeTouch, free), Float(free14) / m, Float(freeTouch) / m,
                    pc(ww14, ww), pc(ws14, ws), Float(hard) / m, Float(push) / m, standOff, Float(moments) / m * 10, Float(emotes) / m * 10, walkSecPerU]
        }
        static let names = ["enc/min", "enc>1.4%", "touch%", "free enc/min", "free>1.4%", "free touch%", "free>1.4/min", "free touch/min", "ww>1.4%", "ws>1.4%", "hard/min", "push/min", "standoff s", "moments/10m", "emotes/10m", "walk s/u"]
    }

    /// One encounter of a pair, open while their centres are within 2.0 (closed after 2 s outside).
    struct Enc { var minD: Float = 9; var touched = false; var partners = false; var walkersAtMin = 0; var outT: Float = 0; var sameWay = false; var onRoute = false; var afterMoment = false }

    func run(_ scene: Scene, seed: UInt64, seconds: Float) -> Score {
        EmoteSpot.reset(); RoomTraffic.waitFor = [:]; RoomTraffic.waited = [:]; MoveMix.soccerNextAt = 0
        let lab: SocialTests.Lab
        switch scene {
        case .homeHappy, .homeGrumpy, .guest:
            let n = scene == .guest ? 4 : 3
            GameCamera.configureRoom(count: n, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
            _ = GameCamera.refreshRoam(aspect: 440 / 956)
            RoomLayout.dynamicBoxes = []
            let pos = n == 3 ? SocialTests.starts : [SIMD2(-1.6, 0.8), SIMD2(1.6, 0.8), SIMD2(0, 2.4), SIMD2(0.2, -1.2)]
            lab = SocialTests.Lab(n: n, positions: pos, quiet: false, seed: seed)
            for (i, r) in lab.rigs.enumerated() {
                r.skinner.autoBlink = false
                let b = r.brain
                b.sleepEnabled = false; b.anticsEnabled = true; b.watching = true; b.homeRoom = true
                b.idleMood = scene == .homeGrumpy ? .grumpy : .happy; b.idleNight = 0; b.idleDeepNight = 0; b.idleMorning = 0
                b.socialBook.cooldown = 6 + Float(i) * 3; b.idleState.cooldown = 8 + Float(i) * 2; b.restTimer = 0.5 + Float(i)
                r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
            }
        case .park:
            ParkVisitPlan.current = .all
            DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); HopscotchLine.shared.prune(keeping: [])
            RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
            let pts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(1.6, 1.2), SIMD2(-1.6, 1.6)]
            lab = SocialTests.Lab(n: 5, positions: pts, quiet: false, seed: seed)
            for (k, r) in lab.rigs.enumerated() {
                r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
                r.brain.anticsEnabled = true; r.brain.watching = true; r.brain.idleMood = .happy; r.brain.outingPlay = true; r.skinner.autoBlink = false; r.renderSamples = false
                r.brain.feature = JellyRoster.feature(k % 5)
                r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
                for (j, o) in lab.rigs.enumerated() where o !== r && (j >= 2 || k >= 2) { r.brain.socialBook.close[o.brain.steerID] = 0.55 }
            }
            WearBody.install(MotionRig.renderMesh)
            DecorField.shared.set(ParkVisitPlan.placedToday); DecorField.shared.toys.news.removeAll()
        }
        Self.keep.append(lab)
        MoveLog.shared.reset(); MoveLog.shared.tag = "\(scene.rawValue) seed \(seed)"; MoveLog.writeFile = false; MoveLog.on = true
        let n = lab.rigs.count, dt: Float = 1.0 / 60
        var sc = Score()
        var open = [Int: Enc]()
        var lastP = lab.rigs.map { $0.brain.position }, stillT = [Float](repeating: 0, count: n), sampT: Float = 0
        var sessions = Set<ObjectIdentifier>(), keepSess: [AnyObject] = []
        var lastSocial = [Float](repeating: -99, count: n), clockT: Float = 0
        func close(_ e: Enc) {
            sc.enc += 1; if e.minD < 1.4 { sc.enc14 += 1 }; if e.touched { sc.encTouch += 1 }
            if e.partners { sc.part += 1; if e.minD < 1.4 { sc.part14 += 1 }; if e.touched { sc.partTouch += 1 }; return }
            sc.free += 1; if e.minD < 1.4 { sc.free14 += 1; if e.sameWay { sc.f14Same += 1 }; if e.onRoute { sc.f14Route += 1 }; if e.afterMoment { sc.f14After += 1 } }; if e.touched { sc.freeTouch += 1 }
            if e.walkersAtMin == 2 { sc.ww += 1; if e.minD < 1.4 { sc.ww14 += 1 }; if e.touched { sc.wwTouch += 1 } }
            else if e.walkersAtMin == 1 { sc.ws += 1; if e.minD < 1.4 { sc.ws14 += 1 }; if e.touched { sc.wsTouch += 1 } }
        }
        for _ in 0..<Int(seconds * 60) {
            lab.tick(watching: false)
            if scene == .park { DecorField.shared.tick(dt: dt) }
            let br = lab.rigs.map { $0.brain }
            clockT += dt
            for i in 0..<n where br[i].social != nil { lastSocial[i] = clockT }
            let walking = br.map { $0.activity == .walking || $0.activity == .coming }
            for b in br { if let s = b.social, sessions.insert(ObjectIdentifier(s)).inserted { keepSess.append(s) } }
            for i in 0..<n { for j in (i + 1)..<n {
                let a = br[i], b = br[j], key = i * 16 + j
                let d = simd_distance(a.position, b.position)
                if var e = open[key] {
                    if d < 2.0 { e.outT = 0 } else { e.outT += dt }
                    if e.outT >= 2 { close(e); open[key] = nil; continue }
                    open[key] = e
                } else if d < 2.0 { open[key] = Enc() }
                guard var e = open[key] else { continue }
                if a.social != nil && a.social === b.social { e.partners = true }
                if d < e.minD { e.minD = d; e.walkersAtMin = (walking[i] ? 1 : 0) + (walking[j] ? 1 : 0); e.sameWay = walking[i] && walking[j] && cosf(a.yaw - b.yaw) > 0; e.onRoute = (walking[i] && !a.steerRoute.isEmpty) || (walking[j] && !b.steerRoute.isEmpty); e.afterMoment = clockT - lastSocial[i] < 6 || clockT - lastSocial[j] < 6 }
                if d < 2.0 {
                    sc.gapAll += 1
                    let g: Float
                    if let cg = ContactField.gap(a.steerID, b.steerID, features: false) { g = min(cg, ContactField.skinGap(a.steerID, b.steerID) ?? cg) }
                    else { sc.gapNil += 1; g = d - 0.5 * a.peerGap }
                    if g <= ContactTuning.touchGap { e.touched = true }
                }
                open[key] = e
            } }
            sampT += dt
            if sampT >= 0.25 {
                for i in 0..<n {
                    let p = br[i].position
                    let near = (0..<n).contains { $0 != i && simd_distance(br[$0].position, p) < 2.0 }
                    if walking[i], near, simd_distance(p, lastP[i]) < 0.03 { stillT[i] += sampT; sc.standOff = max(sc.standOff, stillT[i]) } else { stillT[i] = 0 }
                    lastP[i] = p
                }
                sampT = 0
            }
        }
        for e in open.values { close(e) }
        MoveLog.on = false
        let t = MoveLog.shared.total
        sc.mins = seconds / 60
        sc.hard = t.n[MoveLog.Kind.hard.rawValue]; sc.push = t.n[MoveLog.Kind.push.rawValue]
        sc.emotes = t.emoteN; sc.moments = sessions.count; sc.kinds = t.kinds.count
        sc.walkSecPerU = t.arrSec / max(t.arrDist, 0.01)
        _ = keepSess
        for r in lab.rigs { r.brain.abortScript(r.sim, r.skinner) }
        DecorField.shared.clear(); HopscotchLine.shared.prune(keeping: [])
        if scene == .park { GameCamera.endPark(count: 3); RoomLayout.apply(RoomCatalog.home) }
        return sc
    }

    static func fmt(_ v: [Float]) -> String { v.map { String(format: "%.2f", $0) }.joined(separator: " | ") }

    func testScoreboard() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SCOREBOARD"] != nil else { throw XCTSkip("set TEST_RUNNER_SCOREBOARD=1") }
        let seconds = Float(env["SCOREBOARD_SECONDS"].flatMap { Float($0) } ?? 600)
        let nSeeds = env["SCOREBOARD_SEEDS"].flatMap { Int($0) } ?? 6
        let seeds: [UInt64] = (0..<nSeeds).map { 101 + 13 * UInt64($0) }
        let tag = env["SCOREBOARD_TAG"] ?? "run"
        MotionLog.write("SCORE \(tag) switches: \(MoveCrowdInfo.text) seconds \(seconds) seeds \(seeds)")
        MotionLog.write("SCORE \(tag) columns: " + Score.names.joined(separator: " | "))
        for scene in Scene.allCases where env["SCOREBOARD_ONLY"] == nil || scene.rawValue.contains(env["SCOREBOARD_ONLY"]!) {
            var rows: [[Float]] = []
            var pooled = Score()
            for s in seeds {
                let sc = run(scene, seed: s, seconds: seconds)
                rows.append(sc.cols)
                MotionLog.write("SCORE \(tag) \(scene.rawValue) seed \(s): " + Self.fmt(sc.cols) + " | f14 same \(sc.f14Same) route \(sc.f14Route) afterMoment \(sc.f14After) | kinds \(sc.kinds) gapNil \(sc.gapNil)/\(sc.gapAll) enc \(sc.enc) free \(sc.free) ww \(sc.ww) ws \(sc.ws) part \(sc.part)")
                pooled.mins += sc.mins; pooled.enc += sc.enc; pooled.enc14 += sc.enc14; pooled.encTouch += sc.encTouch; pooled.free += sc.free; pooled.free14 += sc.free14; pooled.freeTouch += sc.freeTouch
                pooled.ww += sc.ww; pooled.ww14 += sc.ww14; pooled.ws += sc.ws; pooled.ws14 += sc.ws14; pooled.part += sc.part; pooled.part14 += sc.part14; pooled.partTouch += sc.partTouch
                pooled.f14Same += sc.f14Same; pooled.f14Route += sc.f14Route; pooled.f14After += sc.f14After
                pooled.hard += sc.hard; pooled.push += sc.push; pooled.standOff = max(pooled.standOff, sc.standOff); pooled.moments += sc.moments; pooled.emotes += sc.emotes
                pooled.walkSecPerU += sc.walkSecPerU / Float(seeds.count)
            }
            let k = Float(rows.count), cols = rows[0].count
            let mean = (0..<cols).map { c in rows.map { $0[c] }.reduce(0, +) / k }
            let sd = (0..<cols).map { c in sqrtf(rows.map { ($0[c] - mean[c]) * ($0[c] - mean[c]) }.reduce(0, +) / max(k - 1, 1)) }
            MotionLog.write("SCORE \(tag) \(scene.rawValue) POOLED: " + Self.fmt(pooled.cols) + " | free>1.4 n \(pooled.free14): same-way \(pooled.f14Same) route \(pooled.f14Route) afterMoment \(pooled.f14After) | partners \(pooled.part) >1.4 \(pooled.part14) touch \(pooled.partTouch)")
            MotionLog.write("SCORE \(tag) \(scene.rawValue) MEAN: " + Self.fmt(mean))
            MotionLog.write("SCORE \(tag) \(scene.rawValue) SD: " + Self.fmt(sd))
        }
    }

    /// Determinism gate: one scene, one seed, twice in one process: the rows must be identical.
    func testScoreboardDeterministic() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SCOREBOARD"] != nil else { throw XCTSkip("set TEST_RUNNER_SCOREBOARD=1") }
        let a = run(.homeHappy, seed: 101, seconds: 120).cols, b = run(.homeHappy, seed: 101, seconds: 120).cols
        MotionLog.write("SCORE determinism A: " + Self.fmt(a)); MotionLog.write("SCORE determinism B: " + Self.fmt(b))
        XCTAssertEqual(a, b, "the same seed gives the same row")
    }
}
