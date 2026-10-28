//
//  ShoeEncloseTests.swift
//  The bare blue foot under the shoes (user, on device, Bob standing still): the shell must ENCLOSE the foot that is drawn. Walk then stand with the jiggle on,
//  a REAL floorY (the ShoeTests run at -10 and never see the coplanar sole): while shoes are worn the beans stay out (the drawn foot is the bean the shell grows
//  from), the visible foot's low vertices are inside the shell, the sole sticks out under the bean and the rim flares.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShoeEncloseTests: XCTestCase {
    /// Is `p` inside the closed mesh (parity of a ray's crossings)?
    static func inside(_ p: SIMD3<Float>, _ v: [SIMD3<Float>], _ idx: [UInt32]) -> Bool {
        let d = simd_normalize(SIMD3<Float>(0.31, 0.9, 0.29))
        var hits = 0
        var t = 0
        while t + 2 < idx.count {
            let a = v[Int(idx[t])], e1 = v[Int(idx[t + 1])] - a, e2 = v[Int(idx[t + 2])] - a
            t += 3
            let h = simd_cross(d, e2), det = simd_dot(e1, h)
            if abs(det) < 1e-9 { continue }
            let f = 1 / det, s = p - a, u = f * simd_dot(s, h)
            if u < 0 || u > 1 { continue }
            let q = simd_cross(s, e1), w = f * simd_dot(d, q)
            if w < 0 || u + w > 1 { continue }
            if f * simd_dot(e2, q) > 1e-6 { hits += 1 }
        }
        return hits % 2 == 1
    }

    func testTheShellEnclosesTheDrawnFootWalkingThenStanding() {
        let r = MotionRig(game: true)
        r.brain.shoesWorn = true
        r.brain.request(.goTo(r.root + SIMD2(1.2, 1.4)))
        var checked = 0, standChecks = 0, worstOut: Float = 0
        var standing = false
        let total: Float = 9
        let look = WearLook.sneakerMint
        func check() {
            r.render()
            guard r.skinner.beansActive, let beans = GameCare.footBeans(brain: r.brain, sim: r.sim, skinner: r.skinner) else { return }
            for s in 0..<2 {
                let b = RoomMeshBuilder(); b.material = .plain
                ShoeModel.build(look, bean: beans[s], floorY: r.sim.floorY, time: 0, side: s, into: b)
                let v = b.mesh.vertices.map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) }
                let bn = ShoeModel.normals(beans[s])
                // the shoe is built from exactly the bean that is drawn
                for i in stride(from: 0, to: FootBean.vertexCount, by: 7) {
                    let o = 6 * Int(r.bean[s][i])
                    let drawn = SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2])
                    XCTAssertLessThan(simd_distance(drawn, beans[s][i]), 0.002, "the shoe is built on the drawn bean, vertex \(i)")
                }
                // every low vertex of the drawn foot is covered by the shoe (no bare foot poking out under it)
                for i in stride(from: 0, to: FootBean.vertexCount, by: 3) where FootBean.localF[i].y < 0.03 {
                    if !ShoeTests.covered(beans[s][i] - bn[i] * 0.002, bn[i], v, b.mesh.indices) { worstOut = max(worstOut, 1); var ys: [Float] = []
                    var tt = 0
                    let P0 = beans[s][i]
                    while tt + 2 < b.mesh.indices.count {
                        let a = v[Int(b.mesh.indices[tt])], bb = v[Int(b.mesh.indices[tt + 1])], c = v[Int(b.mesh.indices[tt + 2])]; tt += 3
                        let d0 = SIMD2(bb.x - a.x, bb.z - a.z), d1 = SIMD2(c.x - a.x, c.z - a.z), dp = SIMD2(P0.x - a.x, P0.z - a.z)
                        let den = d0.x * d1.y - d1.x * d0.y
                        if abs(den) < 1e-12 { continue }
                        let u = (dp.x * d1.y - d1.x * dp.y) / den, w = (d0.x * dp.y - dp.x * d0.y) / den
                        if u >= 0 && w >= 0 && u + w <= 1 { ys.append(a.y + (bb.y - a.y) * u + (c.y - a.y) * w) }
                    }
                    XCTFail("ys under it \(ys.sorted()) t=\(r.t) foot \(s) bean vertex \(i) at \(beans[s][i]) normal \(bn[i]) is not covered by the shoe (lowest shoe y \(v.map(\.y).min()!), lowest bean y \(beans[s].map(\.y).min()!), floor \(r.sim.floorY))"); return }
                }
            }
            checked += 1
            if standing { standChecks += 1 }
        }
        var k = 0
        r.run(total, each: {
            k += 1
            r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt)
            if r.brain.activity == .idle && r.t > 4 { standing = true }
            if k % 15 == 0 { check() }
        })
        XCTAssertGreaterThan(checked, 20)
        XCTAssertGreaterThan(standChecks, 8, "he stood still for a while")
        XCTAssertTrue(r.skinner.beansActive, "while he stands the beans are still out")
        XCTAssertEqual(r.skinner.beanBlend, 1, accuracy: 0.001, "and fully out: the drawn foot IS the bean")
        MotionLog.write("SHOEENCLOSE checks \(checked), standing \(standChecks)")
    }

    func testSoleStandsUnderTheBeanAndTheRimFlaresAtARealFloor() {
        ShoeArt.forceProcedural = true; defer { ShoeArt.forceProcedural = false }          // the procedural fallback shell
        let lift: Float = 0.004
        let bean = FootBean.localF.map { SIMD3($0.x, $0.y + lift, $0.z) }          // a foot standing 4 mm over the floor plane
        for look in WearLook.shoes {
            let b = RoomMeshBuilder(); b.material = .plain
            ShoeModel.buildShell(look, bean: bean, floorY: 0, into: b)
            let v = b.mesh.vertices.prefix(FootBean.vertexCount).map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) }
            XCTAssertLessThan(v.map(\.y).min()!, bean.map(\.y).min()!, "\(look): a sole under the foot")
            XCTAssertGreaterThanOrEqual(v.map(\.y).min()!, 0.001 - 1e-6, "\(look): never through the floor")
            // the rim of the sole stands clear of the bean's own rim (radially, from the sole centre)
            let ids = ShoeModel.soleVerts
            var c = SIMD2<Float>.zero
            for i in ids { c += SIMD2(bean[i].x, bean[i].z) }; c /= Float(ids.count)
            var worst = Float.infinity
            for i in ids {
                let d = SIMD2(bean[i].x, bean[i].z) - c
                guard simd_length(d) > 0.02 else { continue }
                let n = d / simd_length(d)
                let out = simd_dot(SIMD2(v[i].x, v[i].z) - SIMD2(bean[i].x, bean[i].z), n)
                worst = min(worst, out)
            }
            XCTAssertGreaterThanOrEqual(worst, 0.012, "\(look): the sole rim flares out past the bean (\(worst))")
        }
    }

    /// A modelled shoe at a real floor: its sole is the bottom of the foot (a hair under the bean, never above it, never through the floor by more than the rounding).
    func testModelledSoleSitsAtTheFootsBottomAtARealFloor() {
        let bean = FootBean.localF
        for look in WearLook.shoes {
            let b = RoomMeshBuilder(); b.material = .plain
            ShoeModel.build(look, bean: bean, floorY: 0, time: 0, side: 0, into: b)
            let lo = b.mesh.vertices.map(\.pos.y).min()!
            XCTAssertLessThanOrEqual(lo, bean.map(\.y).min()! + 1e-4, "\(look): a sole under the foot")
            XCTAssertGreaterThanOrEqual(lo, -0.016, "\(look): not buried in the floor")
        }
    }
}
