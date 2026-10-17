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
    /// 2026-10-16: the bean IS the rest foot (BobForm.footSDF alone, the arched shoe with the curled toe): each vertex is where a ray from the
    /// foot's inside meets the foot surface, so the swap between the embedded foot and the bean changes neither size nor shape.
    static let local: (pos: [SIMD3<Double>], nrm: [SIMD3<Double>]) = {
        var pos: [SIMD3<Double>] = [], nrm: [SIMD3<Double>] = []
        let c0 = SIMD3<Double>(0, 0.07, 0)
        func f(_ l: SIMD3<Double>) -> Double { BobForm.footSDF(SIMD3(BobForm.footX + l.x, l.y, BobForm.footZ + l.z)) }
        func emit(_ d: SIMD3<Double>) {
            var lo = 0.0, hi = 0.6
            for _ in 0..<44 { let m = (lo + hi) / 2; if f(c0 + d * m) < 0 { lo = m } else { hi = m } }
            let p = c0 + d * lo
            let e = 0.0008
            let g = SIMD3(f(p + SIMD3(e, 0, 0)) - f(p - SIMD3(e, 0, 0)), f(p + SIMD3(0, e, 0)) - f(p - SIMD3(0, e, 0)), f(p + SIMD3(0, 0, e)) - f(p - SIMD3(0, 0, e)))
            let q = p
            pos.append(SIMD3(q.x, max(q.y, 0), q.z)); nrm.append(simd_length(g) > 1e-12 ? simd_normalize(g) : simd_normalize(d))
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

    /// Bean vertices that make the crown (the top three rings and the top pole): the part that must always lie inside the egg.
    static let crownIndices: [Int] = Array((vertexCount - 1 - 3 * around)..<vertexCount)

    /// The lifted shape: a soft rounded ball / bean on the same vertex layout (sphere directions), its bottom at the sole plane. A foot that is off the
    /// floor morphs from the boot (`localF`) to this and back (see `BlobBrain.beanMorph`): it rounds as it leaves the floor and flattens into the boot as
    /// it lands, with no pop (vertex-wise blend of two shapes of the same mesh).
    static let ballRadii = SIMD3<Float>(0.118, 0.110, 0.128), ballZ: Float = 0.02
    static let ballF: [SIMD3<Float>] = dirs.map { d in
        SIMD3(Float(d.x) * ballRadii.x, ballRadii.y + Float(d.y) * ballRadii.y, ballZ + Float(d.z) * ballRadii.z)
    }
    /// Vertex `i` morphed by `m` (0 = planted boot, 1 = lifted ball).
    @inline(__always) static func morphed(_ i: Int, _ m: Float) -> SIMD3<Float> { localF[i] + (ballF[i] - localF[i]) * m }

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

    /// The sphere directions the bean's vertices are laid out on (same order as `local`).
    static let dirs: [SIMD3<Double>] = {
        var out: [SIMD3<Double>] = [SIMD3(0, -1, 0)]
        for r in 0..<rings {
            let phi = Double.pi * Double(r + 1) / Double(rings + 1)
            for j in 0..<around {
                let th = 2 * Double.pi * Double(j) / Double(around)
                out.append(SIMD3(sin(phi) * cos(th), -cos(phi), sin(phi) * sin(th)))
            }
        }
        out.append(SIMD3(0, 1, 0))
        return out
    }()

    /// Hidden shape in rest coordinates: a small ball deep inside the belly above the foot (side -1 / +1 mirrored). It is laid out on the sphere
    /// directions (never on the bean's own normals: on a flat sole / straight wall many normals coincide, which collapses the hidden ball and
    /// makes the mesh-build winding fix flip random triangles).
    static func inactive(sigma: Double) -> [SIMD3<Double>] {
        let c = SIMD3(sigma * BobForm.footX, 0.48, BobForm.footZ)
        return dirs.map { c + $0 * 0.05 }
    }

    /// Static `mat` (baked crease occlusion 0...0.4): the same occlusion the rest skin bakes, read at the bean's rest pose against the whole body
    /// (vertices inside the belly are projected onto its surface first, so the crown, which only shows once the foot is lifted, is crease-dark).
    static let mat: [Float] = local.pos.map { p in
        let w = SIMD3(BobForm.footX + p.x, p.y, BobForm.footZ + p.z)
        let s = BobForm.project(w, steps: 3)
        let n = BobForm.normal(s)
        return Float(0.4 * BobForm.occlusion(s, n))
    }

    /// The crinkle-texture coordinate stream: the working-size bean at the rest foot, so the texture density matches the body skin.
    static func restStream(sigma: Double) -> [SIMD3<Double>] {
        local.pos.map { SIMD3(sigma * BobForm.footX + $0.x, $0.y, BobForm.footZ + $0.z) }
    }
}
