//
//  WalkGoldenTests.swift
//  Trick plan stage 3 (moonwalk v2) adds a heel-up hook to `driveLimbs` (BlobBrain.swift, after `feet.state(s)` and at the boot-shape line), gated on the moonwalk's own
//  `idleState.trick.heelUp`. The locked walk must be BIT-FOR-BIT what it was: one number per sampled tick folds the sim body, the sole targets and both foot beans together,
//  recorded on 27fbd0b3 (before BlobBrain.swift was touched).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WalkGoldenTests: XCTestCase {
    static func digest(seconds: Float) -> [Double] {
        let r = MotionRig(game: true)
        r.brain.request(.goTo(SIMD2(1.6, 0.4)))
        var out: [Double] = [], n = 0
        r.run(seconds, each: {
            n += 1
            guard n % 6 == 0 else { return }
            var v: Double = 0
            for (i, x) in r.sim.x.enumerated() where i % 7 == 0 { v += Double(x) * Double(1 + i % 5) }
            for t in r.sim.targets { v += 0.5 * Double(t.pos.x + 2 * t.pos.y + 3 * t.pos.z) }
            for s in 0..<2 { for (i, p) in r.skinner.beanPos[s].enumerated() where i % 9 == 0 { v += 0.25 * Double(p.x + 3 * p.y + 5 * p.z) * Double(s + 1) } }
            v += 0.01 * Double(r.skinner.beanBlend)
            out.append((v * 1e3).rounded() / 1e3)
        })
        return out
    }

    func testTheLockedWalkIsUnchangedByTheMoonwalkHook() {
        let walk = Self.digest(seconds: 4)
        if Self.goldenWalk.isEmpty {
            MotionLog.write("GOLDEN walk " + "[" + walk.map { String(format: "%.3f", $0) }.joined(separator: ", ") + "]")
            XCTFail("golden walk not frozen yet")
            return
        }
        XCTAssertEqual(walk.count, Self.goldenWalk.count)
        for (i, (a, b)) in zip(walk, Self.goldenWalk).enumerated() { XCTAssertEqual(a, b, accuracy: 2e-3, "walk tick \(i * 6)") }
    }

    static let goldenWalk: [Double] = [254.779, 203.302, 262.003, 288.114, 311.707, 387.993, 496.203, 630.269, 714.237, 769.161, 805.044, 869.012, 944.990, 945.298, 932.038, 930.662, 920.257, 942.973, 964.261, 975.498, 970.387, 970.025, 970.371, 970.333, 970.326, 970.326, 970.326, 970.326, 970.326, 970.325, 970.325, 970.325, 970.325, 970.325, 970.325, 970.325, 970.325, 970.325, 970.326, 970.326]
}
