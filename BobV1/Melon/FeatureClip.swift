//
//  FeatureClip.swift
//  A feature (Lavender / Pearl's wings, Pip's spikes + tail, Moss's daisy) or a limb (the arms, Teddy's ears + pom, the tail) that would be DRAWN inside ANOTHER Jelbie's
//  body is pushed out to that body's surface (2026-11-02, the user's phone photo: Pearl's wing sunk in Teddy, Teddy's arm in Pearl).
//
//  Why a push-out and not a fold: a wing at rest is already as folded as it gets (flap 0 / spread 0), so folding changes nothing for the overlap; only the vertices
//  that are inside the other body move, along that body's egg gradient, by the depth (+ a 4 mm skin). It deforms the FEATURE only, never a body (the body-vs-body
//  particle push was tried and rejected: pressed bodies looked deformed), so the contact squish / boop / sounds are untouched. It is a continuous map of the depth
//  (zero at 4 mm outside the egg, no pop), and fades out for a vertex that is inside its OWN body (the join of a limb with its owner stays put).
//  Cost: one bounding-sphere test per vertex per other body; the egg SDF only for the vertices inside a neighbour's sphere (none when the Jelbies stand apart).
//  It runs on the main thread after the parallel skin pass (the stage) and inside FeatureSet.frame, from one table of the bodies drawn this frame (`eggs`).
//

import Foundation
import simd

/// One body's fitted egg in the world this frame: the rigid pose (centroid, rotation) with the squash, as the wardrobe / features carry points.
nonisolated struct ClipEgg {
    var centroid: SIMD3<Float>
    var restCentroid: SIMD3<Float>
    var minv: simd_float3x3          // world offset from the centroid -> rest offset from the rest centroid
    var radius: Float                // a sphere round the centroid that holds the whole egg

    static let restRadius: Float = {
        var r = 0.0
        for k in 0...24 {
            let t = Double(k) / 24
            r = max(r, BobForm.halfWidth(t: t), BobForm.halfDepth(t: t))
        }
        return Float(max(r, BobForm.top * 0.5)) + 0.05
    }()

    init(centroid: SIMD3<Float>, rotation: simd_quatf, squash: Float, restCentroid: SIMD3<Float>) {
        self.centroid = centroid; self.restCentroid = restCentroid
        let sq = max(0.3, min(2, squash)), sxz = 1 / sq.squareRoot()
        minv = simd_float3x3(diagonal: SIMD3(1 / sxz, 1 / sq, 1 / sxz)) * simd_float3x3(rotation).transpose
        // the tallest rest reach (head or belly from the rest centroid) and the widest, stretched by the largest axis of the squash
        let reach = max(Float(BobForm.top) - restCentroid.y, restCentroid.y - Float(BobForm.lift))
        radius = max(reach, Self.restRadius) * max(sxz, 1 / sq, 1) + 0.03
    }

    init(sim: SoftBody) {
        let p = sim.bodyPose(iterations: 3)
        self.init(centroid: p.centroid, rotation: p.rotation, squash: sim.attractor.squash, restCentroid: sim.restCentroid)
    }

    /// Rest-space point of the world point `p`.
    @inline(__always) func rest(_ p: SIMD3<Float>) -> SIMD3<Float> { restCentroid + minv * (p - centroid) }

    /// The egg's box in rest space (a hair wider): outside it a point is not in the egg, no SDF needed.
    static let restHalf: Float = Float(max(BobForm.halfW, BobForm.halfD)) + 0.02
    static let restLo: Float = Float(BobForm.lift) - 0.02, restHi: Float = Float(BobForm.top) + 0.02

    /// Depth (+ inside, rest units) of the world point `p` in the egg; -1 when it is outside the egg's rest box.
    @inline(__always) func depth(_ p: SIMD3<Float>) -> Float {
        let q = rest(p)
        if abs(q.x) > Self.restHalf || abs(q.z) > Self.restHalf || q.y < Self.restLo || q.y > Self.restHi { return -1 }
        return -Float(BobForm.bodySDF(SIMD3<Double>(Double(abs(q.x)), Double(q.y), Double(q.z))))
    }

    /// World point `p` (inside the egg by `d`) moved out to `margin` outside the surface.
    func pushedOut(_ p: SIMD3<Float>, depth d: Float, margin: Float) -> SIMD3<Float> {
        var p = p
        var d = d
        for _ in 0..<3 {
            let q = rest(p)
            let sx: Float = q.x < 0 ? -1 : 1
            let qd = SIMD3<Double>(Double(abs(q.x)), Double(q.y), Double(q.z))
            let f0 = -Double(d), e = 0.004          // (forward differences from the depth in hand: 3 SDF evaluations, not 6; the loop re-measures the depth anyway)
            let g = SIMD3(BobForm.bodySDF(qd + SIMD3(e, 0, 0)) - f0, BobForm.bodySDF(qd + SIMD3(0, e, 0)) - f0, BobForm.bodySDF(qd + SIMD3(0, 0, e)) - f0)
            let gl = Float(simd_length(g))
            guard gl > 1e-9 else { return p }
            let gr = SIMD3<Float>(sx * Float(g.x), Float(g.y), Float(g.z)) / gl          // outward, rest space
            let nw = simd_normalize(minv.transpose * gr)                                  // outward, world (a normal transforms by the inverse transpose)
            let per = max(0.25, simd_dot(minv * nw, gr))                                  // rest distance covered per unit of world distance along nw
            p += nw * ((d + margin) / per)
            d = depth(p)
            if d < -margin * 0.5 { break }
        }
        return p
    }
}

nonisolated enum FeatureClip {
    /// false = off (the captures' "before" / the soak's comparison).
    nonisolated(unsafe) static var enabled = true
    /// The bodies drawn this frame, by body id (nil = not drawn / not skinned). Set by the stage after the skin pass.
    nonisolated(unsafe) static var eggs: [ClipEgg?] = []
    static let margin: Float = 0.004
    /// A point inside its OWN egg by more than `ownIn` is left alone (the join with its owner), fully clipped from `ownOut` outside it.
    static let ownIn: Float = 0.01, ownOut: Float = 0.01

    /// Clip the world point `p` of body `own` against every other drawn body. Returns the deepest penetration before the push (0 = none).
    @inline(__always) static func clip(_ p: inout SIMD3<Float>, own: Int, eggs: [ClipEgg?]) -> Float {
        var worst: Float = 0
        for (j, e) in eggs.enumerated() where j != own {
            guard let e else { continue }
            let d0 = p - e.centroid
            if simd_dot(d0, d0) > e.radius * e.radius { continue }
            let d = e.depth(p)
            guard d > -margin else { continue }
            var w: Float = 1
            if own >= 0, own < eggs.count, let mine = eggs[own] {
                let o = mine.depth(p)          // + inside its own body
                w = max(0, min(1, (ownIn - o) / (ownIn + ownOut)))
                if w <= 0 { continue }
            }
            let target = e.pushedOut(p, depth: d, margin: margin)
            p += (target - p) * w
            worst = max(worst, d)
        }
        return worst
    }

    /// The feature vertices `range` of `m` (world space) of body `own`.
    static func clip(_ m: inout RoomMesh, range: Range<Int>, own: Int) {
        guard enabled, eggs.count > 1 else { return }
        let eg = eggs
        for i in range {
            var p = SIMD3(m.vertices[i].pos.x, m.vertices[i].pos.y, m.vertices[i].pos.z)
            if clip(&p, own: own, eggs: eg) > 0 { m.vertices[i].pos = SIMD4(p, m.vertices[i].pos.w) }
        }
    }

    /// The body-attached blocks of the skinned streams (the arms, the tail, Teddy's ears + pom): after the parallel skin pass, on the main thread.
    static func apply(jobs: [JellyParallel.SkinJob]) {
        guard enabled, jobs.count > 1 else { eggs = []; return }
        var table = [ClipEgg?](repeating: nil, count: (jobs.map(\.id).max() ?? 0) + 1)
        for j in jobs { table[j.id] = ClipEgg(sim: j.sim) }
        eggs = table
        for j in jobs {
            let sk = j.skinner, dst = j.dst, own = j.id
            func block(_ first: Int, _ count: Int) {
                guard first >= 0, count > 0 else { return }
                for v in first..<(first + count) {
                    let o = 6 * v
                    var p = SIMD3(dst[o], dst[o + 1], dst[o + 2])
                    if clip(&p, own: own, eggs: table) > 0 { dst[o] = p.x; dst[o + 1] = p.y; dst[o + 2] = p.z }
                }
            }
            if sk.armCapsulesActive { for s in 0..<2 { block(sk.armFirst[s], ArmCapsule.vertexCount) } }
            if sk.tailOn { block(sk.tailFirst, TailBean.vertexCount) }
            if sk.teddyOn { block(sk.teddyFirst, TeddyBean.vertexCount) }
        }
    }
}
