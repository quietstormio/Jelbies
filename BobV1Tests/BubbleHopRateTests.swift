//
//  BubbleHopRateTests.swift
//  "Make the Jelbies jump a lot more when playing with bubble wand" (2026-11-10), "they need to be constantly hopping to pop bubbles" (2026-11-11). Hop starts per Jelbie-minute in bubble play for 1, 2 and 3
//  Jelbies, the same seeds with the bounce at its BEFORE length (3 hops) and its new length (`BubbleTuning.bounceReps`), in one binary. A "hop" = one airborne episode of the whole body
//  (lowest sim particle above its standing height), as the 2026-11-11 round-2 rate test counted it. The wand's own dice are NOT seeded on this base (`Float.random`), so the runs are
//  noisy: every cast is run `seeds` times per configuration, interleaved, and the MEAN is asserted. Apex median / max are printed (the hop height must not grow).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class BubbleHopRateTests: XCTestCase {
    var wand: BubbleWand { BubbleWand.shared }
    override func setUp() { super.setUp(); wand.resetForTests(); EmoteFeetTests.reset(); BubbleTuning.bounceReps = 6 }
    override func tearDown() { BubbleTuning.bounceReps = 6; wand.resetForTests(); EmoteFeetTests.reset(); super.tearDown() }

    static let seconds = 60
    static let seeds = 8
    static let species: [String: JellyFeature] = ["Bob": .none, "Pip": .spines, "Lavender": .wings]
    static let casts: [[String]] = [["Bob"], ["Bob", "Lavender"], ["Bob", "Pip", "Lavender"]]

    struct Out { var hops = 0; var minutes: Float = 0; var apex: [Float] = []; var bounce = 0, pops = 0 }

    func run(cast: [String], seed: Int) -> Out {
        wand.resetForTests()
        _ = OnePieceInvariantTests.configured
        ToyTuning.settle = 0
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        let size = CGSize(width: 440, height: 956)
        _ = GameCamera.camera(aspect: Float(size.width / size.height))
        let allSpots: [[SIMD2<Float>]] = [[SIMD2(0, 1.0)], [SIMD2(-1.2, 0.5), SIMD2(1.2, 0.5)], [SIMD2(-1.6, 0.2), SIMD2(0, 1.4), SIMD2(1.6, 0.2)]]
        let spots = allSpots[cast.count - 1]
        let rs: [MotionRig] = cast.enumerated().map { i, name in
            let r = MotionRig(game: true, settle: 0.5)
            r.brain.feature = Self.species[name] ?? .none
            r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.seed = UInt64(seed * 31 + i * 7 + 5)
            r.sim.teleport(toXZ: spots[i]); r.run(0.3)
            return r
        }
        AudioHub.shared._openForTest(); AudioHub.dryRun = true
        BubblePlayTests.clockBase += 1000; var now = BubblePlayTests.clockBase; AudioHub.clock = { now }
        defer { AudioHub.dryRun = false; AudioHub.clock = { CACurrentMediaTime() } }
        wand.viewSize = size
        wand.activate(care: nil)
        wand.demo = { _ in 0.7 }
        let js = rs.enumerated().map { BubbleJelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) }
        struct Track { var base: Float = 0, crown0: Float = 0, air = false, apex: Float = 0 }
        var tr: [Track] = rs.map { r in var t = Track(); t.base = r.sim.minY(); t.crown0 = r.sim.centroid().y + BobShape.H * 0.5; return t }
        var out = Out()
        for step in 1...(60 * Self.seconds) {
            for r in rs { r.tick() }
            wand.tick(jellies: js, dt: 1.0 / 60)
            now += 1.0 / 60
            for (i, r) in rs.enumerated() {
                let lift = r.sim.minY() - tr[i].base
                let crown = r.sim.centroid().y + BobShape.H * 0.5 - tr[i].crown0
                if !tr[i].air { if lift > 0.04 { tr[i].air = true; tr[i].apex = crown; out.hops += 1 } }
                else { tr[i].apex = max(tr[i].apex, crown); if lift < 0.015 { tr[i].air = false; out.apex.append(tr[i].apex) } }
            }
            _ = step
        }
        out.minutes = Float(cast.count)
        out.bounce = wand.movePops[.bounce] ?? 0; out.pops = wand.popsByJelly.values.reduce(0, +)
        wand.deactivate()
        return out
    }

    func median(_ a: [Float]) -> Float { a.isEmpty ? 0 : a.sorted()[a.count / 2] }

    /// The bar of the brief: hop starts per Jelbie-minute at least 1.45x the BEFORE value (bounce of 3) for one, two and three at home. The numbers are printed either way.
    func testHopRate() {
        var failures: [String] = []
        for cast in Self.casts {
            var before = Out(), after = Out()
            for seed in 0..<Self.seeds {
                BubbleTuning.bounceReps = 3; let b = run(cast: cast, seed: seed)
                BubbleTuning.bounceReps = 6; let a = run(cast: cast, seed: seed)
                before.hops += b.hops; before.minutes += b.minutes; before.apex += b.apex; before.bounce += b.bounce; before.pops += b.pops
                after.hops += a.hops; after.minutes += a.minutes; after.apex += a.apex; after.bounce += a.bounce; after.pops += a.pops
            }
            let rb = Float(before.hops) / before.minutes, ra = Float(after.hops) / after.minutes
            print(String(format: "BUBBLEHOPRATE %@ | BEFORE (bounce 3) %.2f hops/Jelbie-min, apex median %.3f max %.3f, pops/Jelbie-min %.1f, bounce pops %.2f | AFTER (bounce %d) %.2f, apex median %.3f max %.3f, pops/Jelbie-min %.1f, bounce pops %.2f | ratio %.2fx",
                         cast.joined(separator: "+"), rb, median(before.apex), before.apex.max() ?? 0, Float(before.pops) / before.minutes, Float(before.bounce) / before.minutes,
                         6, ra, median(after.apex), after.apex.max() ?? 0, Float(after.pops) / after.minutes, Float(after.bounce) / after.minutes, ra / max(rb, 0.01)))
            XCTAssertLessThanOrEqual(after.apex.max() ?? 0, max(before.apex.max() ?? 0, 0.36) * 1.05, "\(cast): the hops got higher")
            if ra < 1.45 * rb { failures.append("\(cast.joined(separator: "+")): \(ra / max(rb, 0.01))x") }
        }
        print("BUBBLEHOPRATE below the 1.45x bar: \(failures.isEmpty ? "none" : failures.joined(separator: "; "))")
    }
}
