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
    /// The ridge layout (see build): spike count, where the row starts on the back, how far down the tail it runs, and the size / tilt rules.
    static let count = 6
    static let startFraction: Float = 0.74          // of his height, on the back silhouette line
    static let tailEnd: Double = 0.85               // fraction of the tail's length the row reaches
    static let widthOfSpacing: Float = 0.55         // the biggest spike's base width as a fraction of the spacing (the rest are smaller: no overlap)
    static let tiltDeg: Float = 12                  // each spike leans this far from the surface normal toward the tail
    static let slim: Float = 0.8                    // sideways thinning
    static let backFractions: [Float] = [0]          // (marker: the back spikes are rigid on the skin, see FeatureSet.partRotation)
    /// Diagnostics of the last layout: spacing, per-spike base widths and the smallest gap between neighbours (all along the curve).
    nonisolated(unsafe) static var lastLayout: (spacing: Float, widths: [Float], minGap: Float) = (0, [], 0)

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
                var lv = (crown + p.positions[k]) - piv; lv.x *= PipSpikes.slim                  // slimmer sideways
                pos.append(base + q.act(lv) * s)
                nrm.append(q.act(p.normals[k])); col.append(p.colors[k]); ao.append(p.ao[k])
            }
            idx += p.indices.map { $0 + off }
        }
    }

    /// Base width (along the spike's lean plane) of a template, measured just above its sunk base.
    static func baseWidth(_ part: String, spec: FeatureSpec) -> Float {
        guard let art = FeatureMeshes.art("pip_c_final"), let p = art.parts.first(where: { $0.name == part }), let sp = spec.spines.first(where: { $0.part == part }) else { return 0.1 }
        let crown = SIMD3<Float>(0, spec.top, 0), piv = crown + sp.pivot.v3, n0 = simd_normalize(sp.normal.v3)
        let along = simd_normalize(simd_cross(SIMD3<Float>(1, 0, 0), n0))
        var lo = Float.infinity, hi = -Float.infinity
        for q in p.positions {
            let lv = crown + q - piv, h = simd_dot(lv, n0)
            if h > 0.02 && h < 0.07 { let a = simd_dot(lv, along); lo = min(lo, a); hi = max(hi, a) }
        }
        return hi > lo ? hi - lo : 0.1
    }

    static func build(body: WearBody, spec: FeatureSpec) -> FeaturePrepared {
        let r = FeaturePrepared(art: "pip_spikes", key: "ridge")
        var m = Mesh()
        var parts: [(String, Int, Int, SIMD3<Float>)] = []
        let h = spec.top
        func f3(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
        // ---- one continuous ridge curve: the back silhouette line from 74% of his height down to the tail root, then the tail's top centre line
        let sh = TailBean.shape
        var tailPts: [(p: SIMD3<Float>, n: SIMD3<Float>)] = []
        let t0 = sh.sink, t1 = sh.sink + tailEnd * (sh.length - sh.sink)
        var t = t0
        while t <= t1 { let rg = sh.ridge(t); tailPts.append((f3(rg.p + rg.up * (rg.r * 0.95)), f3(rg.up))); t += 0.01 }
        var curve: [(p: SIMD3<Float>, n: SIMD3<Float>)] = []
        var y = startFraction * h
        let yTail = tailPts.first?.p.y ?? 0.5
        while y > yTail {
            var lo = -1.2, hi = 0.0
            for _ in 0..<40 { let mid = (lo + hi) / 2; if BobForm.sdf(SIMD3(0, Double(y), mid)) > 0 { lo = mid } else { hi = mid } }
            let p = SIMD3<Double>(0, Double(y), hi)
            curve.append((f3(p), f3(BobForm.normal(p)))); y -= 0.01
        }
        let backCount = curve.count
        curve += tailPts
        var arc: [Float] = [0]
        for i in 1..<curve.count { arc.append(arc[i - 1] + simd_distance(curve[i].p, curve[i - 1].p)) }
        let L = arc.last ?? 1, d = L / (Float(count) - 0.5)
        let wt: Float = 0.10                              // the shipped spike's base width at scale 1 (measured by eye on the renders)
        var widths: [Float] = [], centres: [Float] = []
        let first = m.pos.count
        var tailFirst = -1
        for k in 0..<count {
            let sK = d * 0.5 + Float(k) * d
            var i = 1; while i < arc.count - 1 && arc[i] < sK { i += 1 }
            let a = max(0, min(1, (sK - arc[i - 1]) / max(arc[i] - arc[i - 1], 1e-5)))
            let p = curve[i - 1].p * (1 - a) + curve[i].p * a
            let nrm = simd_normalize(curve[i - 1].n * (1 - a) + curve[i].n * a)
            var tg = curve[min(i + 1, curve.count - 1)].p - curve[max(i - 2, 0)].p
            tg -= nrm * simd_dot(tg, nrm); tg = simd_normalize(tg)
            // size from the spacing: biggest at index 1, stepping smoothly down to 45% at the last spike; the base width never exceeds 55% of the spacing
            let taper: Float = k == 0 ? 0.85 : (k == 1 ? 1.0 : 1.0 - 0.55 * Float(k - 1) / Float(count - 2))
            let w = taper * widthOfSpacing * d
            let scale = min(w / wt, taper * 0.85 * d / 0.2022)        // base never over 55% of the spacing, and the HEIGHT stays under the spacing too (no leaning onto the neighbour)
            widths.append(w); centres.append(sK)
            let ax = simd_normalize(nrm * cosf(tiltDeg * .pi / 180) + tg * sinf(tiltDeg * .pi / 180))
            let base = p - nrm * (0.03 * scale)
            let isTail = i - 1 >= backCount
            let start = m.pos.count
            m.spike("spike_00", base: base, normal: ax, scale: scale, spec: spec)
            if isTail { if tailFirst < 0 { tailFirst = start } } else { parts.append(("spike\(k)", start, m.pos.count - start, base)) }
        }
        var gap = Float.infinity
        for k in 1..<count { gap = min(gap, (centres[k] - widths[k] / 2) - (centres[k - 1] + widths[k - 1] / 2)) }
        lastLayout = (d, widths, gap)
        assert(gap > 0.3 * d, "Pip's spikes overlap")
        _ = first
        let root = f3(sh.root)
        if tailFirst >= 0 { parts.append(("tail", tailFirst, m.pos.count - tailFirst, root)) }
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
        var ti = 0
        while ti + 2 < m.idx.count {
            let i0 = m.idx[ti], i1 = m.idx[ti + 1], i2 = m.idx[ti + 2]
            let g = simd_cross(m.pos[Int(i1)] - m.pos[Int(i0)], m.pos[Int(i2)] - m.pos[Int(i0)])
            let nn = m.nrm[Int(i0)] + m.nrm[Int(i1)] + m.nrm[Int(i2)]
            if simd_dot(g, nn) >= 0 { r.idx += [i0, i1, i2] } else { r.idx += [i0, i2, i1] }
            ti += 3
        }
        return r
    }
}
