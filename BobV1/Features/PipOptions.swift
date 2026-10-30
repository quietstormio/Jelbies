//
//  PipOptions.swift  (PipSpikes)
//  Pip's signature: the ORIGINAL spikes (the shipped mesh, orange, scale 1.0) spaced out in a single row down his back from below the hat line to the
//  lower back, then 3 smaller ones on the top ridge of his teardrop tail (TailBean, part of the body mesh). None on the top of his head, so hats never
//  matter. One rigid part per back spike on its own sunk, surface-bound pivot (it follows the skin); the tail spikes share one part pivoted at the tail
//  root so they ride the tail's sway / wag (FeatureSet.partRotation).
//

import simd
import Foundation

/// Which layout Pip's spike row stands in (restyled variants): bare, or re-flowed under a crown-enclosing hat (`brim` = the hat's lowest y, 1 cm steps) and around the neck pieces
/// he wears (`avoid` = their art ids, sorted): the row threads around the cords and cloth instead of hiding under them (PipSpikes.build).
nonisolated struct RidgeLayout: Hashable, Sendable {
    var brim: Float?
    var avoid: [String]
    init(brim: Float? = nil, avoid: [String] = []) { self.brim = brim.map { ($0 * 100).rounded() / 100 }; self.avoid = Array(Set(avoid)).sorted() }
    static let bare = RidgeLayout()
    var isBare: Bool { brim == nil && avoid.isEmpty }
    var key: String { isBare ? "pip_ridge" : String(format: "pip_ridge|b%@|a:%@", brim.map { String(format: "%.2f", $0) } ?? "-", avoid.joined(separator: ",")) }
}

nonisolated enum PipSpikes {
    /// The ridge layout (see build): spike count, where the row starts on the back, how far down the tail it runs, and the size / tilt rules.
    static let count = 5
    static let startFraction: Float = 0.90          // of his height, on the back silhouette line
    static let tailEnd: Double = 0.80               // fraction of the tail's length the row reaches
    static let widthOfSpacing: Float = 0.55         // the biggest spike's base width as a fraction of the spacing (the rest are smaller: no overlap)
    static let tiltDeg: Float = 30                  // each spike leans this far from the surface normal toward the tail
    /// Restyle (T1 / T2): the row starts at the same height on the back as the shipped one (the thinner tail leaves the back lower, which would otherwise pull the whole row down onto the tail),
    /// and heights are explicit (mean of today's row x the variant's scale x a per-spike grade) so the scales read as true multiples of today's spikes.
    static let rowStartY: Double = 1.203
    static let restyledBareSpacing: Float = 0.32               // the bare row's arc spacing between spikes (about)
    static let reflowTailEnd: Double = 0.97                   // under a hat the row also runs a little further down the tail (its bare end is 0.86), since the back part is shorter
    static let rowStartOffset: Double = 0.063                 // the first spike's base stands this far below the path's start (rowStartY 1.203 -> first base at about 1.14)
    static let restyledMinChord: Float = 0.30                 // minimum straight-line spacing of the ridge spikes
    static let restyledBaseHeight: Float = 0.095              // the shipped row's mean height
    static let restyledGrade: [Float] = [0.80, 1.0, 1.0, 0.92, 0.75]          // per spike, top of the back to the tail tip: biggest at the junction / middle, smallest at the tip
    static let slim: Float = 1.0                    // sideways thinning
    static let backFractions: [Float] = [0]          // (marker: the back spikes are rigid on the skin, see FeatureSet.partRotation)
    /// Diagnostics of the last layout: spacing, per-spike base widths and the smallest gap between neighbours (all along the curve).
    nonisolated(unsafe) static var debug = ""
    /// The smallest gap (spike surface to a worn neck piece / hat vertex) of the last layout built; negative = a spike touches the piece (diagnostic, the tests read it).
    nonisolated(unsafe) static var lastClearance: Float = .infinity
    nonisolated(unsafe) static var lastLayout: (spacing: Float, widths: [Float], minGap: Float) = (0, [], 0)

    /// The shipped spikes' orange (the mean vertex colour of the art, measured from feature_pip_c_final.bin: about (0.92, 0.52, 0.15) linear).
    static func tones(spec: FeatureSpec) -> (base: SIMD3<Float>, tip: SIMD3<Float>) { (SIMD3(0.92, 0.48, 0.13), SIMD3(0.95, 0.56, 0.17)) }

    struct Mesh {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = [], ao: [Float] = [], idx: [UInt32] = []
        /// A clean slightly pointed cone that bends gently toward `bend` (a small claw / thorn): sunk base with a soft flare that blends into the skin, a straight
        /// taper to a softly rounded tip, smooth normals. `curve` = how far the tip is carried along `bend`, as a fraction of the height; `tipSoft` = tip radius / base radius.
        mutating func cone(base: SIMD3<Float>, axis a: SIMD3<Float>, height H: Float, baseR b: Float, bend: SIMD3<Float>, curve: Float, tipSoft: Float,
                           lateral: SIMD3<Float>, tones t: (base: SIMD3<Float>, tip: SIMD3<Float>)) {
            let seg = 12, tipR = tipSoft * b
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

    /// `brimY` (restyled variants only): the lowest point of the crown-enclosing hat he wears. The row then RE-FLOWS: it starts just below the brim line (a base `hatMargin`
    /// under it, so no spike tucks under the brim) and runs down the back and onto the tail with the same even spacing and size grading, instead of vanishing under the hat.
    /// A hat that sits higher than the bare row's first spike changes nothing.
    static func build(body: WearBody, spec: FeatureSpec, layout: RidgeLayout = .bare) -> FeaturePrepared {
        let brimY = layout.brim
        let bareLayout = layout.isBare
        let r = FeaturePrepared(art: "pip_spikes", key: layout.key)
        var m = Mesh()
        func f3(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
        // ---- a short row of small rounded cones along the TOP ridge of the tail only (none on the head or the back), evenly spaced from the root to near the tip
        let sh = TailBean.shape
        let tn = tones(spec: spec)
        var parts: [(String, Int, Int, SIMD3<Float>)] = []
        var widths: [Float] = [], centres: [Float] = []
        var tailSpikes: [(String, Int, Int, SIMD3<Float>, Int, SIMD3<Float>)] = []
        // ---- ONE shared ridge path: down the back's centreline from 47% of his height, over the swell where the back becomes the tail, then along the tail's top.
        // Spikes are spaced evenly by arc length along it and sized by distance from the junction (largest there).
        struct PP { var shown: SIMD3<Float>; var rest: SIMD3<Float>; var n: SIMD3<Float>; var t: Double; var isTail: Bool }
        let sd = TailBean.startDir, sH = TailBean.swellHeight
        func swelled(_ q: SIMD3<Float>) -> SIMD3<Float> { q + sd * (sH * TailBean.swellWeight(q)) }          // (the skin's own swell: Skinner.configureTail)
        func inEgg(_ q: SIMD3<Float>) -> Bool { BobForm.sdf(SIMD3(Double(q.x), Double(q.y), Double(q.z))) <= 0 }
        var path: [PP] = []
        // the first tail ridge sample that stands outside the swelled back
        var tCross = sh.sink
        do {
            var t = sh.sink
            while t < sh.length {
                let rg = sh.ridge(t), rp = f3(rg.p + rg.up * rg.r)
                let inv = rp - sd * (sH * TailBean.swellWeight(rp))
                if !inEgg(inv) { tCross = t; break }
                t += 0.01
            }
        }
        let crossRg = sh.ridge(tCross), crossRest = f3(crossRg.p + crossRg.up * crossRg.r)
        var y = max(0.47 * Double(spec.top), PipTailVariant.active == .current ? Double(crossRest.y) + 0.42 : min(PipSpikes.rowStartY, brimY.map { Double($0 - FeatureSet.hatMargin) + PipSpikes.rowStartOffset } ?? PipSpikes.rowStartY))          // mid-back, but always a good stretch above the junction
        while y > Double(crossRest.y) {
            var lo = -1.2, hi = 0.0
            for _ in 0..<40 { let mid = (lo + hi) / 2; if BobForm.sdf(SIMD3(0, y, mid)) > 0 { lo = mid } else { hi = mid } }
            let p = SIMD3<Double>(0, y, hi)
            path.append(PP(shown: swelled(f3(p)), rest: f3(p), n: f3(BobForm.normal(p)), t: 0, isTail: false))
            y -= 0.01
        }
        let backCount = path.count
        var tt = tCross
        while tt <= sh.sink + (bareLayout ? 0.86 : PipSpikes.reflowTailEnd) * (sh.length - sh.sink) {
            let rg = sh.ridge(tt), rp = f3(rg.p + rg.up * rg.r)
            path.append(PP(shown: rp, rest: rp, n: f3(rg.up), t: tt, isTail: true)); tt += 0.01
        }
        var arc: [Float] = [0]
        for i in 1..<path.count { arc.append(arc[i - 1] + simd_distance(path[i].shown, path[i - 1].shown)) }
        let sJ = arc[min(max(backCount, 0), arc.count - 1)]
        let nSp = count
        let vr = PipTailVariant.active, heightScale = vr.spikeHeightScale, aspect = heightScale / vr.spikeBaseScale
        // ---- the neck pieces / hat the row threads around: every path sample where a spike (at its largest size) would touch one of their back vertices is BLOCKED; the row is spaced
        // evenly over the unblocked length only, so the spikes nearest a cord slide to just above or below it and the rest re-space (restyled variants only)
        var obstacles: [SIMD3<Float>] = []
        if vr.reflowsUnderHat {
            for art in layout.avoid {
                guard let look = WearLook.pieces.first(where: { $0.art == art }), let piece = WearMeshes.prepare(look, body: body) else { continue }
                for q in piece.rest where q.z < -0.2 && abs(q.x) < 0.3 && q.y > 0.25 { obstacles.append(q) }
            }
        }
        let clearGap: Float = 0.022                                                           // spike surface to cloth / cord, at least
        func coneHits(base: SIMD3<Float>, ax: SIMD3<Float>, H: Float, bR: Float, tipSoft: Float) -> Float {          // smallest (distance - spike radius) of the cone's axis samples to the obstacles
            var worst = Float.infinity
            for s in 0...8 {
                let h = H * Float(s) / 8, c = base + ax * h, rad = bR * (1 - (h / H) * (1 - tipSoft))
                for q in obstacles { worst = min(worst, simd_distance(c, q) - rad) }
            }
            return worst
        }
        func tangentAt(_ i: Int, _ n: SIMD3<Float>) -> SIMD3<Float> {
            let raw = simd_normalize(path[min(i + 1, path.count - 1)].shown - path[max(i - 1, 0)].shown)
            return simd_normalize(raw - n * simd_dot(raw, n))
        }
        var blocked = [Bool](repeating: false, count: path.count)
        if !obstacles.isEmpty {
            let H0 = restyledBaseHeight * heightScale, bR0 = H0 / aspect / 2
            for i in path.indices {
                let pt = path[i], lean: Float = pt.isTail ? 0.21 : 0.45
                let ax = simd_normalize(pt.n * cosf(lean) + tangentAt(i, pt.n) * sinf(lean))
                if coneHits(base: pt.rest - pt.n * (0.3 * bR0), ax: ax, H: H0, bR: bR0, tipSoft: vr.spikeTipSoft) < clearGap { blocked[i] = true }
            }
        }
        var aArc: [Float] = [0]
        for i in 1..<path.count { aArc.append(aArc[i - 1] + ((blocked[i] || blocked[i - 1]) ? 0 : simd_distance(path[i].shown, path[i - 1].shown))) }
        let L = aArc.last ?? 1
        var Lreal: Float = 0
        for i in 1..<path.count where !(blocked[i] || blocked[i - 1]) { Lreal += simd_distance(path[i].shown, path[i - 1].shown) }          // the unblocked length in real units (the spike size follows it)
        debug = String(format: "top=%.3f crossRestY=%.3f crossT=%.3f backCount=%d pathCount=%d L=%.3f sJ=%.3f", spec.top, crossRest.y, tCross, backCount, path.count, L, sJ)
        // pass 1: where each spike stands, its normal / lean and its graded size
        struct Sp { var sK: Float; var pt: PP; var n: SIMD3<Float>; var tg: SIMD3<Float>; var H: Float; var asp: Float = 1; var bw: Float { H / asp }; var baseShown: SIMD3<Float> = .zero; var ax: SIMD3<Float> = .zero; var lean: Float = 0.21 }
        var sps: [Sp] = []
        // a hat re-flow packs the same five spikes into a shorter row: the straight-line spacing floor eases to 75% of the even arc spacing (bare: unchanged)
        // a re-flowed row is shorter, so its five spikes are a little smaller (half-way between their bare size and the size that keeps the bare spacing ratio), never bigger
        let reflowSize: Float = bareLayout ? 1 : 0.5 + 0.5 * min(1, (Lreal * 0.87 / Float(nSp - 1)) / PipSpikes.restyledBareSpacing)
        let rowMinChord: Float = bareLayout ? PipSpikes.restyledMinChord : min(PipSpikes.restyledMinChord, 0.75 * Lreal * 0.87 / Float(nSp - 1))
        // restyle (PipTailVariant): spikes get taller by heightScale while the base only widens by baseScale, so they read taller and pointier; `aspect` = height / base diameter
        for k in 0..<nSp {
            let sK = L * (0.05 + 0.87 * Float(k) / Float(nSp - 1))
            var i = 1; while i < arc.count - 1 && (aArc[i] < sK || blocked[i]) { i += 1 }
            // restyle: the ridge path doubles back where the swelled back meets the tail, so equal ARC spacing can bunch two spikes together in 3D; step on along the path until
            // each spike stands at least `restyledMinChord` (straight-line) from the one before it, so the row reads evenly spaced in every view
            if PipTailVariant.active != .current, let prev = sps.last {
                while i < arc.count - 1 && (simd_distance(path[i].shown, prev.pt.shown) < rowMinChord || blocked[i]) { i += 1 }
            }
            let pt = path[i]
            let tgRaw = simd_normalize(path[min(i + 1, path.count - 1)].shown - path[max(i - 1, 0)].shown)
            let n = pt.n
            let tgP = simd_normalize(tgRaw - n * simd_dot(tgRaw, n))
            // size: largest at the junction, smaller up the back and toward the tip
            let f: Float = sK <= sJ ? 1 - 0.40 * (sJ - sK) / max(sJ, 1e-3) : 1 - 0.50 * (sK - sJ) / max(L - sJ, 1e-3)
            var H = 0.15 * f
            if pt.isTail { H = min(H, max(0.08, 0.7 * Float(sh.ridge(pt.t).r))) }
            if PipTailVariant.active != .current { H = PipSpikes.restyledBaseHeight * heightScale * PipSpikes.restyledGrade[min(k, PipSpikes.restyledGrade.count - 1)] * reflowSize }          // explicit graded heights
            sps.append(Sp(sK: sK, pt: pt, n: n, tg: tgP, H: H, asp: aspect, lean: pt.isTail ? 0.21 : 0.45))
        }
        // pass 2: no two neighbours may touch in ANY view: their bases must be at least 1.5 base-diameters apart (a gap of 0.5x the larger diameter) and their whole
        // cones (axis segments, measured where they actually stand on the shown / swelled surface) at least their summed radii apart; the larger one shrinks until they clear
        func segDist(_ p1: SIMD3<Float>, _ q1: SIMD3<Float>, _ p2: SIMD3<Float>, _ q2: SIMD3<Float>) -> Float {
            var best = Float.infinity
            for a in 0...8 { let u = Float(a) / 8; let c = p1 + (q1 - p1) * u
                let d = q2 - p2, t = max(0, min(1, simd_dot(c - p2, d) / max(simd_dot(d, d), 1e-9)))
                best = min(best, simd_distance(c, p2 + d * t)) }
            return best
        }
        func place() { for k in 0..<sps.count { let bR = sps[k].bw / 2; sps[k].baseShown = sps[k].pt.shown - sps[k].n * (0.3 * bR)
            sps[k].ax = simd_normalize(sps[k].n * cosf(sps[k].lean) + sps[k].tg * sinf(sps[k].lean)) } }
        for _ in 0..<30 {
            place()
            var changed = false
            for k in 1..<sps.count {
                let a = sps[k - 1], b = sps[k]
                let diam = max(a.bw, b.bw)                                         // base diameter (= height for the current spikes)
                let chord = simd_distance(a.baseShown, b.baseShown)
                let sd = segDist(a.baseShown, a.baseShown + a.ax * a.H, b.baseShown, b.baseShown + b.ax * b.H)
                func flat(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(v.x, 0, v.z) }
                let sdTop = segDist(flat(a.baseShown), flat(a.baseShown + a.ax * a.H), flat(b.baseShown), flat(b.baseShown + b.ax * b.H))          // seen from above
                let hard = chord < 1.5 * diam || sd < 0.6 * (a.bw + b.bw) / 2
                let topOnly = PipTailVariant.active == .current && !hard && sdTop < 0.4 * (a.bw + b.bw) / 2 && max(a.bw, b.bw) > 0.095          // (the from-above rule never shrinks a spike below 0.095: they stay readable)
                if hard || topOnly {
                    if a.H >= b.H { sps[k - 1].H *= 0.93 } else { sps[k].H *= 0.93 }
                    changed = true
                } else if max(a.H, b.H) > (PipTailVariant.active == .current ? 1.35 : 1.45) * min(a.H, b.H) {                // keep the grading smooth: neighbours differ by at most 35 %
                    if a.H > b.H { sps[k - 1].H *= 0.96 } else { sps[k].H *= 0.96 }
                    changed = true
                }
            }
            if !changed { break }
        }
        var minChord = Float.infinity, minSeg = Float.infinity
        lastClearance = .infinity
        for k in 0..<sps.count {
            let sp = sps[k]
            let H = sp.H, bR = sp.bw / 2.0, pt = sp.pt, tgP = sp.tg, n = sp.n, sK = sp.sK
            let ax = simd_normalize(n * cosf(sp.lean) + tgP * sinf(sp.lean))
            let base = pt.rest - n * (0.3 * bR)
            if !obstacles.isEmpty { lastClearance = min(lastClearance, coneHits(base: base, ax: ax, H: H, bR: bR, tipSoft: vr.spikeTipSoft)) }
            if k > 0 { minChord = min(minChord, simd_distance(sps[k].baseShown, sps[k - 1].baseShown) / max(sps[k].bw, sps[k - 1].bw)) }
            let start = m.pos.count
            m.cone(base: base, axis: ax, height: H, baseR: bR, bend: tgP, curve: 0.06, tipSoft: vr.spikeTipSoft, lateral: SIMD3(1, 0, 0), tones: tn)
            widths.append(2 * bR); centres.append(sK)
            if pt.isTail {
                let ring = max(1, min(TailBean.bodyRings, Int((pt.t / sh.length * Double(TailBean.bodyRings)).rounded())))
                let rc = sh.point(sh.length * Double(ring) / Double(TailBean.bodyRings)), ru = sh.frame(sh.length * Double(ring) / Double(TailBean.bodyRings)).up
                var bestJ = 0, bestD = -Double.infinity
                for j in 0..<TailBean.around { let q = TailBean.local.pos[1 + TailBean.around * (ring - 1) + j] - rc; let d = simd_dot(q, ru); if d > bestD { bestD = d; bestJ = j } }
                let local = 1 + TailBean.around * (ring - 1) + bestJ
                tailSpikes.append(("tail\(k)", start, m.pos.count - start, base, local, f3(TailBean.local.pos[local])))
            } else {
                parts.append(("spike\(k)", start, m.pos.count - start, base))
            }
        }
        debug += " spikes=" + sps.map { String(format: "[sK=%.3f tail=%d t=%.2f H=%.3f bw=%.3f rest=(%.2f,%.2f,%.2f) shown=(%.2f,%.2f,%.2f)]", $0.sK, $0.pt.isTail ? 1 : 0, $0.pt.t, $0.H, $0.bw, $0.pt.rest.x, $0.pt.rest.y, $0.pt.rest.z, $0.pt.shown.x, $0.pt.shown.y, $0.pt.shown.z) }.joined(separator: " ")
        debug += String(format: " heights=%@ minChordOverDiam=%.2f", sps.map { String(format: "%.3f", $0.H) }.joined(separator: ","), minChord)
        _ = minSeg
        var arcS: Float = 0
        _ = arcS; arcS = 0
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
