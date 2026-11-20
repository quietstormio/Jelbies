//
//  PlayFrameTests.swift
//  play-frame-r1 (owner 2026-11-19): while Play mode is on (the ball or the wand) every Jelmiko's whole body stays inside the screen, and the ball's returns / rests too; the
//  play camera is one dial (PlayTuning.camZoom) and the chase is a little faster than the old one (PlayTuning.old = the old numbers).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PlayFrameTests: XCTestCase {
    static let portrait = CGSize(width: 440, height: 956)
    static let landscape = CGSize(width: 956, height: 440)

    override func setUp() { super.setUp(); Self.reset() }
    override func tearDown() { Self.reset(); super.tearDown() }
    static func reset() {
        PlayTuning.old = false; PlayTuning.zoomOverride = nil
        GameCamera.playBlend = 0; RoomLayout.ballSpheres = []
        DecorField.shared.clear()
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: Float(portrait.width / portrait.height))
    }
    static func room(_ size: CGSize) {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let a = Float(size.width / size.height); _ = GameCamera.camera(aspect: a); GameCamera.refreshRoam(aspect: a)
    }

    /// The screen box (points) of a body standing at `p`: 0.9 sideways (wings, spines, sway), 0.8 deep, 1.25 body heights tall (ears, antennas, hat), as HUDLayout.frontBandTop reads it.
    static func box(_ p: SIMD2<Float>, size: CGSize, height: Float = BobShape.H * 1.25) -> (lo: CGPoint, hi: CGPoint)? {
        let e = GameCamera.roamLateralExtent, d: Float = 0.8
        var cs = [SIMD3<Float>]()
        for cx in [p.x - e, p.x + e] { for cy in [Float(0), height] { for cz in [p.y - d, p.y + d] { cs.append(SIMD3(cx, cy, cz)) } } }
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let pts = Silhouette.project(cs, viewProj: cam.viewProj, size: size)
        guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(), let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return nil }
        return (CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1))
    }
    /// How far (points) the box sticks out of the screen: 0 = inside.
    static func cut(_ p: SIMD2<Float>, size: CGSize) -> CGFloat {
        guard let b = box(p, size: size) else { return 999 }
        return max(0, -b.lo.x, b.hi.x - size.width, -b.lo.y, b.hi.y - size.height)
    }

    func testGeometryTable() {
        var out = ""
        for (name, size) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
            for z: Float in [0, 0.25, 0.5, 1] {
                PlayTuning.zoomOverride = z
                Self.room(size); GameCamera.playBlend = 1
                let spots = PlayToss.playSpots(count: 3, size: size)
                let p = PlayToss(); p.viewSize = size
                let hand = p.handWorld()
                var line = String(format: "GEO %@ zoom %.2f | catchZ %.2f hand (%.2f,%.2f) | spots %@ | spot cut %@", name, z, p.catchZ(), hand.x, hand.z,
                                  spots.sorted { $0.key < $1.key }.map { String(format: "(%.1f,%.1f)", $0.value.x, $0.value.y) }.joined(separator: " "),
                                  spots.sorted { $0.key < $1.key }.map { String(format: "%.0f", Self.cut($0.value, size: size)) }.joined(separator: ","))
                // the room floor's reachable corners, seen through this camera
                GameCamera.playBlend = 0; Self.room(size); GameCamera.playBlend = 1
                if let rf = GameCamera.roamFloor {
                    let c = rf.extremeCorners
                    line += " | roam corners cut(pt) " + c.map { String(format: "(%.1f,%.1f):%.0f", $0.x, $0.y, Self.cut($0, size: size)) }.joined(separator: " ")
                    line += String(format: " | roam z %.2f...%.2f hw front %.2f back %.2f", rf.minZ, rf.maxZ, rf.hw.last ?? 0, rf.hw.first ?? 0)
                }
                out += line + "\n"
                // the play floor (PlayToss turns it on with the ball / wand): every row and corner of it, seen through this camera
                GameCamera.playBlend = 1; GameCamera.playFrame = true
                if let rf = GameCamera.refreshRoam(aspect: Float(size.width / size.height)) {
                    var worst: CGFloat = 0
                    for (i, zz) in rf.zs.enumerated() { for x in [-rf.hw[i], 0, rf.hw[i]] { worst = max(worst, Self.cut(SIMD2(x, zz), size: size)) } }
                    out += String(format: "PLAYFLOOR %@ zoom %.2f | z %.2f...%.2f | half width back %.2f front %.2f | area %.1f | worst cut on any row edge %.1f pt\n", name, z, rf.minZ, rf.maxZ, rf.hw.first ?? 0, rf.hw.last ?? 0, rf.area, Double(worst))
                }
                GameCamera.playFrame = false; GameCamera.playFrameView = nil; GameCamera.playBlend = 0
            }
        }
        print(out)
        try? out.write(toFile: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/4c5ade4b-a768-4e5e-a1b1-52f2de759290/scratchpad/playframe/geometry-table-0.txt", atomically: true, encoding: .utf8)
    }

    // MARK: the harness: three Jelmiko, a ball thrown again and again

    struct Run {
        var size = CGSize.zero, kind = DecorKind.ball, seconds: Float = 0
        var liveSeconds: Float = 0
        var moveShare: [Float] = [0, 0, 0]          // seconds each Jelmiko moved (> 0.35 u/s) while a ball was live
        var firstTouch: [Float] = []
        var tosses = 0, catches = 0, touches = 0
        var takers: [Set<Int>] = []                 // per throw: who headed / kicked
        var cutSteps = 0, steps = 0, worstCut: CGFloat = 0
        var ballOff = 0, ballChecks = 0
        var worstBall: CGFloat = 0
        var perJellyTouches = [0, 0, 0]
    }

    nonisolated(unsafe) static var keep: [AnyObject] = []

    func ballOnScreen(_ b: TossBall, size: CGSize) -> CGFloat {
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let q = cam.viewProj * SIMD4<Float>(b.pos.x, b.pos.y, b.pos.z, 1)
        guard q.w > 1e-4 else { return 999 }
        let x = CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y = CGFloat(1 - (q.y / q.w * 0.5 + 0.5)) * size.height
        let r = CGFloat(b.radius) * 40
        return max(0, r - x, x + r - size.width, r - y, y + r - size.height)
    }

    /// One session: `seconds` of throws (one every time the ball is back in the hand), the Jelmiko as the real game runs them.
    func session(kind: DecorKind, seed: Int, size: CGSize, seconds: Float = 60, old: Bool) -> Run {
        PlayTuning.old = old
        Self.room(size)
        BlobBrain.pickBudgetSeconds = .infinity
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        let start: [SIMD2<Float>] = [SIMD2(-1.6, 0.2), SIMD2(0, 1.4), SIMD2(1.6, 0.2)]
        let rs: [MotionRig] = start.enumerated().map { i, s in
            let r = MotionRig(game: true, settle: 0.5)
            Self.keep.append(r)
            r.renderSamples = false
            r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = UInt64(seed * 31 + i * 7 + 5)
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: s); r.run(0.3)
            return r
        }
        let p = PlayToss(); p.seed(UInt64(seed * 977 + 13)); p.viewSize = size
        TossTuning.zBack = -2.4; TossTuning.zFront = 9
        var run = Run(); run.size = size; run.kind = kind
        var throwAt: Float = 0, touched = false
        var takers = Set<Int>()
        p.onEvent = { e in
            switch e {
            case .header(let id, _), .kick(let id):
                run.touches += 1; run.perJellyTouches[id] += 1; takers.insert(id)
                if !touched { touched = true; run.firstTouch.append(p.clock - throwAt) }
            case .caught: run.catches += 1
            default: break
            }
        }
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        p.begin(ball: kind, title: "ball", jellies: js(), snapCamera: true)
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf
        let dt = rs[0].sim.stepDt
        var prev = rs.map(\.brain.position)
        var movedAcc = [Float](repeating: 0, count: 3), winT: Float = 0
        var settle: Float = 4, round = 0
        var t: Float = 0
        while t < seconds + 4 {
            for r in rs { r.tick() }
            p.tick(dt: dt, world: w, jellies: js())
            t += dt
            if p.phase == .inHand, t > settle {
                if p.camBlend > 0.9, simd_distance(p.ball.pos, p.handWorld()) < 0.3 {
                    if throwAt > 0 || run.tosses > 0 { run.takers.append(takers) }
                    takers = []; touched = false
                    // a swipe at the next Jelmiko's head, as a player would (the speed that reaches it on the screen, a little off to either side)
                    let from = CGPoint(x: size.width * 0.5, y: size.height * 0.83)
                    let tgt = rs[[1, 0, 2, 1, 2, 0][round % 6]].brain.position
                    let head = GameCamera.screenPoint(floor: tgt, y: BobShape.H, size: size) ?? CGPoint(x: size.width / 2, y: size.height / 2)
                    let off: CGFloat = [0, 0.03, -0.03][round % 3] * size.width; round += 1
                    let dx = head.x + off - from.x, dy = head.y - from.y, L = max(hypot(dx, dy), 1)
                    let sp = (L / size.height) / TossAim.reach * size.height
                    p.flick(from: from, velocity: CGVector(dx: dx / L * sp, dy: dy / L * sp))
                    throwAt = p.clock; run.tosses += 1
                    settle = t + 1.2
                }
            }
            guard t > 4 else { prev = rs.map(\.brain.position); continue }
            run.steps += 1
            // the frame: where each body is on the screen, hops and all
            var cutNow = false
            for r in rs { let c = Self.cut(r.brain.position, size: size); run.worstCut = max(run.worstCut, c); if c > 1 { cutNow = true } }
            if cutNow { run.cutSteps += 1 }
            if p.phase == .flying || p.phase == .loose {
                run.liveSeconds += dt
                for (i, r) in rs.enumerated() { if simd_distance(r.brain.position, prev[i]) / dt > 0.35 { movedAcc[i] += dt } }
                if p.ball.resting || p.phase == .loose && p.ball.onFloor && p.ball.speedXZ < 0.3 {
                    let c = ballOnScreen(p.ball, size: size); run.ballChecks += 1; run.worstBall = max(run.worstBall, c); if c > 1 { run.ballOff += 1 }
                }
            }
            if p.phase == .catching { let c = ballOnScreen(p.ball, size: size); run.ballChecks += 1; run.worstBall = max(run.worstBall, c); if c > 1 { run.ballOff += 1 } }
            prev = rs.map(\.brain.position)
        }
        run.seconds = t - 4
        run.moveShare = movedAcc.map { run.liveSeconds > 0 ? $0 / run.liveSeconds : 0 }
        p.end()
        TossTuning.zBack = -2.4; TossTuning.zFront = 9
        PlayTuning.old = false
        return run
    }

    func describe(_ name: String, _ runs: [Run]) -> String {
        let secs = runs.reduce(0) { $0 + $1.seconds }, live = runs.reduce(0) { $0 + $1.liveSeconds }
        let move = (0..<3).map { k in runs.reduce(0) { $0 + $1.moveShare[k] * $1.liveSeconds } / max(live, 1) }
        let ft = runs.flatMap(\.firstTouch).sorted()
        let takers = runs.flatMap(\.takers)
        let n = Float(max(takers.count, 1))
        let share = (1...3).map { k in Float(takers.filter { $0.count == k }.count) / n }
        let touches = (0..<3).map { k in runs.reduce(0) { $0 + $1.perJellyTouches[k] } }
        return String(format: "%@ | runs %d, %.0f s | live ball %.0f%% | move share per jelly %.0f%% %.0f%% %.0f%% (mean %.0f%%) | throw->first touch median %.2f s mean %.2f s (n %d) | returns/min %.2f (throws %d) | takers per throw: 1 %.0f%% 2 %.0f%% 3 %.0f%% mean %.2f | touches by jelly %@ | cut steps %d/%d worst %.0f pt | ball off-screen checks %d/%d worst %.0f pt",
                      name, runs.count, secs, 100 * live / max(secs, 1), 100 * move[0], 100 * move[1], 100 * move[2], 100 * (move[0] + move[1] + move[2]) / 3,
                      ft.isEmpty ? 0 : ft[ft.count / 2], ft.isEmpty ? 0 : ft.reduce(0, +) / Float(ft.count), ft.count,
                      Float(runs.reduce(0) { $0 + $1.catches }) / max(secs / 60, 0.01), runs.reduce(0) { $0 + $1.tosses },
                      100 * share[0], 100 * share[1], 100 * share[2], Float(takers.reduce(0) { $0 + $1.count }) / n, "\(touches)",
                      runs.reduce(0) { $0 + $1.cutSteps }, runs.reduce(0) { $0 + $1.steps }, Double(runs.map(\.worstCut).max() ?? 0),
                      runs.reduce(0) { $0 + $1.ballOff }, runs.reduce(0) { $0 + $1.ballChecks }, Double(runs.map(\.worstBall).max() ?? 0))
    }

    /// BEFORE / AFTER table (printed; written to the scratchpad when PF_OUT is set).
    func testMeasure() {
        let mode = ProcessInfo.processInfo.environment["PF_MODE"] ?? UserDefaults.standard.string(forKey: "PFMode") ?? "both"
        var lines = ""
        for kind in [DecorKind.ball, .beachball] {
            for (sname, size) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
                for old in (mode == "both" ? [true, false] : [mode == "old"]) {
                    let runs = (0..<3).map { session(kind: kind, seed: $0, size: size, old: old) }
                    let l = describe("\(old ? "OLD" : "NEW") \(kind.rawValue) \(sname)", runs)
                    print("PFMEASURE " + l); lines += l + "\n"
                }
            }
        }
        try? lines.write(toFile: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/4c5ade4b-a768-4e5e-a1b1-52f2de759290/scratchpad/playframe/measure-\(mode).txt", atomically: true, encoding: .utf8)
    }

    // MARK: the bubble wand

    struct WandRun { var steps = 0, cutSteps = 0, worstCut: CGFloat = 0, pops = 0 }

    func wandSession(seed: Int, size: CGSize, seconds: Int = 60, old: Bool) -> WandRun {
        PlayTuning.old = old
        let wand = BubbleWand.shared
        wand.resetForTests()
        Self.room(size)
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        let start: [SIMD2<Float>] = [SIMD2(-1.6, 0.2), SIMD2(0, 1.4), SIMD2(1.6, 0.2)]
        let rs: [MotionRig] = start.enumerated().map { i, s in
            let r = MotionRig(game: true, settle: 0.5)
            Self.keep.append(r)
            r.renderSamples = false
            r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = UInt64(seed * 31 + i * 7 + 5)
            r.sim.teleport(toXZ: s); r.run(0.3)
            return r
        }
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        defer { AudioHub.dropTap = nil; AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() } }
        var now = 70_000.0 + Double(seed) * 1000; AudioHub.clock = { now }
        let p = PlayToss(); p.viewSize = size
        p.beginToy(title: "Bubble wand", snapCamera: true)
        wand.viewSize = size
        wand.activate(care: nil)
        wand.demo = { _ in 0.7 }
        let js = rs.enumerated().map { BubbleJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) }
        var run = WandRun()
        for i in 0..<(60 * seconds) {
            for r in rs { r.tick() }
            wand.tick(jellies: js, dt: 1.0 / 60)
            now += 1.0 / 60
            guard i > 60 * 4 else { continue }
            run.steps += 1
            var cutNow = false
            for r in rs { let c = Self.cut(r.brain.position, size: size); run.worstCut = max(run.worstCut, c); if c > 1 { cutNow = true } }
            if cutNow { run.cutSteps += 1 }
        }
        run.pops = wand.popsByJelly.values.reduce(0, +)
        wand.deactivate(); p.end(); wand.resetForTests()
        PlayTuning.old = false
        return run
    }

    func testMeasureWand() {
        var lines = ""
        for old in [true, false] {
            for (sname, size) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
                let runs = (0..<3).map { wandSession(seed: $0, size: size, old: old) }
                let l = String(format: "%@ wand %@ | steps %d | cut steps %d | worst cut %.0f pt | pops %d", old ? "OLD" : "NEW", sname, runs.reduce(0) { $0 + $1.steps }, runs.reduce(0) { $0 + $1.cutSteps }, Double(runs.map(\.worstCut).max() ?? 0), runs.reduce(0) { $0 + $1.pops })
                print("PFWAND " + l); lines += l + "\n"
            }
        }
        try? lines.write(toFile: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/4c5ade4b-a768-4e5e-a1b1-52f2de759290/scratchpad/playframe/measure-wand.txt", atomically: true, encoding: .utf8)
    }
}
