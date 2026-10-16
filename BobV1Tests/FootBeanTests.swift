import XCTest
import simd
@testable import BobV1

final class FootBeanTests: XCTestCase {
    /// The hidden foot beans must sit strictly inside the rest body (rest mesh and skinned at rest), so the base look is unchanged.
    func testFootBeansInsideBodyAtRest() throws {
        let ap = BlobAppearance.berry
        let sm = buildSimMesh(appearance: ap), rm = buildRenderMesh(appearance: ap)
        guard let caps = rm.armCapsule else { return }
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let rig = buildEyeRig(render: rm, sim: sm, appearance: ap)
        let body = SoftBody(mesh: sm, firmness: 0.95, damping: 0.45)
        body.reset(drop: 0)
        let skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount, eyes: rig, antennae: buildAntennaRig(render: rm, sim: sm))
        var dyn = [Float](repeating: 0, count: rm.vertexCount * 6)
        dyn.withUnsafeMutableBufferPointer { skinner.update(x: body.x, index: rm.index, into: $0.baseAddress!) }
        for side in [-1, 1] {
            var worstRest = -Double.infinity, worstSkinned = -Double.infinity
            let f = caps.beanFirst(side: side)
            for v in f..<(f + FootBean.vertexCount) {
                let p = SIMD3<Double>(Double(rm.rest[3 * v]), Double(rm.rest[3 * v + 1]), Double(rm.rest[3 * v + 2]))
                let q = SIMD3<Double>(Double(dyn[6 * v]), Double(dyn[6 * v + 1]), Double(dyn[6 * v + 2]))
                worstRest = max(worstRest, BobForm.sdf(p)); worstSkinned = max(worstSkinned, BobForm.sdf(q))
            }
            XCTAssertLessThan(worstRest, -0.01, "foot bean (side \(side)) pokes out of the body at rest (rest mesh)")
            XCTAssertLessThan(worstSkinned, -0.01, "foot bean (side \(side)) pokes out of the body at rest (skinned)")
        }
        // beans are inside the capsule index range and use only capsule-block vertices
        var t = caps.indexFirst
        while t < caps.indexFirst + caps.indexCount {
            let a = Int(rm.index[t])
            let side = (a >= caps.firstVertex[1]) ? 1 : 0
            let lo = caps.firstVertex[side], hi = lo + ArmCapsule.vertexCount + FootBean.vertexCount
            for k in 0..<3 { let v = Int(rm.index[t + k]); XCTAssertTrue(v >= lo && v < hi, "capsule-range triangle crosses blocks") }
            t += 3
        }
    }

    /// The swap starts from the bean inset to FootBean.startScale at the rest foot pose; that must be nearly full size so the swap is seamless.
    func testSwapStartBeanIsNearFullSize() {
        MotionLog.write(String(format: "FOOTBEAN start scale %.3f (bean inside the body surface at rest by >= 2 mm)", FootBean.startScale))
        XCTAssertGreaterThan(FootBean.startScale, 0.90)
    }

    /// ALWAYS ATTACHED: in every frame of every scenario the bean point nearest the body centre lies inside the posed body (egg sdf < -0.01),
    /// so the lifted foot always overlaps the belly (no coin floating apart from him from any camera). The body frame is the fitted pose of the
    /// sim body (rotation + centroid), independent of the brain's own pose.
    @MainActor
    func testBeanAlwaysAttachedToTheBody() {
        let cases: [(String, Bool, (MotionRig) -> Void, Float)] = [
            ("walk", false, { $0.brain.request(.goTo($0.root + SIMD2(0, 2.4))) }, 7),
            ("walk game", true, { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) }, 7),
            ("march", false, { $0.brain.startStepping(seconds: 3, sim: $0.sim) }, 5),
            ("turn", false, { $0.brain.startTurn(to: $0.poseYaw + 2.4, sim: $0.sim) }, 3.5),
            ("wave", true, { $0.brain.request(.wave) }, 4),
            ("hop", false, { $0.brain.startHopPlay(sim: $0.sim) }, 3),
            ("Call", true, { $0.brain.requestNow(.come(to: SIMD2(0, 1.4))) }, 12)]
        for (name, game, start, secs) in cases {
            let r = MotionRig(game: game)
            r.renderSamples = false
            start(r)
            var worst = -Float.infinity, frames = 0
            r.run(secs) {
                guard r.skinner.beansActive, r.skinner.beanBlend > 0.05 else { return }
                r.render()
                let pose = r.sim.bodyPose(iterations: 4)
                let c0 = r.sim.restCentroid
                for s in 0..<2 {
                    var best = SIMD3<Float>.zero, bd = Float.infinity
                    for id in r.bean[s] {
                        let o = 6 * Int(id), p = SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2])
                        let d = simd_length_squared(p - pose.centroid)
                        if d < bd { bd = d; best = p }
                    }
                    let q = c0 + pose.rotation.inverse.act(best - pose.centroid)
                    worst = max(worst, Float(BobForm.bodySDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))))
                }
                frames += 1
            }
            MotionLog.write(String(format: "FOOTBEAN attached %@: worst sdf of the bean point nearest the body centre %.4f u over %d frames", name, worst, frames))
            XCTAssertGreaterThan(frames, 20, "\(name): beans were out")
            XCTAssertLessThan(worst, -0.01, "\(name): the lifted bean leaves the body")
        }
    }
}
