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
    static let startFraction: Float = 0.90          // of his height, on the back silhouette line
    static let tailEnd: Double = 0.80               // fraction of the tail's length the row reaches
    static let widthOfSpacing: Float = 0.55         // the biggest spike's base width as a fraction of the spacing (the rest are smaller: no overlap)
    static let tiltDeg: Float = 30                  // each spike leans this far from the surface normal toward the tail
    static let slim: Float = 1.0                    // sideways thinning
    static let backFractions: [Float] = [0]          // (marker: the back spikes are rigid on the skin, see FeatureSet.partRotation)
    /// Diagnostics of the last layout: spacing, per-spike base widths and the smallest gap between neighbours (all along the curve).
    nonisolated(unsafe) static var lastLayout: (spacing: Float, widths: [Float], minGap: Float) = (0, [], 0)

    /// The shipped spikes' orange (the mean vertex colour of the art, measured from feature_pip_c_final.bin: about (0.92, 0.52, 0.15) linear).
    static func tones(spec: FeatureSpec) -> (base: SIMD3<Float>, tip: SIMD3<Float>) { (SIMD3(0.92, 0.48, 0.13), SIMD3(0.95, 0.56, 0.17)) }

    struct Mesh {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], ao: [Float] = [], idx: [UInt32] = []
        /// A clean slightly pointed cone that bends gently toward `bend` (a small claw / thorn): sunk base with a soft flare that blends into the skin, a straight
        /// taper to a softly rounded tip, smooth normals. `curve` = how far the tip is carried along `bend`, as a fraction of the height; `tipSoft` = tip radius / base radius.
        mutating func cone(base: SIMD3<Float>, axis a: SIMD3<Float>, height H: Float, baseR b: Float, bend: SIMD3<Float>, curve: Float, tipSoft: Float,
                           lateral: SIMD3<Float>, tones t: (base: SIMD3<Float>, tip: SIMD3<Float>)) {
            let seg = 18, tipR = tipSoft * b
            var bd = bend - a * simd_dot(bend, a); bd = simd_length(bd) > 1e-5 ? simd_normalize(bd) : a
            func centre(_ h: Float) -> SIMD3<Float> { let q = max(h, 0) / H; return base + a * h + bd * (curve * H * q * q) }
            func tangent(_ h: Float) -> SIMD3<Float> { simd_normalize(a + bd * (2 * curve * max(h, 0) / H)) }
            var prof: [(h: Float, r: Float)] = []
            prof.append((-0.35 * b, 1.30 * b))                              // buried flare
            prof.append((0, 1.12 * b))
            prof.append((0.06 * H, 1.0 * b))
            let nBody = 8
            let hTip = H - tipR
            for i in 1...nBody {
                let u = Float(i) / Float(nBody)
                let h = 0.06 * H + (hTip - 0.06 * H) * u
                prof.append((h, tipR + (b - tipR) * pow(1 - (h - 0.06 * H) / (hTip - 0.06 * H), 0.7)))        // gumdrop-ish taper (slightly convex)
            }
            let base0 = UInt32(pos.count)
            var rings = 0
            func slopeAngle(_ i: Int) -> Float {
                let a0 = prof[max(i - 1, 0)], a1 = prof[min(i + 1, prof.count - 1)]
                return atanf(-(a1.r - a0.r) / max(a1.h - a0.h, 1e-5))
            }
            func color(_ h: Float) -> SIMD3<Float> { let u = max(0, min(1, h / H)); let w = u * u * (3 - 2 * u); return t.base + (t.tip - t.base) * w }
            func frame(_ h: Float) -> (u: SIMD3<Float>, v: SIMD3<Float>, t: SIMD3<Float>) {
                let tg = tangent(h)
                let u = simd_normalize(lateral - tg * simd_dot(lateral, tg))
                return (u, simd_cross(tg, u), tg)
            }
            for (i, p) in prof.enumerated() {
                let al = slopeAngle(i), f = frame(p.h), c = centre(p.h)
                for j in 0..<seg {
                    let ph = 2 * Float.pi * Float(j) / Float(seg)
                    let rad = f.u * (cosf(ph) * PipSpikes.slim) + f.v * sinf(ph)
                    let radN = simd_normalize(f.u * (cosf(ph) / PipSpikes.slim) + f.v * sinf(ph))
                    pos.append(c + rad * p.r)
                    nrm.append(simd_normalize(radN * cosf(al) + f.t * sinf(al))); col.append(color(p.h)); ao.append(1)
                }
                rings += 1
            }
            let capRings = 5
            let fc = frame(hTip), cc = centre(hTip)
            for k in 1...capRings {                                           // the softly rounded tip: a small hemisphere
                let th = Float.pi / 2 * Float(k) / Float(capRings)
                for j in 0..<seg {
                    let ph = 2 * Float.pi * Float(j) / Float(seg)
                    let rad = fc.u * (cosf(ph) * PipSpikes.slim) + fc.v * sinf(ph)
                    let radN = simd_normalize(fc.u * (cosf(ph) / PipSpikes.slim) + fc.v * sinf(ph))
                    pos.append(cc + fc.t * (tipR * sinf(th)) + rad * (tipR * cosf(th)))
                    nrm.append(simd_normalize(radN * cosf(th) + fc.t * sinf(th))); col.append(color(H)); ao.append(1)
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
        func f3(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
        // ---- a short row of small rounded cones along the TOP ridge of the tail only (none on the head or the back), evenly spaced from the root to near the tip
        let sh = TailBean.shape
        let tn = tones(spec: spec)
        // spike 1 sits on the body's back above the root (its own rigid part on the skin); spike 2 just above the root; spikes 3-6 along the tail's top ridge
        var parts: [(String, Int, Int, SIMD3<Float>)] = []
        var widths: [Float] = [], centres: [Float] = []
        var tailSpikes: [(String, Int, Int, SIMD3<Float>, Int, SIMD3<Float>)] = []
        let W = Float(sh.width)
        func hOf(_ u: Float) -> Float { 0.23 * W * (1 - 0.4 * u) }                       // height; base diameter = height / 1.3
        // spike 1: on the back silhouette line, 35% of the way up from the root to the top
        do {
            let y = Double(sh.root.y) + 0.5 * (Double(spec.top) - sh.root.y)
            var lo = -1.2, hi = 0.0
            for _ in 0..<40 { let mid = (lo + hi) / 2; if BobForm.sdf(SIMD3(0, y, mid)) > 0 { lo = mid } else { hi = mid } }
            let p = SIMD3<Double>(0, y, hi), n = f3(BobForm.normal(p))
            var tg = SIMD3<Float>(0, -1, 0); tg -= n * simd_dot(tg, n); tg = simd_normalize(tg)
            let H: Float = 0.20, bR = H / 2.0
            let ax = simd_normalize(n * cosf(0.21) + tg * sinf(0.21))
            let base = f3(p) - n * (0.3 * bR)
            let start = m.pos.count
            m.cone(base: base, axis: ax, height: H, baseR: bR, bend: tg, curve: 0.06, tipSoft: 0.38, lateral: SIMD3(1, 0, 0), tones: tn)
            parts.append(("spike0", start, m.pos.count - start, base))
            widths.append(2 * bR); centres.append(0)
        }
        let ts: [Double] = [0.10, 0.33, 0.56, 0.78].map { sh.sink + $0 * (sh.length - sh.sink) }
        var arcS: Float = 0, lastP: SIMD3<Float>? = nil
        for (k, t) in ts.enumerated() {
            let rg = sh.ridge(t), fr = sh.frame(t), tg = sh.tangent(t)
            let ridgeP = f3(rg.p + rg.up * rg.r)
            if let lp = lastP { arcS += simd_distance(lp, ridgeP) }
            lastP = ridgeP
            let H = min(0.24, max(0.09, 0.8 * Float(rg.r))), bR = H / 2.0
            let up = f3(rg.up), tgF = f3(tg)
            let ax = simd_normalize(up * cosf(0.21) + tgF * sinf(0.21))
            let base = ridgeP - up * (0.3 * bR)
            let start = m.pos.count
            m.cone(base: base, axis: ax, height: H, baseR: bR, bend: tgF, curve: 0.06, tipSoft: 0.38, lateral: f3(fr.side), tones: tn)
            widths.append(2 * bR); centres.append(arcS + 10 * Float(k + 1))
            // the skin vertex on the tail's top ridge nearest this spike
            let ring = max(1, min(TailBean.bodyRings, Int((t / sh.length * Double(TailBean.bodyRings)).rounded())))
            let rc = sh.point(sh.length * Double(ring) / Double(TailBean.bodyRings)), ru = sh.frame(sh.length * Double(ring) / Double(TailBean.bodyRings)).up
            var bestJ = 0, bestD = -Double.infinity
            for j in 0..<TailBean.around { let q = TailBean.local.pos[1 + TailBean.around * (ring - 1) + j] - rc; let d = simd_dot(q, ru); if d > bestD { bestD = d; bestJ = j } }
            let local = 1 + TailBean.around * (ring - 1) + bestJ
            tailSpikes.append(("tail\(k)", start, m.pos.count - start, base, local, f3(TailBean.local.pos[local])))
        }
        var gap = Float.infinity
        for k in 1..<centres.count { gap = min(gap, (centres[k] - widths[k] / 2) - (centres[k - 1] + widths[k - 1] / 2)) }
        lastLayout = (centres.count > 1 ? centres[1] - centres[0] : 0, widths, gap)
        let root = f3(sh.root)
        let allParts = parts.map { ($0.0, $0.1, $0.2, $0.3, -1, SIMD3<Float>.zero) } + tailSpikes
        for (pi, pp) in allParts.enumerated() {
            var pr = FeaturePrepared.Part(name: pp.0)
            pr.first = r.rest.count; pr.count = pp.2; pr.pivot = pp.3
            pr.tailLocal = pp.4; pr.skinAnchor = pp.5
            pr.bind = pp.4 >= 0 ? SurfaceBind() : (body.bind(pp.3) ?? SurfaceBind()); pr.side = pi
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
