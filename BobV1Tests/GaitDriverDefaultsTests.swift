//
//  GaitDriverDefaultsTests.swift
//  Trick plan stage 2 added knobs to the GaitDriver (`flipTwist`, `crouchDepth`, `crouchHold`, `airStretch`, `landDepth`). Every one defaults to today's value:
//  an ordinary hop and an ordinary flip must write the SAME attractor, tick for tick, as before the knobs existed. The golden digests below were recorded on
//  d1c5543c (before Locomotion.swift was touched).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class GaitDriverDefaultsTests: XCTestCase {
    /// One number per sampled tick: the attractor's anchor, rotation, squash and strength folded together.
    static func digest(_ start: (MotionRig) -> Void, seconds: Float) -> [Double] {
        let r = MotionRig(game: false)
        start(r)
        var out: [Double] = [], n = 0
        r.run(seconds, each: {
            n += 1
            guard n % 4 == 0 else { return }
            let a = r.sim.attractor
            let v = Double(a.anchor.x) + 3 * Double(a.anchor.y) + 5 * Double(a.anchor.z) + 7 * Double(a.squash) + 11 * Double(a.rotation.vector.x) + 13 * Double(a.rotation.vector.y) + 17 * Double(a.rotation.vector.z) + 19 * Double(a.rotation.vector.w) + 0.001 * Double(a.strength)
            out.append((v * 1e4).rounded() / 1e4)
        })
        return out
    }
    static func literal(_ a: [Double]) -> String { "[" + a.map { String(format: "%.4f", $0) }.joined(separator: ", ") + "]" }

    func testOrdinaryHopAndFlipAreUnchangedByTheNewKnobs() {
        let hop = Self.digest({ $0.brain.startHopPlay(sim: $0.sim) }, seconds: 1.6)
        let flip = Self.digest({ $0.brain.startFlip(sim: $0.sim) }, seconds: 2.4)
        if Self.goldenHop.isEmpty {
            MotionLog.write("GOLDEN hop \(Self.literal(hop))")
            MotionLog.write("GOLDEN flip \(Self.literal(flip))")
            XCTFail("golden digests not frozen yet")
            return
        }
        XCTAssertEqual(hop.count, Self.goldenHop.count); XCTAssertEqual(flip.count, Self.goldenFlip.count)
        for (i, (a, b)) in zip(hop, Self.goldenHop).enumerated() { XCTAssertEqual(a, b, accuracy: 2e-4, "hop tick \(i * 4)") }
        for (i, (a, b)) in zip(flip, Self.goldenFlip).enumerated() { XCTAssertEqual(a, b, accuracy: 2e-4, "flip tick \(i * 4)") }
    }

    func testTheKnobsDefaultToToday() {
        let g = GaitDriver()
        XCTAssertEqual(g.flipTwist, 0); XCTAssertEqual(g.twistNow, 0); XCTAssertEqual(g.crouchDepth, 0.18); XCTAssertEqual(g.crouchHold, 0); XCTAssertEqual(g.airStretch, 0.12); XCTAssertEqual(g.landDepth, 0.2)
    }

    /// The corkscrew: the flip machinery with the turn about the vertical axis. A full twist reaches 2 pi in the air, the flip's pitch stays 0, and he lands on the heading he left.
    func testCorkscrewTwistReachesAFullTurnAndKeepsPitchAtZero() {
        for (twist, name) in [(2 * Float.pi, "clean"), (1.5 * Float.pi, "short")] {
            let r = MotionRig(game: false)
            r.brain.gait.flipTwist = twist
            r.brain.startFlip(sim: r.sim)
            var peak: Float = 0, pitchMax: Float = 0, held = false, sawLandTwist: Float = 0
            r.run(2.4, each: {
                peak = max(peak, r.brain.gait.twistNow); if r.brain.gait.phase == .air { pitchMax = max(pitchMax, abs(r.brain.gait.flipPitch)) }
                if r.brain.gait.phase == .land { sawLandTwist = r.brain.gait.twistNow }
                if r.brain.gait.phase == .crouch, r.brain.gait.twistNow != 0 { held = true }
            })
            XCTAssertEqual(peak, twist, accuracy: 0.02, "\(name): the twist reaches its full turn in the air")
            XCTAssertEqual(pitchMax, 0, "\(name): no pitch in the air while twisting")
            XCTAssertFalse(held, "\(name): no twist in the crouch")
            XCTAssertEqual(abs(sawLandTwist), name == "clean" ? 0 : 0.5 * .pi, accuracy: 0.02, "\(name): the landing heading")
            XCTAssertEqual(r.brain.gait.twistNow, 0, "\(name): the twist is cleared when the move ends")
            XCTAssertFalse(r.brain.gait.isBusy)
        }
    }

    /// The crouch hold stretches the crouch by exactly that long and nothing else.
    func testCrouchHoldDelaysTheLaunch() {
        func crouchSeconds(_ hold: Float) -> Float {
            let r = MotionRig(game: false)
            r.brain.gait.crouchHold = hold; r.brain.gait.crouchDepth = 0.30
            r.brain.startHopPlay(sim: r.sim)
            var n = 0
            r.run(1.0, until: { if r.brain.gait.phase == .air { return true }; n += 1; return false })
            return Float(n) / 60
        }
        XCTAssertEqual(crouchSeconds(0.25) - crouchSeconds(0), 0.25, accuracy: 0.03)
    }

    static let goldenHop: [Double] = [27.9609, 27.1901, 29.3858, 29.1209, 29.5824, 29.8629, 29.1811, 28.9622, 28.6477, 28.8257, 28.8078, 28.7820, 28.6387, 28.3002, 27.8940, 27.8940, 27.8940, 27.8940, 27.8940, 27.8940, 27.8940, 27.8940, 27.8940, 27.8940]
    static let goldenFlip: [Double] = [28.0893, 26.9140, 26.7809, 21.9277, 12.7566, 3.1480, -5.0519, -10.2180, -11.3584, -9.1550, 27.1779, 27.7355, 28.8522, 28.9001, 28.8993, 28.8552, 28.3065, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023, 27.9023]
}
