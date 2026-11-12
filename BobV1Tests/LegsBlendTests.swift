//
//  LegsBlendTests.swift
//  The leg / belly shading blend (Skinner.computeLegBlend + legBlendAt in the body shaders) moves nothing: two rigs in lockstep, one with the blend on and
//  one off, give the same skin to the last bit; and the shader data is finite and present while a piece is out. Prints the CPU cost per call.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class LegsBlendTests: XCTestCase {
    private func make(char: Int, start: (MotionRig) -> Void) -> MotionRig {
        let rm = MotionRig.renderMesh
        let r = MotionRig(game: true, settle: 0.5)
        r.skinner.autoBlink = false
        r.brain.seed = 11
        r.brain.feature = JellyRoster.feature(char)
        r.skinner.configureTail(rm); r.skinner.tailOn = r.brain.feature == .spines; r.brain.skinnerRef = r.skinner
        start(r)
        return r
    }

    /// Lockstep: the skin with the blend on equals the skin with it off (every vertex, 0.00), over a walk, a turn and a hop.
    func testBlendMovesNoVertex() throws {
        let was = Skinner.legsBlend
        defer { Skinner.legsBlend = was }
        var worst: Float = 0, outFrames = 0, finite = true
        var cost: Double = 0, calls = 0
        func run(_ name: String, char: Int, seconds: Float, start: (MotionRig) -> Void) {
            let ra = make(char: char, start: start), rb = make(char: char, start: start)
            var w: Float = 0
            for _ in 0..<Int(60 * seconds) {
                for r in [ra, rb] { r.tick(); r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
                Skinner.legsBlend = true
                let t0 = CFAbsoluteTimeGetCurrent(); ra.render(); let t1 = CFAbsoluteTimeGetCurrent()
                Skinner.legsBlend = false
                let t2 = CFAbsoluteTimeGetCurrent(); rb.render(); let t3 = CFAbsoluteTimeGetCurrent()
                if ra.skinner.legBlend[0].x > 0.5 {
                    outFrames += 1; cost += (t1 - t0) - (t3 - t2); calls += 1
                    for v in ra.skinner.legBlend where !(v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite) { finite = false }
                }
                for i in 0..<ra.dyn.count { w = max(w, abs(ra.dyn[i] - rb.dyn[i])) }
            }
            print(String(format: "[legsblend] lockstep %@ char %d: largest skin difference %.6f cm", name, char, w * 100))
            worst = max(worst, w)
        }
        run("walk", char: 0, seconds: 4) { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) }
        run("walk", char: 1, seconds: 4) { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) }
        run("turn", char: 6, seconds: 3) { $0.brain.startTurn(to: $0.poseYaw + 2.4, sim: $0.sim) }
        run("hop", char: 4, seconds: 3) { $0.brain.startHopPlay(sim: $0.sim) }
        print(String(format: "[legsblend] lockstep displacement %.2f cm over all runs; blend data on in %d frames; extra skin time with the blend %.4f ms per body-frame (%d frames)", worst * 100, outFrames, calls > 0 ? cost / Double(calls) * 1000 : 0, calls))
        XCTAssertEqual(worst, 0, "the blend moved a vertex")
        XCTAssertGreaterThan(outFrames, 30, "the blend never ran (no piece out?)")
        XCTAssertTrue(finite, "non-finite blend data")
    }
}
