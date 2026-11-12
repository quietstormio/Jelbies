//
//  TrickStageThreeTests.swift
//  Focused checks of the stage-3 prototypes (trick plan): moonwalk, back bounce, headstand. The feet / OnePiece invariants are in EmoteFeetTests and OnePieceInvariantTests;
//  the Shop rows in TrickStoreTests; the words in VoiceTrainingTests; the locked walk's golden in WalkGoldenTests. These are the moves' own numbers.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TrickStageThreeTests: XCTestCase {
    override func setUp() { super.setUp(); EmoteFeetTests.reset() }
    override func tearDown() { EmoteFeetTests.reset(); super.tearDown() }

    private func run(_ kind: IdleKind, seconds: Float, fail: Bool = false, each: @escaping (MotionRig) -> Void) -> MotionRig {
        let r = MotionRig(game: true)
        r.brain.idleForced = true; r.brain.commanded = true
        r.brain.idleState.trickFailNext = fail
        XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) did not start")
        var started = false
        r.run(seconds, until: { if r.brain.idleState.kind == nil && started { return true }; if r.brain.idleState.phase >= 1 { started = true }; return false }, each: { each(r) })
        return r
    }
    private func wrapDelta(_ d: Float) -> Float { var x = d; while x > .pi { x -= 2 * .pi }; while x < -.pi { x += 2 * .pi }; return x }

    // MARK: words

    private static let ruleWords: [(String, VoiceTrick)] = [("moonwalk", .moonwalk), ("do the moonwalk", .moonwalk), ("moon walk", .moonwalk), ("back bounce", .backBounce), ("do a back bounce", .backBounce), ("bounce on your back", .backBounce),
                                                            ("headstand", .headstand), ("do a headstand", .headstand), ("stand on your head", .headstand), ("head stand", .headstand), ("bounce", .hop), ("bounce around", .hop), ("do a flip", .flip)]
    func testRuleParserFindsTheStageThreeWords() {
        let n = "TrickStageThreeTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: n) }
        let names = JellyNames(defaults: UserDefaults(suiteName: n)!, key: "nick", persists: true)
        names.roster = [0, 1, 2, 3]
        let cat = AICatalogRegistry.catalog(jellies: [(0, "Bob"), (1, "Pip"), (2, "Moss")])
        for (said, t) in Self.ruleWords { XCTAssertEqual(RuleParser.parse(said, names: names, catalog: cat).command.action, .trick(t), said) }
    }

    // MARK: the pure profile of the tipped tricks

    /// No jumps: the pose changes smoothly through every beat; it starts and ends upright, on the heading it had.
    func testAcroProfilesAreContinuousAndEndUpright() {
        for kind in [IdleKind.backBounce, .headstand] {
            for fail in [false, true] {
                let end = AcroProfile.total(kind, fail: fail)
                var prev = AcroProfile(kind, t: 0, fail: fail)
                var maxDP: Float = 0, maxDL: Float = 0, maxTilt: Float = 0
                var t: Float = 1.0 / 240
                while t <= end + 0.05 {
                    let p = AcroProfile(kind, t: t, fail: fail)
                    maxDP = max(maxDP, abs(p.pitch - prev.pitch)); maxDL = max(maxDL, abs(p.lift - prev.lift) + abs(p.dip - prev.dip) + abs(p.back - prev.back))
                    maxTilt = max(maxTilt, kind == .headstand ? min(p.pitch, 2 * .pi - p.pitch) : -p.pitch)
                    prev = p; t += 1.0 / 240
                }
                let who = "\(kind)\(fail ? " flop" : "")"
                XCTAssertLessThan(maxDP, 0.08, "\(who): no pitch jump (rad per 1/240 s)"); XCTAssertLessThan(maxDL, 0.02, "\(who): no anchor jump")
                XCTAssertEqual(prev.beat, .done, who)
                XCTAssertEqual(wrapDelta(prev.pitch), 0, accuracy: 1e-4, "\(who): ends upright"); XCTAssertEqual(prev.squash, 1, accuracy: 0.01, who)
                XCTAssertGreaterThan(maxTilt, kind == .headstand ? 2.6 : 1.3, "\(who): turned over")
            }
        }
    }

    // MARK: moonwalk

    /// The body glides BACKWARD (against its heading) at a steady speed with no bob, the feet take turns (one pinned while the other slides back), then the point and the walk back.
    func testMoonwalkGlidesBackwardWithoutBobbing() {
        var heading: Float = 0, start = SIMD2<Float>.zero, maxBack: Float = 0, ys: [Float] = [], moved: [Int] = [0, 0], sawWalk = false
        var lastFeet: [SIMD2<Float>]?
        let r = run(.moonwalk, seconds: 14) { r in
            guard r.brain.idleState.kind == .moonwalk else { return }
            if r.brain.idleState.phase == 1, start == .zero { start = r.brain.idleState.trick.base; heading = r.brain.yaw }
            if r.brain.idleState.phase == 2 {
                let fwd = SIMD2<Float>(sinf(heading), cosf(heading))
                maxBack = max(maxBack, -simd_dot(SIMD2(r.brain.px, r.brain.pz) - start, fwd))
                let u = r.brain.idleState.phaseT.truncatingRemainder(dividingBy: MoonwalkTuning.glide) / MoonwalkTuning.glide
                if u > 0.3, u < 0.7 { ys.append(r.sim.centroid().y) }
                if let lf = lastFeet { for s in 0..<2 where simd_length(r.brain.feet.pos[s] - lf[s]) > 1e-4 { moved[s] += 1 } }
                lastFeet = r.brain.feet.pos
                XCTAssertLessThan(abs(self.wrapDelta(r.brain.yaw - heading)), 0.01, "faces the same way while gliding back")
            }
            if r.brain.idleState.phase == MoonwalkTuning.walkBackPhase { sawWalk = true }
        }
        let mean = ys.reduce(0, +) / Float(max(1, ys.count))
        let bob = ys.map { abs($0 - mean) }.max() ?? 1
        MotionLog.write(String(format: "MOONWALK back %.3f u, mid-glide centroid bob %.4f u, foot slide ticks %d / %d, walked back %@, ends %.3f u from the start", maxBack, bob, moved[0], moved[1], sawWalk ? "yes" : "no", simd_length(SIMD2(r.brain.px, r.brain.pz) - start)))
        XCTAssertGreaterThan(maxBack, 0.30, "glides back a real distance"); XCTAssertLessThan(bob, 0.012, "no bob through the slides")
        XCTAssertGreaterThan(moved[0], 30); XCTAssertGreaterThan(moved[1], 30, "both feet take turns sliding")
        XCTAssertTrue(sawWalk, "walks back"); XCTAssertLessThan(simd_length(SIMD2(r.brain.px, r.brain.pz) - start), 0.2, "back near his spot")
        XCTAssertNil(r.brain.idleState.kind)
    }

    func testMoonwalkFlopSlipsAndWalksBack() {
        var kinds = Set<IdleKind>(), slipped = false
        let r = run(.moonwalk, seconds: 14, fail: true) { r in if let k = r.brain.idleState.kind { kinds.insert(k) }; if r.brain.expr.kind == .worried { slipped = true } }
        XCTAssertTrue(slipped, "the slip"); XCTAssertNil(r.brain.idleState.kind)
    }

    // MARK: back bounce

    func testBackBounceLiesOnItsBackBouncesAndGetsUp() {
        var maxTilt: Float = 0, lyingTicks = 0, airborneOnBack = 0, sawTipped = false, kicked: Float = 0
        let rest = MotionRig(game: true).sim.restCentroid.y
        _ = rest
        let r = run(.backBounce, seconds: 8) { r in
            guard r.brain.idleState.kind == .backBounce, r.brain.idleState.phase == 1 else { return }
            let pose = r.sim.bodyPose(iterations: 4)
            maxTilt = max(maxTilt, pose.tilt)
            if pose.tilt > 1.1 { lyingTicks += 1; if r.sim.minY() - r.sim.floorY > 0.02 { airborneOnBack += 1 } }
            if r.brain.trickTipped { sawTipped = true }
            kicked = max(kicked, r.brain.jellyKick)
        }
        let end = r.sim.bodyPose(iterations: 6)
        MotionLog.write(String(format: "BACK BOUNCE max tilt %.2f rad, on the back %.2f s, airborne on the back %.2f s, kick %.1f, end tilt %.2f", maxTilt, Float(lyingTicks) / 60, Float(airborneOnBack) / 60, kicked, end.tilt))
        XCTAssertGreaterThan(maxTilt, 1.2, "onto his back"); XCTAssertGreaterThan(Float(airborneOnBack) / 60, 0.10, "bounces up off his back")
        XCTAssertTrue(sawTipped); XCTAssertNil(r.brain.idleState.kind); XCTAssertFalse(r.brain.trickTipped)
        XCTAssertLessThan(end.tilt, 0.35, "back on his feet")
    }

    // MARK: headstand

    func testHeadstandHoldsUpsideDownAndPopsOver() {
        var heldTicks = 0, first: Float?
        let r = run(.headstand, seconds: 8) { r in
            guard r.brain.idleState.kind == .headstand, r.brain.idleState.phase == 1 else { return }
            if first == nil { first = r.brain.idleState.trick.root.z }
            if r.sim.bodyPose(iterations: 4).tilt > 2.4 { heldTicks += 1 }
        }
        let end = r.sim.bodyPose(iterations: 6)
        MotionLog.write(String(format: "HEADSTAND upside down %.2f s, end tilt %.2f, heading off %.2f", Float(heldTicks) / 60, end.tilt, wrapDelta(r.brain.yaw - (first ?? 0))))
        XCTAssertGreaterThan(Float(heldTicks) / 60, 0.8, "a held headstand")
        XCTAssertLessThan(end.tilt, 0.35, "back on his feet"); XCTAssertNil(r.brain.idleState.kind)
        XCTAssertEqual(wrapDelta(r.brain.yaw - (first ?? 0)), 0, accuracy: 0.3, "on the heading he had")
    }

    func testTippedFlopsGetUpByThemselves() {
        for kind in [IdleKind.backBounce, .headstand] {
            var maxTilt: Float = 0
            let r = run(kind, seconds: 9, fail: true) { r in if r.brain.idleState.kind == kind { maxTilt = max(maxTilt, r.sim.bodyPose(iterations: 4).tilt) } }
            XCTAssertGreaterThan(maxTilt, 1.1, "\(kind) flop goes over"); XCTAssertNil(r.brain.idleState.kind, "\(kind) flop ends")
            XCTAssertLessThan(r.sim.bodyPose(iterations: 6).tilt, 0.35, "\(kind) flop: back on his feet")
        }
    }

    // MARK: interrupted

    /// Each stage-3 move cut short at three moments (a tap, the Show's walk-out, a voice stop: abortAll) leaves him upright within 2 s, the move over, no heel left up.
    func testAbortingAStageThreeMoveLeavesHimUprightWithinTwoSeconds() {
        let restTilt: Float = { let b = MotionRig(game: true); b.run(2); return b.sim.bodyPose(iterations: 6).tilt }()
        var report = "ABORT"
        for (kind, moments) in [(IdleKind.moonwalk, [Float(0.3), 1.2, 2.4]), (.backBounce, [0.4, 0.9, 1.5]), (.headstand, [0.5, 1.2, 2.2])] {
            for abortAt in moments {
                let r = MotionRig(game: true)
                r.brain.idleForced = true; r.brain.commanded = true
                XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind)")
                var started = false, n = 0
                r.run(8, until: { if r.brain.idleState.phase >= 1 { started = true }; if started { n += 1 }; return Float(n) / 60 >= abortAt })
                let tilt0 = r.sim.bodyPose(iterations: 4).tilt
                r.brain.abortAll(r.sim, r.skinner)
                var upAt: Float = -1, k = 0
                r.run(2.0, each: { k += 1; if upAt < 0, r.sim.bodyPose(iterations: 3).tilt < restTilt + 0.08, r.brain.activity != .recovering { upAt = Float(k) / 60 } })
                let who = "\(kind) aborted at \(abortAt) s (tilt \(String(format: "%.2f", tilt0)))"
                report += String(format: " | %@ %.1f s: tilt %.2f, upright after %.2f s", kind.rawValue, abortAt, tilt0, upAt)
                XCTAssertFalse(r.sim.hasNonFinite(), who); XCTAssertNil(r.brain.idleState.kind, who); XCTAssertFalse(r.brain.trickTipped, who)
                XCTAssertLessThan(r.sim.bodyPose(iterations: 6).tilt, restTilt + 0.08, "\(who): upright within 2 s")
                XCTAssertEqual(r.brain.armDirW, 0, who)
                r.run(1.0)
                XCTAssertFalse(r.brain.gait.isBusy, who)
            }
        }
        MotionLog.write(report)
    }
}
