//
//  TrickStageTwoTests.swift
//  Focused checks of the stage-2 tricks (trick plan): hula, super spring, corkscrew jump, one-leg spin. The feet / OnePiece invariants are in EmoteFeetTests and
//  OnePieceInvariantTests; the Shop rows in TrickStoreTests; the words in VoiceTrainingTests. These are the moves' own numbers.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TrickStageTwoTests: XCTestCase {
    override func setUp() { super.setUp(); EmoteFeetTests.reset() }
    override func tearDown() { EmoteFeetTests.reset(); super.tearDown() }

    /// Runs `kind` from a game brain (as the Tricks button does: commanded) and calls `each` every tick until the move is over (or `seconds`).
    private func run(_ kind: IdleKind, seconds: Float, fail: Bool = false, character: Int = 0, each: @escaping (MotionRig) -> Void) -> MotionRig {
        let r = MotionRig(game: true)
        r.brain.idleForced = true; r.brain.commanded = true
        r.brain.idleState.trickFailNext = fail
        XCTAssertTrue(r.brain.idleStart(kind, r.sim), "\(kind) did not start")
        var started = false
        r.run(seconds, until: { if r.brain.idleState.kind == nil && started { return true }; if r.brain.idleState.phase >= 1 { started = true }; return false }, each: { each(r) })
        return r
    }

    // MARK: the typed / spoken words (RuleParser)

    private static let ruleWords: [(String, VoiceTrick)] = [("do the hula", .hula), ("hula", .hula), ("Bob hula dance", .hula), ("super spring", .superSpring), ("do a super spring", .superSpring), ("corkscrew jump", .corkscrew), ("do a corkscrew", .corkscrew), ("spin around", .spin), ("jump", .jacks)]
    func testRuleParserFindsTheStageTwoWords() {
        let n = "TrickStageTwoTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: n) }
        let names = JellyNames(defaults: UserDefaults(suiteName: n)!, key: "nick", persists: true)
        names.roster = [0, 1, 2, 3]
        let cat = AICatalogRegistry.catalog(jellies: [(0, "Bob"), (1, "Pip"), (2, "Moss")])
        for (said, t) in Self.ruleWords { XCTAssertEqual(RuleParser.parse(said, names: names, catalog: cat).command.action, .trick(t), said) }
    }

    // MARK: hula

    /// The base circles (the root swings by at least the hip radius) while the head stays over the spot, it speeds up, and he ends on the spot he started from.
    func testHulaCirclesTheHipsAndKeepsTheHeadOverTheSpot() {
        var hip: [SIMD2<Float>] = [], head: [SIMD2<Float>] = [], times: [Float] = []
        var top = -1
        var base = SIMD2<Float>.zero
        let r = run(.hula, seconds: 8) { r in
            if top < 0 { var best: Float = -.infinity; for i in 0..<(r.sim.x.count / 3) where r.sim.x[3 * i + 1] > best { best = r.sim.x[3 * i + 1]; top = i } }
            guard r.brain.idleState.kind == .hula, r.brain.idleState.phase >= 1 else { return }
            if hip.isEmpty { base = r.brain.idleState.trick.base }
            hip.append(SIMD2(r.brain.px, r.brain.pz)); head.append(SIMD2(r.sim.x[3 * top], r.sim.x[3 * top + 2])); times.append(r.brain.idleState.phaseT)
        }
        XCTAssertGreaterThan(hip.count, 150, "the hula ran")
        // the window where the circle is at full size (s in 1.2 ... 2.6)
        let idx = times.indices.filter { times[$0] > 1.2 && times[$0] < 2.6 }
        func spread(_ p: [SIMD2<Float>]) -> Float { let m = idx.reduce(SIMD2<Float>.zero) { $0 + p[$1] } / Float(idx.count); return idx.map { simd_length(p[$0] - m) }.max() ?? 0 }
        let hipR = spread(hip), headR = spread(head)
        MotionLog.write(String(format: "HULA hip radius %.3f u, head radius %.3f u", hipR, headR))
        XCTAssertGreaterThan(hipR, 0.08, "the hips circle (8 cm or more)")
        XCTAssertLessThan(headR, 0.8 * hipR, "the head stays over the spot: it moves far less than the hips (the counter-tilt; not the dizzy wobble, where the crown circles)")
        XCTAssertLessThan(simd_length(hip.last! - base), 0.002, "back on the spot he started from")
        // it speeds up: more root-circle turns in the last second of the swing than in the first
        func turns(_ lo: Float, _ hi: Float) -> Float {
            var a: Float = 0; var prev: Float?
            for i in hip.indices where times[i] >= lo && times[i] < hi { let d = hip[i] - base; let ang = atan2f(d.y, d.x); if let p = prev { var da = ang - p; while da > .pi { da -= 2 * .pi }; while da < -.pi { da += 2 * .pi }; a += abs(da) }; prev = ang }
            return a / (2 * .pi)
        }
        XCTAssertGreaterThan(turns(1.9, 2.9), 1.3 * turns(0.3, 1.3), "the circle speeds up")
        XCTAssertNil(r.brain.idleState.kind, "the move ends")
    }

    /// The Show's flop: the same circle, faster and bigger, then the dizzy wobble.
    func testHulaFailEndsInTheDizzyWobble() {
        var kinds = Set<IdleKind>()
        _ = run(.hula, seconds: 9, fail: true) { r in if let k = r.brain.idleState.kind { kinds.insert(k) } }
        XCTAssertTrue(kinds.contains(.hula)); XCTAssertTrue(kinds.contains(.dizzyWobble), "the flop spins out into the dizzy wobble")
    }

    // MARK: super spring

    /// A plain hop's rise (the centroid's, in u), for the comparison.
    private func plainHopRise() -> Float {
        let r = MotionRig(game: true)
        r.brain.startHopPlay(sim: r.sim)
        var lo = Float.infinity, hi: Float = -.infinity
        r.run(2.0, each: { let y = r.sim.centroid().y; if r.brain.activity == .playing { lo = min(lo, y); hi = max(hi, y) } })
        return hi - r.sim.restCentroid.y
    }

    /// Squashes very low and holds it, launches about twice a normal hop, a big landing, and puts the gait knobs back.
    func testSuperSpringIsDeepHeldAndAboutTwiceAHop() {
        let rest = MotionRig(game: true).sim.restCentroid.y
        var maxY: Float = -.infinity, minSq: Float = 1, holdTicks = 0, landMin: Float = 1, landing = false, kicked: Float = 0
        let r = run(.superSpring, seconds: 8) { r in
            guard r.brain.idleState.kind == .superSpring, r.brain.idleState.phase >= 1 else { return }
            maxY = max(maxY, r.sim.centroid().y)
            let sq = r.sim.attractor.squash
            if r.brain.gait.phase == .crouch { minSq = min(minSq, sq); if sq < 0.76 { holdTicks += 1 } }
            if r.brain.gait.phase == .land { landing = true }
            if landing, r.brain.gait.phase == .land { landMin = min(landMin, sq) }
            kicked = max(kicked, r.brain.jellyKick)
        }
        let rise = maxY - rest, hop = plainHopRise()
        MotionLog.write(String(format: "SPRING rise %.3f u (plain hop %.3f) deepest crouch squash %.2f held %.2f s, landing squash %.2f, kick %.1f", rise, hop, minSq, Float(holdTicks) / 60, landMin, kicked))
        XCTAssertGreaterThan(rise, 1.6 * hop, "about twice a normal hop")
        XCTAssertLessThan(minSq, 0.77, "squashes very low")
        XCTAssertGreaterThan(Float(holdTicks) / 60, 0.2, "the squash is held")
        XCTAssertLessThan(landMin, 0.82, "a big landing squash")
        XCTAssertGreaterThanOrEqual(kicked, 3.0, "a big landing jiggle")
        XCTAssertNil(r.brain.idleState.kind, "the move ends")
        let g = r.brain.gait
        XCTAssertEqual(g.crouchDepth, 0.18); XCTAssertEqual(g.crouchHold, 0); XCTAssertEqual(g.airStretch, 0.12); XCTAssertEqual(g.landDepth, 0.2, "the knobs are back to the ordinary hop's")
        XCTAssertEqual(r.brain.gait.hopApex, 0.10, accuracy: 1e-6)
    }

    func testSuperSpringFlopIsAWeakHopAndALurch() {
        var maxY: Float = -.infinity, pitchMax: Float = 0, ok = false
        let rest = MotionRig(game: true).sim.restCentroid.y
        _ = run(.superSpring, seconds: 8, fail: true) { r in
            guard r.brain.idleState.kind == .superSpring, r.brain.idleState.phase >= 1 else { return }
            ok = true; maxY = max(maxY, r.sim.centroid().y); pitchMax = max(pitchMax, r.brain.gait.basePitch)
        }
        XCTAssertTrue(ok)
        XCTAssertLessThan(maxY - rest, 0.5 * plainHopRise() + 0.08, "the flop barely leaves the floor")
        XCTAssertGreaterThan(pitchMax, 0.08, "the forward lurch")
    }

    // MARK: corkscrew

    private func wrapDelta(_ d: Float) -> Float { var x = d; while x > .pi { x -= 2 * .pi }; while x < -.pi { x += 2 * .pi }; return x }

    /// A high jump with ONE full twist about the vertical axis (the body's heading turns a whole turn in the air), a squishy landing on the heading he left, a held ta-da.
    func testCorkscrewTwistsOnceAndLandsOnItsHeading() {
        let rest = MotionRig(game: true).sim.restCentroid.y
        var prev: Float?, first: Float = 0, turned: Float = 0, maxY: Float = -.infinity, sawTada = false, minSq: Float = 1, last: Float = 0, kicked: Float = 0
        let r = run(.corkscrew, seconds: 8) { r in
            guard r.brain.idleState.kind == .corkscrew, r.brain.idleState.phase >= 1 else { return }
            if r.brain.idleState.phase == 2 { sawTada = true }
            let y = r.sim.bodyPose(iterations: 4).yaw
            if let p = prev { turned += self.wrapDelta(y - p) } else { first = y }
            prev = y; last = y
            maxY = max(maxY, r.sim.centroid().y); minSq = min(minSq, r.sim.attractor.squash); kicked = max(kicked, r.brain.jellyKick)
        }
        MotionLog.write(String(format: "CORKSCREW turned %.2f rad, rise %.3f, deepest squash %.2f, kick %.1f, ends %.2f rad off its heading", turned, maxY - rest, minSq, kicked, wrapDelta(last - first)))
        XCTAssertGreaterThan(abs(turned), 2 * .pi * 0.92, "one full twist"); XCTAssertLessThan(abs(turned), 2 * .pi * 1.10)
        XCTAssertGreaterThan(maxY - rest, 0.24, "a high jump")
        XCTAssertLessThan(minSq, 0.80, "a squishy landing and crouch")
        XCTAssertEqual(wrapDelta(last - first), 0, accuracy: 0.30, "lands on the heading he left")
        XCTAssertTrue(sawTada, "the held ta-da"); XCTAssertGreaterThanOrEqual(kicked, 2.5)
        XCTAssertNil(r.brain.idleState.kind); XCTAssertEqual(r.brain.gait.flipTwist, 0, "the twist knob is cleared for the next flip")
    }

    /// The Show's flop: 1.5 turns, he lands sideways, then the dizzy wobble.
    func testCorkscrewFlopLandsSidewaysAndGoesDizzy() {
        var kinds = Set<IdleKind>(), first: Float?, afterLand: Float = 0
        _ = run(.corkscrew, seconds: 9, fail: true) { r in
            if let k = r.brain.idleState.kind { kinds.insert(k) }
            if r.brain.idleState.kind == .corkscrew, r.brain.idleState.phase >= 1, first == nil { first = r.sim.bodyPose(iterations: 4).yaw }
            if r.brain.idleState.kind == .dizzyWobble, afterLand == 0, let f = first { afterLand = abs(self.wrapDelta(r.sim.bodyPose(iterations: 4).yaw - f)) }
        }
        XCTAssertTrue(kinds.contains(.corkscrew) && kinds.contains(.dizzyWobble), "ends in the dizzy wobble")
        XCTAssertEqual(afterLand, 0.5 * .pi, accuracy: 0.5, "he lands about a quarter turn off")
    }
}
