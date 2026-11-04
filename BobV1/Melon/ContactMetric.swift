//
//  ContactMetric.swift
//  The ground truth for "do two Jelbies touch, and by how much" (2026-11-02, g-contactcat). A Jelbie is a soft body whose DRAWN surface (the skinned render mesh: the body, the arms, Teddy's ears, Pip's tail)
//  is what the player sees, so a contact rule must be judged on that surface, not on roots or fitted eggs. This file is a small protocol plus a TEMPORARY brute-force implementation:
//  slow (every skinned vertex, every call) and meant for tests. The engine's fast version (`ContactProfile.skinGap`, a per-body radial skin-extent profile computed in the skin pass)
//  is checked against it (BobV1Tests/ContactPolishTests.swift).
//
//  skinGap(a, b) = (root distance) - (touch distance), in metres (1 u = 1 m):
//      +0.01  the surfaces are 1 cm apart,   0  they just touch,   negative  they overlap.
//  The touch distance is read along the line between the two roots, in the horizontal plane: how far each skin reaches from its own root toward the other (the support of its
//  vertices along that line, over the height both bodies share). The sum of the two reaches is the root distance at which the surfaces would just meet. It is signed (an overlap shows
//  as a negative gap, which a plain vertex-to-vertex distance cannot) and it does not depend on where the root sits inside a body.
//

import Foundation
import simd

/// One Jelbie's drawn surface in the world: its root on the floor (x, z) and the skinned vertices (world space).
nonisolated struct ContactSurface {
    var root: SIMD2<Float>
    var points: [SIMD3<Float>]

    init(root: SIMD2<Float>, points: [SIMD3<Float>]) { self.root = root; self.points = points }

    /// From a skinned vertex buffer (6 floats per vertex: position, normal), the vertices in `ranges` (the body, then the limb blocks that are drawn).
    init(root: SIMD2<Float>, dyn: UnsafePointer<Float>, ranges: [Range<Int>]) {
        self.root = root
        var pts: [SIMD3<Float>] = []
        for r in ranges { pts.reserveCapacity(pts.count + r.count); for v in r { pts.append(SIMD3(dyn[6 * v], dyn[6 * v + 1], dyn[6 * v + 2])) } }
        points = pts
    }
}

nonisolated protocol ContactMetric {
    /// Root distance minus touch distance of the two surfaces (metres): positive = apart, 0 = touching, negative = overlapping. `ContactMetric.farApart` when they share no height.
    static func skinGap(_ a: ContactSurface, _ b: ContactSurface) -> Float
}

extension ContactMetric {
    /// What `skinGap` returns for two bodies that share no height (one is wholly above the other): nothing to touch.
    static var farApart: Float { 9 }
}

/// TEMPORARY ground truth: brute force over every vertex (no profile, no cache).
nonisolated enum BruteForceContactMetric: ContactMetric {
    /// The height both surfaces share (nil = none).
    static func sharedBand(_ a: ContactSurface, _ b: ContactSurface) -> ClosedRange<Float>? {
        guard let aLo = a.points.map(\.y).min(), let aHi = a.points.map(\.y).max(), let bLo = b.points.map(\.y).min(), let bHi = b.points.map(\.y).max() else { return nil }
        let lo = max(aLo, bLo), hi = min(aHi, bHi)
        return lo <= hi ? lo...hi : nil
    }

    /// How far `s` reaches from its root along the horizontal unit vector `u`, over the heights in `band`.
    static func reach(_ s: ContactSurface, along u: SIMD2<Float>, band: ClosedRange<Float>) -> Float {
        var m = -Float.infinity
        for p in s.points where band.contains(p.y) { m = max(m, (p.x - s.root.x) * u.x + (p.z - s.root.y) * u.y) }
        return m
    }

    static func skinGap(_ a: ContactSurface, _ b: ContactSurface) -> Float {
        guard let band = sharedBand(a, b) else { return farApart }
        let d = b.root - a.root
        let dist = simd_length(d)
        let u = dist > 1e-4 ? d / dist : SIMD2<Float>(1, 0)
        let ra = reach(a, along: u, band: band), rb = reach(b, along: -u, band: band)
        guard ra.isFinite, rb.isFinite else { return farApart }
        return dist - ra - rb
    }

    /// The FOOTPRINT gap: how far `b` could slide toward `a` along the root axis before any vertex of one meets the other's footprint (over the shared height): the vertices binned
    /// by their lateral offset (5 mm strips), per strip `b`'s nearest axial minus `a`'s farthest axial, the least over the strips both cover. >= `skinGap` (the supports can overlap
    /// where the footprints do not); this is the one the eye checks ("is there floor between them").
    static func footprintGap(_ a: ContactSurface, _ b: ContactSurface, strip: Float = 0.005) -> Float {
        guard let band = sharedBand(a, b) else { return farApart }
        let d = b.root - a.root, dist = simd_length(d)
        let u = dist > 1e-4 ? d / dist : SIMD2<Float>(1, 0), v = SIMD2(-u.y, u.x)
        var envA: [Int: Float] = [:], envB: [Int: Float] = [:]
        for p in a.points where band.contains(p.y) {
            let q = SIMD2(p.x, p.z) - a.root, w = Int((simd_dot(q, v) / strip).rounded(.down)), t = simd_dot(q, u)
            if t > envA[w] ?? -.infinity { envA[w] = t }
        }
        for p in b.points where band.contains(p.y) {
            let q = SIMD2(p.x, p.z) - a.root, w = Int((simd_dot(q, v) / strip).rounded(.down)), t = simd_dot(q, u)
            if t < envB[w] ?? .infinity { envB[w] = t }
        }
        var best = Float.infinity
        for (w, ta) in envA { if let tb = envB[w] { best = min(best, tb - ta) } }
        return best.isFinite ? best : farApart
    }

    /// The plain closest horizontal distance between any vertex of `a` and any vertex of `b` over their shared height (unsigned: an overlap still reads positive). A cross-check: where the
    /// surfaces are apart, it is >= `skinGap` (the vertices are samples of the surface, the support gap is the planes').
    static func closestHorizontal(_ a: ContactSurface, _ b: ContactSurface) -> Float {
        guard let band = sharedBand(a, b) else { return farApart }
        let pa = a.points.filter { band.contains($0.y) }, pb = b.points.filter { band.contains($0.y) }
        var best = Float.infinity
        for p in pa { for q in pb { let dx = p.x - q.x, dz = p.z - q.z; best = min(best, dx * dx + dz * dz) } }
        return best.isFinite ? best.squareRoot() : farApart
    }
}
