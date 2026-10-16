//
//  FootBean.swift
//  A closed bean per foot, appended to the render mesh inside the wave-arm capsule blocks (per side: [arm capsule, bean]). At rest it is
//  hidden deep inside the belly, so the rest render is unchanged (BaseBodyLock). While he walks / turns / waves / hops it grows at the foot's
//  pose and the embedded foot (an open cup glued to the belly) retracts, so a lifted or displaced foot is a real round bean with no bridge
//  of skin to the belly. See BlobBrain.driveLimbs.
//
//  The bean is a superellipsoid of the foot's footprint with a flat sole (the sole plane is y = 0 in foot-local coordinates, the footprint
//  centre is x = z = 0). Vertex layout: sole pole, `rings` rings of `around` vertices, top pole.
//

import Foundation
import simd

nonisolated enum FootBean {
    static let around = 32, rings = 13
    static var vertexCount: Int { 2 + around * rings }
    /// Working size (world units): footprint half axes and the height of the sole plane to the crown.
    static let rx = 0.135, rz = 0.125, centreY = 0.100, ry = 0.130, exponent = 2.0
    /// Where the bean sits when it replaces the rest foot (rest coordinates): footprint centre of the +x foot.
    static var footCentre: SIMD3<Double> { SIMD3(BobForm.footX, 0, BobForm.footZ) }

    static func triangles(firstVertex f: Int) -> [UInt32] {
        var t: [UInt32] = []
        func ring(_ r: Int, _ j: Int) -> UInt32 { UInt32(f + 1 + around * r + (j % around)) }
        let bottom = UInt32(f), top = UInt32(f + vertexCount - 1)
        for j in 0..<around { t += [bottom, ring(0, j), ring(0, j + 1)] }
        for r in 0..<(rings - 1) {
            for j in 0..<around {
                t += [ring(r, j), ring(r + 1, j), ring(r, j + 1)]
                t += [ring(r, j + 1), ring(r + 1, j), ring(r + 1, j + 1)]
            }
        }
        for j in 0..<around { t += [top, ring(rings - 1, j + 1), ring(rings - 1, j)] }
        return t
    }

    /// Working-size shape in foot-local coordinates (sole plane y = 0, footprint centre at the origin) and outward unit normals.
    static let local: (pos: [SIMD3<Double>], nrm: [SIMD3<Double>]) = {
        var pos: [SIMD3<Double>] = [], nrm: [SIMD3<Double>] = []
        func emit(_ d: SIMD3<Double>) {
            // radial scale onto |x/a|^n + |y/b|^n + |z/c|^n = 1 (about the bean centre), then the flat sole: nothing below y = 0
            let n = exponent
            let q = pow(abs(d.x / rx), n) + pow(abs(d.y / ry), n) + pow(abs(d.z / rz), n)
            let r = pow(q, -1 / n)
            var p = d * r
            let nn = simd_normalize(SIMD3(p.x / (rx * rx), p.y / (ry * ry), p.z / (rz * rz)))
            p.y = max(p.y + centreY, 0)
            pos.append(p); nrm.append(nn)
        }
        emit(SIMD3(0, -1, 0))
        for r in 0..<rings {
            let phi = Double.pi * Double(r + 1) / Double(rings + 1)           // 0 = sole pole, pi = crown pole
            for j in 0..<around {
                let th = 2 * Double.pi * Double(j) / Double(around)
                emit(SIMD3(sin(phi) * cos(th), -cos(phi), sin(phi) * sin(th)))
            }
        }
        emit(SIMD3(0, 1, 0))
        return (pos, nrm)
    }()

    static let localF: [SIMD3<Float>] = local.pos.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }

    /// Scale about `pivotLocal` at which the bean (in the rest foot pose) lies inside the body surface (sdf <= -0.002 everywhere): the swap starts from
    /// this inset bean, coincident with but inside the embedded foot (no z-fighting), and grows to full size as the foot skin retracts.
    static let pivotLocal = SIMD3<Double>(0, 0.10, 0)
    static let startScale: Float = {
        func ok(_ k: Double) -> Bool {
            for p in local.pos {
                let q = pivotLocal + (p - pivotLocal) * k
                if BobForm.sdf(SIMD3(BobForm.footX + q.x, q.y, BobForm.footZ + q.z)) > -0.002 { return false }
            }
            return true
        }
        var lo = 0.5, hi = 1.0
        if ok(hi) { return 1 }
        for _ in 0..<30 { let m = (lo + hi) / 2; if ok(m) { lo = m } else { hi = m } }
        return Float(lo)
    }()

    /// Hidden shape in rest coordinates: a small ball deep inside the belly above the foot (side -1 / +1 mirrored).
    static func inactive(sigma: Double) -> [SIMD3<Double>] {
        let c = SIMD3(sigma * BobForm.footX, 0.48, BobForm.footZ)
        return local.nrm.map { c + $0 * 0.05 }
    }

    /// Static `mat` (baked crease occlusion 0...0.4): darker toward the crown, where the bean meets the belly (a soft clay crease).
    static let mat: [Float] = local.pos.map { p in
        let t = min(max((p.y - 0.06) / 0.08, 0), 1)
        return Float(0.38 * t * t * (3 - 2 * t))
    }

    /// The crinkle-texture coordinate stream: the working-size bean at the rest foot, so the texture density matches the body skin.
    static func restStream(sigma: Double) -> [SIMD3<Double>] {
        local.pos.map { SIMD3(sigma * BobForm.footX + $0.x, $0.y, BobForm.footZ + $0.z) }
    }
}
