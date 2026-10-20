//
//  WearBody.swift
//  The rest body's egg surface as a bind target for wearables. Every Jelly shares one render mesh, so the surface is built ONCE from `RenderMesh.rest`:
//  the egg triangles only (the arm capsules and foot beans sit hidden inside it at rest and would steal the bindings), with a uniform grid for
//  the nearest-triangle query.
//
//  A "bind" pins a rest-space point to the surface: the triangle, the barycentric foot point, and the point's offset in the triangle's smooth frame
//  (T = first edge projected into the tangent plane of the interpolated vertex normal, N = that normal, B = N x T). At runtime the same frame is built
//  from the SKINNED triangle (positions + the smoothed skin normals the CPU already wrote to the shared vertex buffer), so a bound point follows the
//  local jiggle of the skin it sits on, and at rest it lands exactly on its authored position.
//

import simd
import Foundation

nonisolated struct SurfaceBind: Sendable {
    var tri: SIMD3<UInt32> = .zero
    var bary: SIMD3<Float> = .zero
    /// Offset in the (T, B, N) frame.
    var off: SIMD3<Float> = .zero
}

nonisolated final class WearBody: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _shared: WearBody?
    /// Every Jelly shares one rest render mesh, so one body serves all of them. The stage installs its mesh; anything else (tests) builds the base mesh.
    static func install(_ rm: RenderMesh) { lock.lock(); if _shared == nil { _shared = WearBody(rm) }; lock.unlock() }
    static var shared: WearBody {
        lock.lock(); defer { lock.unlock() }
        if let s = _shared { return s }
        let b = WearBody(buildRenderMesh())
        _shared = b
        return b
    }

    let pos: [SIMD3<Float>]
    let nrm: [SIMD3<Float>]
    let tris: [SIMD3<UInt32>]
    let eggVertexLimit: Int
    private let cell: Float = 0.08
    private let lo: SIMD3<Float>
    private let dim: SIMD3<Int>
    private var grid: [[Int32]]

    init(_ rm: RenderMesh) {
        var p: [SIMD3<Float>] = [], n: [SIMD3<Float>] = []
        p.reserveCapacity(rm.vertexCount)
        for i in 0..<rm.vertexCount {
            p.append(SIMD3(rm.rest[3 * i], rm.rest[3 * i + 1], rm.rest[3 * i + 2]))
            n.append(SIMD3(rm.restNormal[3 * i], rm.restNormal[3 * i + 1], rm.restNormal[3 * i + 2]))
        }
        pos = p; nrm = n
        let end = min(rm.armCapsule?.indexFirst ?? rm.body.count, rm.body.first + rm.body.count)
        var t: [SIMD3<UInt32>] = []
        var i = rm.body.first
        while i + 2 < end { t.append(SIMD3(rm.index[i], rm.index[i + 1], rm.index[i + 2])); i += 3 }
        tris = t
        eggVertexLimit = rm.armCapsule?.firstVertex.min() ?? rm.vertexCount
        var mn = SIMD3<Float>(repeating: .infinity), mx = SIMD3<Float>(repeating: -.infinity)
        for tr in t { for k in 0..<3 { let q = p[Int(tr[k])]; mn = simd_min(mn, q); mx = simd_max(mx, q) } }
        lo = mn - 0.05
        let d = simd_max(SIMD3<Float>(repeating: 1), ((mx + 0.05 - lo) / cell).rounded(.up))
        dim = SIMD3(Int(d.x), Int(d.y), Int(d.z))
        grid = [[Int32]](repeating: [], count: dim.x * dim.y * dim.z)
        for (ti, tr) in t.enumerated() {
            let a = p[Int(tr.x)], b = p[Int(tr.y)], c = p[Int(tr.z)]
            let tlo = simd_min(a, simd_min(b, c)), thi = simd_max(a, simd_max(b, c))
            let i0 = cellIndex(tlo), i1 = cellIndex(thi)
            for z in i0.z...i1.z { for y in i0.y...i1.y { for x in i0.x...i1.x { grid[(z * dim.y + y) * dim.x + x].append(Int32(ti)) } } }
        }
    }

    private func cellIndex(_ q: SIMD3<Float>) -> SIMD3<Int> {
        let f = ((q - lo) / cell).rounded(.down)
        return SIMD3(min(max(Int(f.x), 0), dim.x - 1), min(max(Int(f.y), 0), dim.y - 1), min(max(Int(f.z), 0), dim.z - 1))
    }

    /// Closest point of triangle (a, b, c) to p: barycentric (Ericson, Real-Time Collision Detection).
    static func closest(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return SIMD3(1, 0, 0) }
        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return SIMD3(0, 1, 0) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { let v = d1 / (d1 - d3); return SIMD3(1 - v, v, 0) }
        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return SIMD3(0, 0, 1) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { let w = d2 / (d2 - d6); return SIMD3(1 - w, 0, w) }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 { let w = (d4 - d3) / ((d4 - d3) + (d5 - d6)); return SIMD3(0, 1 - w, w) }
        let den = 1 / (va + vb + vc)
        let v = vb * den, w = vc * den
        return SIMD3(1 - v - w, v, w)
    }

    /// The smooth frame of a triangle given its three (current or rest) positions and the three vertex normals and barycentrics.
    @inline(__always)
    static func frame(_ pa: SIMD3<Float>, _ pb: SIMD3<Float>, _ na: SIMD3<Float>, _ nb: SIMD3<Float>, _ nc: SIMD3<Float>, _ w: SIMD3<Float>)
        -> (t: SIMD3<Float>, b: SIMD3<Float>, n: SIMD3<Float>) {
        var n = na * w.x + nb * w.y + nc * w.z
        let l = simd_length(n)
        n = l > 1e-9 ? n / l : SIMD3(0, 1, 0)
        var t = pb - pa
        t -= n * simd_dot(t, n)
        let tl = simd_length(t)
        t = tl > 1e-9 ? t / tl : simd_normalize(simd_cross(n, SIMD3(0, 1, 0.001)))
        return (t, simd_cross(n, t), n)
    }

    /// Binds a rest-space point to the egg surface (nil only if the mesh has no triangles).
    func bind(_ p: SIMD3<Float>) -> SurfaceBind? {
        guard !tris.isEmpty else { return nil }
        let c0 = cellIndex(p)
        var best = Float.infinity, bestT = -1, bestW = SIMD3<Float>.zero
        var seen = Set<Int32>()
        var r = 0
        while r <= 14 {
            for z in max(c0.z - r, 0)...min(c0.z + r, dim.z - 1) {
                for y in max(c0.y - r, 0)...min(c0.y + r, dim.y - 1) {
                    for x in max(c0.x - r, 0)...min(c0.x + r, dim.x - 1) {
                        if r > 0, abs(x - c0.x) != r, abs(y - c0.y) != r, abs(z - c0.z) != r { continue }       // the shell of cells only
                        for ti in grid[(z * dim.y + y) * dim.x + x] where seen.insert(ti).inserted {
                            let tr = tris[Int(ti)]
                            let a = pos[Int(tr.x)], b = pos[Int(tr.y)], c = pos[Int(tr.z)]
                            let w = Self.closest(p, a, b, c)
                            let q = a * w.x + b * w.y + c * w.z
                            let d = simd_distance_squared(p, q)
                            if d < best { best = d; bestT = Int(ti); bestW = w }
                        }
                    }
                }
            }
            if bestT >= 0, best.squareRoot() <= Float(r) * cell { break }
            r += 1
        }
        guard bestT >= 0 else { return nil }
        let tr = tris[bestT]
        let a = pos[Int(tr.x)], b = pos[Int(tr.y)], c = pos[Int(tr.z)]
        let q = a * bestW.x + b * bestW.y + c * bestW.z
        let f = Self.frame(a, b, nrm[Int(tr.x)], nrm[Int(tr.y)], nrm[Int(tr.z)], bestW)
        let d = p - q
        return SurfaceBind(tri: tr, bary: bestW, off: SIMD3(simd_dot(d, f.t), simd_dot(d, f.b), simd_dot(d, f.n)))
    }

    /// The bound point in the REST pose (a check: it must land on the authored position).
    func restPoint(_ s: SurfaceBind) -> SIMD3<Float> {
        let a = pos[Int(s.tri.x)], b = pos[Int(s.tri.y)], c = pos[Int(s.tri.z)]
        let q = a * s.bary.x + b * s.bary.y + c * s.bary.z
        let f = Self.frame(a, b, nrm[Int(s.tri.x)], nrm[Int(s.tri.y)], nrm[Int(s.tri.z)], s.bary)
        return q + f.t * s.off.x + f.b * s.off.y + f.n * s.off.z
    }

    /// The bound point on a skinned body: `skin` = 6 floats per render vertex (position, smooth normal), as the CPU skinner writes them.
    @inline(__always)
    static func world(_ s: SurfaceBind, skin: UnsafePointer<Float>) -> SIMD3<Float> {
        @inline(__always) func P(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o], skin[o + 1], skin[o + 2]) }
        @inline(__always) func N(_ i: UInt32) -> SIMD3<Float> { let o = 6 * Int(i); return SIMD3(skin[o + 3], skin[o + 4], skin[o + 5]) }
        let a = P(s.tri.x), b = P(s.tri.y), c = P(s.tri.z)
        let q = a * s.bary.x + b * s.bary.y + c * s.bary.z
        let f = frame(a, b, N(s.tri.x), N(s.tri.y), N(s.tri.z), s.bary)
        return q + f.t * s.off.x + f.b * s.off.y + f.n * s.off.z
    }
    /// The same on an array of posed positions and normals (tests).
    static func world(_ s: SurfaceBind, positions: [SIMD3<Float>], normals: [SIMD3<Float>]) -> SIMD3<Float> {
        let a = positions[Int(s.tri.x)], b = positions[Int(s.tri.y)], c = positions[Int(s.tri.z)]
        let q = a * s.bary.x + b * s.bary.y + c * s.bary.z
        let f = frame(a, b, normals[Int(s.tri.x)], normals[Int(s.tri.y)], normals[Int(s.tri.z)], s.bary)
        return q + f.t * s.off.x + f.b * s.off.y + f.n * s.off.z
    }
}
