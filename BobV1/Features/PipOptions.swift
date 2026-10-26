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
    static let count = 10
    static let startFraction: Float = 0.90          // of his height, on the back silhouette line
    static let tailEnd: Double = 0.85               // fraction of the tail's length the row reaches
    static let widthOfSpacing: Float = 0.55         // the biggest spike's base width as a fraction of the spacing (the rest are smaller: no overlap)
    static let tiltDeg: Float = 30                  // each spike leans this far from the surface normal toward the tail
    static let slim: Float = 0.8                    // sideways thinning
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
        let L = arc.last ?? 1
        let tn = tones(spec: spec)
        // the ridge path, smoothed: a moving average (about +-0.12) rounds the corner where the tail meets the back with a generous fillet, so the spikes' tangents and
        // normals no longer swing through the crease (the positions stay on the skin so each spike is still planted)
        var sm = curve.map { $0.p }
        for _ in 0..<4 {
            var nx = sm
            for i in 0..<sm.count {
                let lo = max(0, i - 12), hi = min(sm.count - 1, i + 12)
                var acc = SIMD3<Float>(0, 0, 0); for j in lo...hi { acc += sm[j] }
                nx[i] = acc / Float(hi - lo + 1)
            }
            sm = nx
        }
        func smoothFrame(_ i: Int) -> (t: SIMD3<Float>, n: SIMD3<Float>) {
            let t = simd_normalize(sm[min(i + 1, sm.count - 1)] - sm[max(i - 1, 0)])
            return (t, simd_normalize(simd_cross(SIMD3<Float>(1, 0, 0), t)))                // outward, perpendicular to the smoothed path
        }
        struct Sp { var p: SIMD3<Float>; var n: SIMD3<Float>; var t: SIMD3<Float>; var isTail: Bool; var s: Float; var H: Float; var bR: Float; var ax: SIMD3<Float>; var e: Float; var tip: SIMD3<Float> }
        func layout(_ cnt: Int) -> (sp: [Sp], d: Float) {
            let d = L / (Float(cnt) - 0.5)
            var out: [Sp] = []
            var tailIndex = 0
            for k in 0..<cnt {
                let sK = d * 0.5 + Float(k) * d
                var i = 1; while i < arc.count - 1 && arc[i] < sK { i += 1 }
                let a = max(0, min(1, (sK - arc[i - 1]) / max(arc[i] - arc[i - 1], 1e-5)))
                let p = curve[i - 1].p * (1 - a) + curve[i].p * a
                let f = smoothFrame(a < 0.5 ? i - 1 : i)
                let isTail = i - 1 >= backCount
                if isTail { tailIndex += 1 }
                // uniform back spikes; the tail ones taper smoothly, each 85% of the one before
                let H = 1.2 * d * (isTail ? powf(0.85, Float(tailIndex)) : 1), bR = 0.30 * H
                let q = Float(k) / Float(max(cnt - 1, 1)), e = q * q * (3 - 2 * q)
                let tilt = (22 + 50 * e) * Float.pi / 180
                let ax = simd_normalize(f.n * cosf(tilt) + f.t * sinf(tilt))
                let base = p - f.n * (0.2 * bR)
                out.append(Sp(p: base, n: f.n, t: f.t, isTail: isTail, s: sK, H: H, bR: bR, ax: ax, e: e,
                              tip: base + ax * H + f.t * (H * (0.10 + 0.32 * e))))
            }
            return (out, d)
        }
        // keep the rhythm at the TIPS too: if two neighbouring tips come closer than 0.8 of the base spacing (the corner crowds them), drop the one nearer the crease
        // (at most twice); every other spike stays exactly where the even spacing put it
        let cnt = count
        var lay = layout(cnt)
        let creaseS = arc[min(backCount, arc.count - 1)]
        for _ in 0..<2 {
            var worst = -1, wd = 0.8 * lay.d
            for k in 1..<lay.sp.count {
                let dd = simd_distance(lay.sp[k].tip, lay.sp[k - 1].tip)
                if dd < wd { wd = dd; worst = k }
            }
            if worst < 0 { break }
            let drop = abs(lay.sp[worst].s - creaseS) < abs(lay.sp[worst - 1].s - creaseS) ? worst : worst - 1
            lay.sp.remove(at: drop)
        }
        var widths: [Float] = [], centres: [Float] = []
        var tailFirst = -1
        for (k, sp) in lay.sp.enumerated() {
            widths.append(2 * sp.bR); centres.append(sp.s)
            let start = m.pos.count
            m.cone(base: sp.p, axis: sp.ax, height: sp.H, baseR: sp.bR, bend: sp.t, curve: 0.10 + 0.32 * sp.e, tipSoft: 0.34, lateral: SIMD3(1, 0, 0), tones: tn)
            if sp.isTail { if tailFirst < 0 { tailFirst = start } } else { parts.append(("spike\(k)", start, m.pos.count - start, sp.p)) }
        }
        var gap = Float.infinity
        for k in 1..<lay.sp.count { gap = min(gap, (centres[k] - widths[k] / 2) - (centres[k - 1] + widths[k - 1] / 2)) }
        lastLayout = (lay.d, widths, gap)
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
