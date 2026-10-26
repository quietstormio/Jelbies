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
    static let count = 7
    static let startFraction: Float = 0.82          // of his height, on the back silhouette line
    static let tailEnd: Double = 0.85               // fraction of the tail's length the row reaches
    static let widthOfSpacing: Float = 0.55         // the biggest spike's base width as a fraction of the spacing (the rest are smaller: no overlap)
    static let tiltDeg: Float = 30                  // each spike leans this far from the surface normal toward the tail
    static let slim: Float = 0.8                    // sideways thinning
    static let backFractions: [Float] = [0]          // (marker: the back spikes are rigid on the skin, see FeatureSet.partRotation)
    /// Diagnostics of the last layout: spacing, per-spike base widths and the smallest gap between neighbours (all along the curve).
    nonisolated(unsafe) static var lastLayout: (spacing: Float, widths: [Float], minGap: Float) = (0, [], 0)

    /// The orange of the shipped spikes: the base tone and the lighter tip tone (sampled from the art: lowest / highest vertices along the spike).
    static func tones(spec: FeatureSpec) -> (base: SIMD3<Float>, tip: SIMD3<Float>) {
        guard let art = FeatureMeshes.art("pip_c_final"), let p = art.parts.first(where: { $0.name == "spike_00" }), let sp = spec.spines.first(where: { $0.part == "spike_00" }) else {
            return (SIMD3(0.72, 0.30, 0.06), SIMD3(0.95, 0.55, 0.15))
        }
        let n0 = simd_normalize(sp.normal.v3), piv = sp.pivot.v3
        let order = p.positions.indices.sorted { simd_dot(p.positions[$0] - piv, n0) < simd_dot(p.positions[$1] - piv, n0) }
        func mean(_ idx: ArraySlice<Int>) -> SIMD3<Float> { idx.reduce(SIMD3<Float>(0, 0, 0)) { $0 + p.colors[$1] } / Float(max(idx.count, 1)) }
        let k = max(order.count / 6, 1)
        return (mean(order[0..<k]), mean(order[(order.count - k)...]))
    }

    struct Mesh {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], ao: [Float] = [], idx: [UInt32] = []
        /// A clean slightly pointed cone: sunk base with a soft flare that blends into the skin, straight taper to a softly rounded tip (like the tail's), smooth normals.
        mutating func cone(base: SIMD3<Float>, axis a: SIMD3<Float>, height H: Float, baseR b: Float, lateral: SIMD3<Float>, tones t: (base: SIMD3<Float>, tip: SIMD3<Float>)) {
            let seg = 18, tipR = 0.11 * b
            var u0 = lateral - a * simd_dot(lateral, a); u0 = simd_normalize(u0)
            let v0 = simd_cross(a, u0)
            var prof: [(h: Float, r: Float)] = []
            prof.append((-0.35 * b, 1.30 * b))                              // buried flare
            prof.append((0, 1.12 * b))
            prof.append((0.06 * H, 1.0 * b))
            let nBody = 7
            let hTip = H - tipR
            for i in 1...nBody {
                let u = Float(i) / Float(nBody)
                let h = 0.06 * H + (hTip - 0.06 * H) * u
                let r = tipR + (b - tipR) * (1 - (h - 0.06 * H) / (hTip - 0.06 * H))                   // straight cone
                prof.append((h, r))
            }
            let base0 = UInt32(pos.count)
            var rings = 0
            func slopeAngle(_ i: Int) -> Float {
                let a0 = prof[max(i - 1, 0)], a1 = prof[min(i + 1, prof.count - 1)]
                return atanf(-(a1.r - a0.r) / max(a1.h - a0.h, 1e-5))
            }
            func color(_ h: Float) -> SIMD3<Float> { let u = max(0, min(1, h / H)); let w = u * u * (3 - 2 * u); return t.base + (t.tip - t.base) * w }
            for (i, p) in prof.enumerated() {
                let al = slopeAngle(i)
                for j in 0..<seg {
                    let ph = 2 * Float.pi * Float(j) / Float(seg)
                    let rad = u0 * (cosf(ph) * PipSpikes.slim) + v0 * sinf(ph)
                    let radN = simd_normalize(u0 * (cosf(ph) / PipSpikes.slim) + v0 * sinf(ph))
                    pos.append(base + a * p.h + rad * p.r)
                    nrm.append(simd_normalize(radN * cosf(al) + a * sinf(al))); col.append(color(p.h)); ao.append(1)
                }
                rings += 1
            }
            let capRings = 4
            for k in 1...capRings {                                           // the softly rounded tip: a small hemisphere
                let th = Float.pi / 2 * Float(k) / Float(capRings)
                for j in 0..<seg {
                    let ph = 2 * Float.pi * Float(j) / Float(seg)
                    let rad = u0 * (cosf(ph) * PipSpikes.slim) + v0 * sinf(ph)
                    let radN = simd_normalize(u0 * (cosf(ph) / PipSpikes.slim) + v0 * sinf(ph))
                    pos.append(base + a * (hTip + tipR * sinf(th)) + rad * (tipR * cosf(th)))
                    nrm.append(simd_normalize(radN * cosf(th) + a * sinf(th))); col.append(color(H)); ao.append(1)
                }
                rings += 1
            }
            for i in 0..<(rings - 1) { for j in 0..<seg {
                let p0 = base0 + UInt32(i * seg + j), p1 = base0 + UInt32(i * seg + (j + 1) % seg)
                let p2 = base0 + UInt32((i + 1) * seg + j), p3 = base0 + UInt32((i + 1) * seg + (j + 1) % seg)
                idx += [p0, p2, p1, p1, p2, p3]
            } }
        }
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
        let tn0 = tones(spec: spec)
        let tn = (base: tn0.base * 0.85, tip: tn0.base * 1.08)          // the shipped orange, a little deeper (the art's pale tip washes out on a thin cone)
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
            // size from the spacing: small at the top, largest at the lower back (index 3), then tapering down along the tail; base width <= 55% of the spacing
            let taper: [Float] = [0.62, 0.78, 0.92, 1.0, 0.82, 0.62, 0.45]
            let H = taper[k] * 1.3 * d, bR = 0.30 * H
            widths.append(2 * bR); centres.append(sK)
            let ax = simd_normalize(nrm * cosf(tiltDeg * .pi / 180) + tg * sinf(tiltDeg * .pi / 180))
            let base = p - nrm * (0.2 * bR)
            let isTail = i - 1 >= backCount
            let start = m.pos.count
            m.cone(base: base, axis: ax, height: H, baseR: bR, lateral: SIMD3(1, 0, 0), tones: tn)
            if isTail { if tailFirst < 0 { tailFirst = start } } else { parts.append(("spike\(k)", start, m.pos.count - start, base)) }
        }
        var gap = Float.infinity
        for k in 1..<count { gap = min(gap, (centres[k] - widths[k] / 2) - (centres[k - 1] + widths[k - 1] / 2)) }
        lastLayout = (d, widths, gap)
        assert(gap > 0.15 * d, "Pip's spikes overlap")
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
