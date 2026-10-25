//
//  WearCrownFit.swift
//  Head wear must NEVER let the head show through the crown. The rigid hat rides the body's rigid pose (centroid + rotation + squash), but the soft skin
//  moves on its own (hop stretch, breathing, landing wobble), and the authored crown only clears the rest head top by ~0.03, so the skin poked through.
//  Every frame a hat that ENCLOSES the head top (its crown covers the cap of the rest egg: `WearPrepared.crownEnclosing`) is fitted to the skin that is
//  actually drawn: the highest skin vertices of the head cap are mapped back into the hat's rest frame, compared with the crown's height map there, and the
//  hat is lifted or lowered (and widened a little) so its crown sits seated on them, the authored clearance above. Never moved for hats that only perch (ears,
//  bows, headphones, flower crowns: their `crownEnclosing` is false).
//

import simd
import Foundation

nonisolated enum CrownFit {
    /// Master switch (tests compare before / after).
    nonisolated(unsafe) static var enabled = true
    static let margin: Float = 0.022, minMargin: Float = 0.006, maxLift: Float = 0.35, maxDrop: Float = 0.16, maxWiden: Float = 1.14
    static let cell: Float = 0.04, origin: Float = -0.9, dim = 46
    /// How much of the lift a vertex takes, by its height above the hat's pivot (rest): the brim stays seated on the head, the crown stretches up.
    @inline(__always) static func liftWeight(_ yRel: Float) -> Float { min(1, max(0, (yRel + 0.25) / 0.28)) }
    /// How much of the rest head cap a hat's crown must cover to count as enclosing.
    static let enclosingShare: Float = 0.9

    /// The crown height map of a prepared piece (max y of its surface per xz cell, `-.infinity` = empty).
    static func heightMap(_ p: WearPrepared) -> [Float] {
        var g = [Float](repeating: -.infinity, count: dim * dim)
        func put(_ x: Float, _ z: Float, _ y: Float) {
            let ix = Int(((x - origin) / cell).rounded(.down)), iz = Int(((z - origin) / cell).rounded(.down))
            guard ix >= 0, iz >= 0, ix < dim, iz < dim else { return }
            if y > g[iz * dim + ix] { g[iz * dim + ix] = y }
        }
        var t = 0
        while t + 2 < p.idx.count {
            let a = p.rest[Int(p.idx[t])], b = p.rest[Int(p.idx[t + 1])], c = p.rest[Int(p.idx[t + 2])]
            let ext = max(simd_length(SIMD2(b.x - a.x, b.z - a.z)), simd_length(SIMD2(c.x - a.x, c.z - a.z)), simd_length(SIMD2(c.x - b.x, c.z - b.z)))
            let n = max(1, Int((ext / (cell * 0.5)).rounded(.up)))
            for i in 0...n { for j in 0...(n - i) {
                let u = Float(i) / Float(n), v = Float(j) / Float(n), w = 1 - u - v
                let q = a * w + b * u + c * v
                put(q.x, q.z, q.y)
            } }
            t += 3
        }
        return g
    }
    /// The crown top above (x, z): the cell's height, nil outside the piece.
    static func height(_ g: [Float], _ x: Float, _ z: Float) -> Float? {
        let ix = Int(((x - origin) / cell).rounded(.down)), iz = Int(((z - origin) / cell).rounded(.down))
        guard ix >= 0, iz >= 0, ix < dim, iz < dim else { return nil }
        let h = g[iz * dim + ix]
        return h.isFinite ? h : nil
    }

    /// Sets `p.crown` / `p.crownEnclosing` (head wear only).
    static func prepare(_ p: WearPrepared, body: WearBody) {
        guard p.look.slot == .head else { return }
        let g = heightMap(p)
        var covered = 0
        var slack = Float.infinity
        for i in body.capIndices {
            let r = body.pos[i]
            if let h = height(g, r.x, r.z), h >= r.y { covered += 1; slack = min(slack, h - r.y) }
        }
        p.crownMargin = slack.isFinite ? max(minMargin, min(margin, slack)) : margin       // the authored clearance at rest (never more than `margin`)
        p.crown = g
        p.crownEnclosing = !body.capIndices.isEmpty && Float(covered) / Float(body.capIndices.count) >= enclosingShare
    }

    /// The lift (rest frame, y) and widening (about the body axis) that keep the crown over the drawn skin. (0, 1) when nothing pokes.
    static func fit(_ p: WearPrepared, carry c: EyeMaskModel.Carry, skin: UnsafePointer<Float>, body: WearBody) -> (dy: Float, widen: Float) {
        guard enabled, p.crownEnclosing, !p.crown.isEmpty else { return (0, 1) }
        let Rt = simd_float3x3(c.rotation).transpose
        let sxz = 1 / c.squash.squareRoot()
        let rc = c.restCentroid
        var dy: Float = -maxDrop, widen: Float = 1, any = false
        for i in body.capIndices {
            let o = 6 * i
            let q = SIMD3(skin[o], skin[o + 1], skin[o + 2]) - c.centroid
            let l = Rt * q
            let r = rc + SIMD3(l.x / sxz, l.y / c.squash, l.z / sxz)         // the skin vertex in the rest frame
            if !(r.x.isFinite && r.y.isFinite && r.z.isFinite) { continue }
            let rest = body.pos[i]
            let rr = simd_length(SIMD2(rest.x - rc.x, rest.z - rc.z))
            if rr > 0.25 { widen = max(widen, simd_length(SIMD2(r.x - rc.x, r.z - rc.z)) / rr) }
        }
        widen = min(maxWiden, widen)
        for i in body.capIndices {
            let o = 6 * i
            let q = SIMD3(skin[o], skin[o + 1], skin[o + 2]) - c.centroid
            let l = Rt * q
            let r = rc + SIMD3(l.x / sxz, l.y / c.squash, l.z / sxz)
            if !(r.x.isFinite && r.y.isFinite && r.z.isFinite) { continue }
            // the crown, widened, is at (x, z) what the authored crown is at (x, z) / widen
            guard let h = height(p.crown, rc.x + (r.x - rc.x) / widen, rc.z + (r.z - rc.z) / widen) else { continue }
            let need = r.y + p.crownMargin - h
            dy = max(dy, need / max(liftWeight(h - p.pivot.y), 0.2)); any = true
        }
        return any ? (min(maxLift, max(-maxDrop, dy)), widen) : (0, widen)
    }
}
