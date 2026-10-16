//
//  MotionChannelLogTests.swift
//  Capture aid (not a gate): runs a capture demo headless in the same engine and prints one CSV row per 60 Hz tick (time, root, rendered foot gaps / xz,
//  crown) for aligning the captures' video frames to engine time. Rows are "CSV,<scenario>,..." lines in the MOTION_LOG file.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MotionChannelLogTests: XCTestCase {
    static let header = ["t", "px", "pz", "footL_fx", "footL_fz", "footL_gap", "footR_fx", "footR_fz", "footR_gap", "crownY", "crownX", "crownZ"].joined(separator: ",")

    private func log(_ name: String, demo: String, game: Bool, seconds: Float) {
        let r = MotionRig(game: game, settle: 0.1)
        r.brain.demo = demo; r.brain.autonomy = false
        r.renderSamples = true
        let t0 = r.t
        MotionLog.write("CSVHEADER,\(name),\(Self.header)")
        r.run(seconds) {
            r.render()
            let c = r.sim.centroid()
            var f: [String] = []
            func a(_ v: Float) { f.append(String(format: "%.5f", v)) }
            a(r.t - t0); a(c.x); a(c.z)
            for s in 0..<2 { let xz = r.renderedFootXZ(s); a(xz.x); a(xz.y); a(r.renderedFootGap(s)) }
            var cyv: Float = -1, cxv: Float = 0, czv: Float = 0
            for v in 0..<MotionRig.renderMesh.vertexCount { let y = r.dyn[6 * v + 1]; if y > cyv { cyv = y; cxv = r.dyn[6 * v]; czv = r.dyn[6 * v + 2] } }
            a(cyv - r.sim.floorY); a(cxv); a(czv)
            MotionLog.write("CSV,\(name)," + f.joined(separator: ","))
        }
    }

    func testChannelLogs() {
        log("front", demo: "wfrontL", game: false, seconds: 18)
        log("s34", demo: "w34", game: false, seconds: 16)
        log("side", demo: "wside", game: false, seconds: 8)
        log("game_gwalk", demo: "gwalk", game: true, seconds: 14)
    }
}
