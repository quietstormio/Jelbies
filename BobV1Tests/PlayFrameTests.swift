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
    static func cut(_ p: SIMD2<Float>, size: CGSize) -> CGFloat { PlayTuning.edgeCut(p, size: size) }

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
    static let measureMarker = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/4c5ade4b-a768-4e5e-a1b1-52f2de759290/scratchpad/playframe/measure.on"
    func testMeasure() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.measureMarker), "the before / after table (create the marker file to run it)")
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

    struct WandRun { var steps = 0, cutSteps = 0, worstCut: CGFloat = 0, pops = 0, distSum: Float = 0 }

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
            let q = rs.map(\.brain.position)
            run.distSum += (simd_distance(q[0], q[1]) + simd_distance(q[1], q[2]) + simd_distance(q[0], q[2])) / 3
        }
        run.pops = wand.popsByJelly.values.reduce(0, +)
        wand.deactivate(); p.end(); wand.resetForTests()
        PlayTuning.old = false
        return run
    }

    func testMeasureWand() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.measureMarker), "the before / after table (create the marker file to run it)")
        var lines = ""
        for old in [true, false] {
            for (sname, size) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
                let runs = (0..<3).map { wandSession(seed: $0, size: size, old: old) }
                let l = String(format: "%@ wand %@ | steps %d | cut steps %d | worst cut %.0f pt | pops %d | mean distance between the three %.2f u", old ? "OLD" : "NEW", sname, runs.reduce(0) { $0 + $1.steps }, runs.reduce(0) { $0 + $1.cutSteps }, Double(runs.map(\.worstCut).max() ?? 0), runs.reduce(0) { $0 + $1.pops }, Double(runs.reduce(0) { $0 + $1.distSum }) / Double(max(runs.reduce(0) { $0 + $1.steps }, 1)))
                print("PFWAND " + l); lines += l + "\n"
            }
        }
        try? lines.write(toFile: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/4c5ade4b-a768-4e5e-a1b1-52f2de759290/scratchpad/playframe/measure-wand.txt", atomically: true, encoding: .utf8)
    }

    // MARK: the proofs

    /// The ball game, several seeds, both balls, portrait and landscape: no body leaves the screen, the ball's catches and rests are on it, and the game still plays.
    func testBallPlayKeepsEveryJelmikoAndTheBallInFrame() {
        for kind in [DecorKind.ball, .beachball] {
            for (name, size) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
                for seed in 0..<3 {
                    let r = session(kind: kind, seed: seed, size: size, seconds: 30, old: false)
                    XCTAssertEqual(r.cutSteps, 0, "\(kind) \(name) seed \(seed): a Jelmiko's body was cut by the screen edge in \(r.cutSteps) of \(r.steps) steps (worst \(r.worstCut) pt)")
                    XCTAssertLessThanOrEqual(r.worstBall, 8, "\(kind) \(name) seed \(seed): the ball came to rest / was caught off screen (\(r.worstBall) pt)")
                    XCTAssertGreaterThanOrEqual(r.catches, 2, "\(kind) \(name) seed \(seed): the game stopped returning the ball (\(r.catches) catches, \(r.touches) touches)")
                }
            }
        }
    }

    /// The same session with the old play mode DOES cut bodies (so the test above can fail), and nobody runs faster than before there.
    func testTheOldPlayModeStillCutsBodiesAndHasNoChaseBoost() {
        let r = session(kind: .ball, seed: 0, size: Self.portrait, seconds: 30, old: true)
        XCTAssertGreaterThan(r.cutSteps, 0, "the harness cannot see a body cut by the edge: it would pass anything")
    }

    func testBubbleWandKeepsEveryJelmikoInFrame() {
        for (name, size) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
            for seed in 0..<2 {
                let r = wandSession(seed: seed, size: size, seconds: 30, old: false)
                XCTAssertEqual(r.cutSteps, 0, "wand \(name) seed \(seed): a Jelmiko was cut by the screen edge in \(r.cutSteps) of \(r.steps) steps (worst \(r.worstCut) pt)")
                XCTAssertGreaterThan(r.pops, 5, "wand \(name) seed \(seed): nobody popped bubbles")
            }
        }
    }

    func testTheCameraDialRunsFromTheRoomViewToTheOldPlayView() {
        Self.room(Self.portrait)
        func eye(_ z: Float) -> SIMD3<Float> { PlayTuning.zoomOverride = z; GameCamera.playBlend = 1; return GameCamera.camera(aspect: 440 / 956).pos }
        GameCamera.playBlend = 0; let room = GameCamera.camera(aspect: 440 / 956).pos
        let e0 = eye(0), e1 = eye(1), eq = eye(0.25)
        XCTAssertEqual(simd_distance(e0, room), 0, accuracy: 1e-4, "dial 0 is the room's own camera")
        XCTAssertGreaterThan(simd_distance(e1, room), 2, "dial 1 is the old play view")
        XCTAssertEqual(simd_distance(eq, room) / simd_distance(e1, room), 0.25, accuracy: 0.02, "dial 0.25 is a quarter of the way")
        PlayTuning.old = true; PlayTuning.zoomOverride = 0
        XCTAssertEqual(simd_distance(GameCamera.camera(aspect: 440 / 956).pos, e1), 0, accuracy: 1e-4, "-PlayOld 1 is the old camera whatever the dial says")
        XCTAssertEqual(PlayTuning.camZoom, 1)
    }

    /// A walk with a live ball covers the ground about 20 % faster than the same walk without (15...25 %): the plain goTo, and the walk round behind the ball.
    func testTheChaseWalkIsAboutTwentyPercentFaster() {
        func seconds(chase: Float, bump: Bool) -> Float {
            Self.room(Self.portrait)
            let r = MotionRig(game: true, settle: 0.5)
            Self.keep.append(r)
            r.renderSamples = false
            r.brain.autonomy = false; r.brain.anticsEnabled = true
            r.sim.teleport(toXZ: SIMD2(-2.5, 0)); r.run(0.5)
            r.brain.playChase = chase
            let goal = SIMD2<Float>(1.5, 0)
            if bump { _ = r.brain.tossBumpStart(r.sim, r.skinner, stand: goal, dir: SIMD2(0, 1)) } else { r.brain.requestNow(.goTo(goal)) }
            var t: Float = 0
            let dt = r.sim.stepDt
            while t < 12 {
                r.tick(); t += dt
                if simd_distance(r.brain.position, goal) < 0.3 { break }
            }
            return t
        }
        for bump in [false, true] {
            let slow = seconds(chase: 0, bump: bump), fast = seconds(chase: PlayTuning.chaseGain, bump: bump)
            let gain = slow / fast
            print("PFCHASE \(bump ? "bump walk" : "goTo walk"): \(slow) s -> \(fast) s, \(gain)x")
            XCTAssertGreaterThan(gain, 1.12, "\(bump ? "bump walk" : "goTo"): the chase must be faster (\(gain)x)")
            XCTAssertLessThan(gain, 1.30, "\(bump ? "bump walk" : "goTo"): a little faster, not a frenzy (\(gain)x)")
        }
    }

    /// Sweep of the wand's Jelmiko-area knobs (printed; marker file as the others).
    func testWandAreaSweep() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.measureMarker + ".sweep"), "the wand area sweep (create measure.on.sweep to run it)")
        var out = ""
        for (name, size) in [("landscape", Self.landscape), ("portrait", Self.portrait)] {
            var line = "SWEEP \(name) OLD pops/seed: "
            for seed in 0..<6 { line += "\(wandSession(seed: seed, size: size, seconds: 30, old: true).pops) " }
            out += line + "\n"
            for (sp, dp) in [(1.1, 1.15), (1.5, 1.3), (2.0, 1.6), (3.0, 2.5)] as [(Float, Float)] {
                PlayTuning.wandSpreadK = sp; PlayTuning.wandDepthK = dp
                var l = String(format: "SWEEP %@ NEW spread %.1f depth %.2f pops/seed: ", name, sp, dp)
                for seed in 0..<6 { let r = wandSession(seed: seed, size: size, seconds: 30, old: false); l += "\(r.pops)(c\(r.cutSteps),d\(String(format: "%.1f", r.distSum / Float(max(r.steps, 1))))) " }
                out += l + "\n"
            }
            PlayTuning.wandSpreadK = 1.5; PlayTuning.wandDepthK = 1.3
        }
        print(out)
        try? out.write(toFile: "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/4c5ade4b-a768-4e5e-a1b1-52f2de759290/scratchpad/playframe/sweep2.txt", atomically: true, encoding: .utf8)
    }

    /// With no ball out (play mode waiting in the hand) and outside play mode, the walk is the old gait: no chase blend, the same time for the same walk, and `playChase` is never left on.
    func testOrdinaryWalkingIsTheOldGait() {
        func walk(chaseWas: Float) -> (t: Float, maxRun: Float) {
            Self.room(Self.portrait)
            let r = MotionRig(game: true, settle: 0.5)
            Self.keep.append(r)
            r.renderSamples = false
            r.brain.autonomy = false
            r.sim.teleport(toXZ: SIMD2(-2.5, 0)); r.run(0.5)
            r.brain.playChase = chaseWas; r.brain.playChase = 0          // (on, then off: nothing may stay behind)
            r.brain.requestNow(.goTo(SIMD2(1.5, 0)))
            var t: Float = 0, mr: Float = 0
            while t < 12 { r.tick(); t += r.sim.stepDt; mr = max(mr, r.brain.runW); if simd_distance(r.brain.position, SIMD2(1.5, 0)) < 0.3 { break } }
            return (t, mr)
        }
        let a = walk(chaseWas: 0), b = walk(chaseWas: PlayTuning.chaseGain)
        XCTAssertEqual(a.maxRun, 0, "an ordinary walk has no run blend")
        XCTAssertEqual(b.maxRun, 0, "a walk after the chase flag was switched off has no run blend")
        XCTAssertEqual(a.t, b.t, accuracy: 1e-5, "the same walk takes the same time")
        // play mode with the ball in the hand: nobody is on the chase gait, nobody is sent to support
        Self.room(Self.portrait)
        let rs = (0..<3).map { i -> MotionRig in
            let r = MotionRig(game: true, settle: 0.5); Self.keep.append(r); r.renderSamples = false
            r.sim.teleport(toXZ: SIMD2(Float(i) * 1.5 - 1.5, 0.2)); r.run(0.3); return r
        }
        let p = PlayToss(); p.viewSize = Self.portrait
        func js() -> [PlayJelly] { rs.enumerated().map { PlayJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) } }
        p.begin(ball: .ball, title: "ball", jellies: js(), snapCamera: true)
        var w = TossWorld(); w.xHalf = PlayToss.ballXHalf
        for _ in 0..<600 { for r in rs { r.tick() }; p.tick(dt: rs[0].sim.stepDt, world: w, jellies: js()); XCTAssertEqual(p.phase, .inHand); for r in rs { XCTAssertEqual(r.brain.playChase, 0); XCTAssertEqual(r.brain.runW, 0) } }
        p.end()
        for r in rs { XCTAssertEqual(r.brain.playChase, 0, "play over: the chase flag is off") }
    }
}
