//
//  MelonPerfTests.swift
//  CPU timing of the default Bob sim step and the per-frame skinning, as the app builds them.
//  Prints "PERF ..." lines; run with -configuration Debug and Release to compare.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class MelonPerfTests: XCTestCase {

    func testSimStepAndFrameCPUCost() {
        let ap = BlobAppearance.berry
        let sm = buildSimMesh(appearance: ap)
        let rm = buildRenderMesh(appearance: ap)
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let body = SoftBody(mesh: sm, firmness: 0.95, damping: 0.45)
        let skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount,
                              eyes: buildEyeRig(render: rm, sim: sm, appearance: ap),
                              antennae: buildAntennaRig(render: rm, sim: sm))
        body.reset(drop: 0.35)
        let dyn = UnsafeMutablePointer<Float>.allocate(capacity: rm.vertexCount * 6)
        defer { dyn.deallocate() }
        for _ in 0..<30 { body.step() }   // warm up

        let n = 300
        var t0 = CACurrentMediaTime()
        for _ in 0..<n { body.step() }
        let stepMs = (CACurrentMediaTime() - t0) / Double(n) * 1000

        t0 = CACurrentMediaTime()
        for _ in 0..<n {
            skinner.tickBlink(dt: 1.0 / 60)
            skinner.update(x: body.x, index: rm.index, into: dyn)
        }
        let skinMs = (CACurrentMediaTime() - t0) / Double(n) * 1000

        t0 = CACurrentMediaTime()
        for _ in 0..<n {
            body.step()
            skinner.tickBlink(dt: 1.0 / 60)
            skinner.update(x: body.x, index: rm.index, into: dyn)
            _ = body.centroid()
        }
        let frameMs = (CACurrentMediaTime() - t0) / Double(n) * 1000
        let line = String(format: "PERF particles %d tets %d | step %.3f ms | skin %.3f ms | step+skin per frame %.3f ms",
                          body.n, body.nT, stepMs, skinMs, frameMs)
        print(line)
        NSLog("%@", line)
        XCTAssertLessThan(frameMs, 200)   // sanity only
    }
}
