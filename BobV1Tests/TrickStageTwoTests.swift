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

    private static let ruleWords: [(String, VoiceTrick)] = [("do the hula", .hula), ("hula", .hula), ("Bob hula dance", .hula), ("spin around", .spin), ("jump", .jacks)]
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
}
