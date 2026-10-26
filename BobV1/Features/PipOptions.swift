//
//  PipOptions.swift  (PipSpikes)
//  Pip's signature: the ORIGINAL spikes (the shipped mesh, orange, scale 1.0) spaced out in a single row down his back from below the hat line to the
//  lower back, then 3 smaller ones on the top ridge of his teardrop tail (TailBean, part of the body mesh). None on the top of his head, so hats never
//  matter. One rigid part per back spike on its own sunk, surface-bound pivot (it follows the skin); the tail spikes share one part pivoted at the tail
//  root so they ride the tail's sway / wag (FeatureSet.partRotation).
//

import simd
import Foundation

nonisolated enum PipSpikes {
    static let backFractions: [Float] = [0.86, 0.735, 0.61, 0.485]       // of his height, from just below the hat line down to the lower back
    static let backTemplates = ["spike_00", "spike_00", "spike_00", "spike_00"]
    static let backScale: [Float] = [0.9, 0.84, 0.78, 0.72]
    static let tailU: [Double] = [0.30, 0.55, 0.78]                    // along the tail (fraction of its centre line)
    static let tailScale: [Float] = [0.75, 0.62, 0.5]
    static let tailTemplates = ["spike_00", "spike_00", "spike_00"]

    struct Mesh {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], ao: [Float] = [], idx: [UInt32] = []
        /// A template spike of the shipped Pip art with its sunk base (pivot) at `base`, pointing along `normal`, scaled `s` about the base.
        mutating func spike(_ part: String, base: SIMD3<Float>, normal: SIMD3<Float>, scale s: Float, spec: FeatureSpec) {
            guard let art = FeatureMeshes.art("pip_c_final"), let p = art.parts.first(where: { $0.name == part }),
                  let sp = spec.spines.first(where: { $0.part == part }) else { return }
            let crown = SIMD3<Float>(0, spec.top, 0)
            let n0 = simd_normalize(sp.normal.v3), piv = crown + sp.pivot.v3
            let q = simd_quatf(from: n0, to: simd_normalize(normal))
            let off = UInt32(pos.count)
            for k in 0..<p.positions.count {
                var lv = (crown + p.positions[k]) - piv; lv.x *= 0.8                  // slimmer sideways
                pos.append(base + q.act(lv) * s)
                nrm.append(q.act(p.normals[k])); col.append(p.colors[k]); ao.append(p.ao[k])
            }
            idx += p.indices.map { $0 + off }
        }
    }

    /// Surface point + normal on the centre line at height y (back: z < 0).
    static func centre(_ body: WearBody, y: Float) -> (p: SIMD3<Float>, n: SIMD3<Float>) {
        var best = -1, bz = Float.infinity
        for i in 0..<body.eggVertexLimit {
            let q = body.pos[i]
            guard abs(q.x) < 0.05, abs(q.y - y) < 0.04, q.z < 0 else { continue }
            if q.z < bz { bz = q.z; best = i }
        }
        guard best >= 0 else { return (SIMD3(0, y, -0.45), SIMD3(0, 0, -1)) }
        return (body.pos[best], simd_normalize(body.nrm[best]))
    }

    static func build(body: WearBody, spec: FeatureSpec) -> FeaturePrepared {
        let r = FeaturePrepared(art: "pip_spikes", key: "ridge")
        var m = Mesh()
        var parts: [(String, Int, Int, SIMD3<Float>)] = []
        let h = spec.top
        for k in 0..<backFractions.count {
            let c = centre(body, y: backFractions[k] * h)
            let first = m.pos.count
            let base = c.p - c.n * 0.03
            m.spike(backTemplates[k], base: base, normal: simd_normalize(c.n * 0.35 + SIMD3(0, 1.0, 0)), scale: backScale[k], spec: spec)
            parts.append(("spike\(k)", first, m.pos.count - first, base))
        }
        let sh = TailBean.shape
        let root = SIMD3<Float>(Float(sh.root.x), Float(sh.root.y), Float(sh.root.z))
        let first = m.pos.count
        for k in 0..<tailU.count {
            let rg = sh.ridge(sh.sink + tailU[k] * (sh.length - sh.sink))
            let up = SIMD3<Float>(Float(rg.up.x), Float(rg.up.y), Float(rg.up.z))
            let c = SIMD3<Float>(Float(rg.p.x), Float(rg.p.y), Float(rg.p.z))
            let tg = SIMD3<Float>(Float(sh.tangent(sh.sink + tailU[k] * (sh.length - sh.sink)).x), Float(sh.tangent(sh.sink + tailU[k] * (sh.length - sh.sink)).y), Float(sh.tangent(sh.sink + tailU[k] * (sh.length - sh.sink)).z))
            m.spike(tailTemplates[k], base: c + up * Float(rg.r) * 0.95, normal: simd_normalize(up * 1.0 + tg * 0.3), scale: tailScale[k], spec: spec)
        }
        parts.append(("tail", first, m.pos.count - first, root))
        for (pi, pp) in parts.enumerated() {
            var pr = FeaturePrepared.Part(name: pp.0)
            pr.first = r.rest.count; pr.count = pp.2; pr.pivot = pp.3
            pr.bind = body.bind(pp.3) ?? SurfaceBind(); pr.side = pi
            for k in pp.1..<(pp.1 + pp.2) {
                r.rest.append(m.pos[k]); r.off.append(m.pos[k] - pp.3); r.nrm.append(m.nrm[k]); r.col.append(m.col[k]); r.ao.append(m.ao[k]); r.partOfVertex.append(pi)
            }
            r.parts.append(pr)
        }
        r.anchor = root
        var t = 0
        while t + 2 < m.idx.count {
            let i0 = m.idx[t], i1 = m.idx[t + 1], i2 = m.idx[t + 2]
            let g = simd_cross(m.pos[Int(i1)] - m.pos[Int(i0)], m.pos[Int(i2)] - m.pos[Int(i0)])
            let nn = m.nrm[Int(i0)] + m.nrm[Int(i1)] + m.nrm[Int(i2)]
            if simd_dot(g, nn) >= 0 { r.idx += [i0, i1, i2] } else { r.idx += [i0, i2, i1] }
            t += 3
        }
        return r
    }
}
