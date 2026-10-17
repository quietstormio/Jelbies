//
//  TouchEyeSquashTests.swift
//  The happy squint squashes both eyes toward their own centre. Both must squash the same (mirror images at rest), and under a
//  sideways body shift / lean neither eye may slide off its rest position relative to the other. Also: the dent smoothing must leave the face
//  features and (at rest, no dent) the whole skin exactly as it was.
//

import XCTest
import simd
@testable import BobV1

final class TouchEyeSquashTests: XCTestCase {
    struct Rigged { let rm: RenderMesh; let sm: SimMesh; let body: SoftBody; let skinner: Skinner; let rig: EyeRig }
    private func make() -> Rigged {
        let ap = BlobAppearance.berry
        let sm = buildSimMesh(appearance: ap), rm = buildRenderMesh(appearance: ap)
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let rig = buildEyeRig(render: rm, sim: sm, appearance: ap)
        let body = SoftBody(mesh: sm, firmness: 0.95, damping: 0.45)
        body.reset(drop: 0)
        let skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount, eyes: rig, antennae: buildAntennaRig(render: rm, sim: sm))
        skinner.autoBlink = false
        return Rigged(rm: rm, sm: sm, body: body, skinner: skinner, rig: rig)
    }
    private func skin(_ r: Rigged, shift: SIMD3<Float> = .zero, tilt: Float = 0) -> [Float] {
        var x = r.body.x
        let c = SIMD3<Float>(0, 0.6, 0), q = simd_quatf(angle: tilt, axis: SIMD3(0, 0, 1))
        for i in 0..<(x.count / 3) {
            let p = q.act(SIMD3(x[3 * i], x[3 * i + 1], x[3 * i + 2]) - c) + c + shift
            x[3 * i] = p.x; x[3 * i + 1] = p.y; x[3 * i + 2] = p.z
        }
        var dyn = [Float](repeating: 0, count: r.rm.vertexCount * 6)
        dyn.withUnsafeMutableBufferPointer { r.skinner.update(x: x, index: r.rm.index, into: $0.baseAddress!) }
        return dyn
    }
    /// Mean height and half-height of the eye's skinned vertices in the screen plane (y), plus the centroid.
    private func stats(_ d: [Float], _ ids: [Int32]) -> (c: SIMD3<Float>, h: Float) {
        var c = SIMD3<Float>(0, 0, 0), lo = Float.infinity, hi = -Float.infinity
        for v in ids { let p = SIMD3(d[6 * Int(v)], d[6 * Int(v) + 1], d[6 * Int(v) + 2]); c += p; lo = min(lo, p.y); hi = max(hi, p.y) }
        return (c / Float(ids.count), hi - lo)
    }

    func testBothEyesSquashAsMirrorImagesAtRest() {
        let r = make()
        for k: Float in [1, 0.8, 0.5, 0.25, 0.1, 0] {
            r.skinner.setEyeOpenness(k)
            let d = skin(r)
            let l = r.rig.eye[0], rr = r.rig.eye[1]
            XCTAssertEqual(l.count, rr.count)
            var worstP: Float = 0, worstN: Float = 0
            var worstV: (Int, Int, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = (0, 0, .zero, .zero, .zero)
            for v in l {
                let p = SIMD3(d[6 * Int(v)], d[6 * Int(v) + 1], d[6 * Int(v) + 2]), n = SIMD3(d[6 * Int(v) + 3], d[6 * Int(v) + 4], d[6 * Int(v) + 5])
                // the mirrored vertex of the right eye (nearest to the mirrored REST position)
                let rp = SIMD3(r.rm.rest[3 * Int(v)] * -1, r.rm.rest[3 * Int(v) + 1], r.rm.rest[3 * Int(v) + 2])
                var best = rr[0], bd = Float.infinity, near = 0
                for w in rr {
                    let q = SIMD3(r.rm.rest[3 * Int(w)], r.rm.rest[3 * Int(w) + 1], r.rm.rest[3 * Int(w) + 2])
                    let dd = simd_length(q - rp); if dd < bd { bd = dd; best = w }
                    if dd < 1e-5 { near += 1 }
                }
                if near != 1 { continue }          // split vertices (hard edges) have no unique mirror partner
                let pm = SIMD3(d[6 * Int(best)] * -1, d[6 * Int(best) + 1], d[6 * Int(best) + 2])
                let nm = SIMD3(d[6 * Int(best) + 3] * -1, d[6 * Int(best) + 4], d[6 * Int(best) + 5])
                worstP = max(worstP, simd_length(p - pm))
                let ne = simd_length(n - nm)
                if ne > worstN { worstN = ne; worstV = (Int(v), Int(best), SIMD3(r.rm.rest[3 * Int(v)], r.rm.rest[3 * Int(v) + 1], r.rm.rest[3 * Int(v) + 2]), n, nm) }
            }
            print("EYESYM k=\(k) worst mirror position error \(worstP) normal error \(worstN)")
            XCTAssertLessThan(worstP, 0.004, "k=\(k): the eyes are not mirror images in position")
        }
    }

    func testSquashStaysCentredOnEachEyeWhenTheBodyIsShiftedOrLeaned() {
        let r = make()
        r.skinner.setEyeOpenness(1)
        let open0 = skin(r)
        let rest = [stats(open0, r.rig.eye[0]), stats(open0, r.rig.eye[1])]
        for (shift, tilt) in [(SIMD3<Float>(0.05, 0, 0), Float(0)), (SIMD3<Float>(0, 0, 0), Float(0.12)), (SIMD3<Float>(0.1, 0.02, 0.03), Float(-0.15))] {
            r.skinner.setEyeOpenness(1)
            let open = skin(r, shift: shift, tilt: tilt)
            let o = [stats(open, r.rig.eye[0]), stats(open, r.rig.eye[1])]
            r.skinner.setEyeOpenness(0.5)
            let half = skin(r, shift: shift, tilt: tilt)
            let h = [stats(half, r.rig.eye[0]), stats(half, r.rig.eye[1])]
            var slide: [Float] = []
            for e in 0..<2 { slide.append(simd_length(h[e].c - o[e].c)) }
            print("EYESLIDE shift \(shift) tilt \(tilt): L \(slide[0]) R \(slide[1]) (rest eye height \(rest[0].h))")
            // a squash toward the eye's own centre never moves its centre
            for e in 0..<2 { XCTAssertLessThan(slide[e], 0.004, "eye \(e) slid \(slide[e]) while squashing") }
            XCTAssertEqual(h[0].h, h[1].h, accuracy: 0.01, "the two eyes squash to different heights")
        }
    }

    func testDentSmoothingNeverMovesFaceFeatures() {
        let r = make()
        r.skinner.setEyeOpenness(0.3)
        let a = skin(r)
        r.skinner.normalSmoothing = 1
        r.skinner.smoothCenter = SIMD3(0, 0.7, 0.45)
        let b = skin(r)
        r.skinner.normalSmoothing = 0
        var moved: Float = 0
        for v in r.skinner.faceFeatureVertices {
            let o = 6 * Int(v)
            moved = max(moved, simd_length(SIMD3(a[o], a[o + 1], a[o + 2]) - SIMD3(b[o], b[o + 1], b[o + 2])))
            moved = max(moved, simd_length(SIMD3(a[o + 3], a[o + 4], a[o + 5]) - SIMD3(b[o + 3], b[o + 4], b[o + 5])))
        }
        XCTAssertEqual(moved, 0, "dent smoothing touched an eye / brow / glint vertex")
        // and with smoothing off the skin is exactly the plain skin
        let c = skin(r)
        XCTAssertEqual(a, c)
    }

    func testDentSmoothingCost() {
        let r = make()
        var dyn = [Float](repeating: 0, count: r.rm.vertexCount * 6)
        func time(_ n: Int) -> Double {
            let t0 = CFAbsoluteTimeGetCurrent()
            dyn.withUnsafeMutableBufferPointer { b in for _ in 0..<n { r.skinner.update(x: r.body.x, index: r.rm.index, into: b.baseAddress!) } }
            return (CFAbsoluteTimeGetCurrent() - t0) / Double(n) * 1000
        }
        r.skinner.normalSmoothing = 0
        _ = time(20)
        let plain = time(300)
        r.skinner.normalSmoothing = 1; r.skinner.smoothCenter = SIMD3(0, 0.6, 0.5)
        _ = time(20)
        let dent = time(300)
        r.skinner.normalSmoothing = 0; r.skinner.setEyeOpenness(0.3)
        let eyes = time(300)
        print("DENTCOST plain \(plain) ms, with dent \(dent) ms, extra \(dent - plain) ms; squashed eyes extra \(eyes - plain) ms")
        XCTAssertLessThan(dent - plain, 0.35, "the dent smoothing must cost < 0.35 ms per frame")
    }
}
