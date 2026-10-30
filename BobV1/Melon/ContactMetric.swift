//
//  ContactMetric.swift
//  How far two DRAWN Jelbies pass into each other, measured on the skinned vertex streams (6 floats per vertex: position, normal), never on the sim:
//    depth      the deepest point of one body inside the other (world units): the nearest-surface distance of the deepest vertex that lies inside the other body
//    tail       how far a body's skin reaches into Pip's drawn tail tube (ring centres + radii of the tail block)
//  Used by the touch tests and the `-SocialDemo` capture aid (MelonStage+SocialDemo.swift); no cost in the game itself.
//

import Foundation
import simd

nonisolated enum ContactMetric {
    private static let azBins = 32, elBins = 16

    private static func centre(_ s: UnsafePointer<Float>, _ r: Range<Int>, skip: Range<Int>) -> SIMD3<Float> {
        var c = SIMD3<Float>.zero, n: Float = 0
        for v in r where !skip.contains(v) { c += SIMD3(s[6 * v], s[6 * v + 1], s[6 * v + 2]); n += 1 }
        return n > 0 ? c / n : c
    }

    /// Deepest penetration of `a`'s vertices into `b` (a star-shaped radial map about b's centre decides "inside"; the depth is the distance to b's nearest vertex).
    /// `skip` = the vertices left out of both bodies (the tail block).
    static func depth(of a: UnsafePointer<Float>, into b: UnsafePointer<Float>, vertices n: Int, skip: Range<Int> = 0..<0) -> Float {
        let cb = centre(b, 0..<n, skip: skip)
        var radial = [Float](repeating: 0, count: azBins * elBins)
        func bin(_ d: SIMD3<Float>) -> Int {
            let L = simd_length(d)
            let az = atan2f(d.x, d.z), el = asinf(max(-1, min(1, d.y / max(L, 1e-6))))
            let i = min(azBins - 1, Int((az + .pi) / (2 * .pi) * Float(azBins))), j = min(elBins - 1, Int((el + .pi / 2) / .pi * Float(elBins)))
            return j * azBins + i
        }
        for v in 0..<n where !skip.contains(v) {
            let d = SIMD3(b[6 * v], b[6 * v + 1], b[6 * v + 2]) - cb
            let k = bin(d); radial[k] = max(radial[k], simd_length(d))
        }
        var deepest: Float = 0
        for v in stride(from: 0, to: n, by: 3) where !skip.contains(v) {
            let p = SIMD3(a[6 * v], a[6 * v + 1], a[6 * v + 2]), d = p - cb
            let r = simd_length(d)
            guard r < radial[bin(d)] - 0.004 else { continue }
            var best = Float.infinity
            for w in stride(from: 0, to: n, by: 2) where !skip.contains(w) {
                let q = SIMD3(b[6 * w], b[6 * w + 1], b[6 * w + 2]) - p
                best = min(best, simd_length_squared(q))
            }
            deepest = max(deepest, best.squareRoot())
        }
        return deepest
    }

    /// The deeper of the two directions.
    static func mutualDepth(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, vertices n: Int, skip: Range<Int> = 0..<0) -> Float {
        max(depth(of: a, into: b, vertices: n, skip: skip), depth(of: b, into: a, vertices: n, skip: skip))
    }

    /// Ring centres + mean radii of the tail block starting at vertex `first` (the tube's spheres), every `every`th ring.
    static func tailRings(_ s: UnsafePointer<Float>, first f: Int, every: Int = 2) -> [SIMD4<Float>] {
        var out: [SIMD4<Float>] = []
        let a = TailBean.around
        for r in stride(from: 10, to: TailBean.rings, by: every) {          // (from the first visible ring: the buried root is inside his own body)
            var c = SIMD3<Float>.zero
            for j in 0..<a { let v = f + 1 + a * r + j; c += SIMD3(s[6 * v], s[6 * v + 1], s[6 * v + 2]) }
            c /= Float(a)
            var rad: Float = 0
            for j in 0..<a { let v = f + 1 + a * r + j; rad += simd_distance(SIMD3(s[6 * v], s[6 * v + 1], s[6 * v + 2]), c) }
            out.append(SIMD4(c, rad / Float(a)))
        }
        return out
    }

    /// How far the body `other` reaches into the tail tube of `tail` (0 = clear).
    static func tailIntrusion(tail: UnsafePointer<Float>, first: Int, other: UnsafePointer<Float>, vertices n: Int, skip: Range<Int> = 0..<0) -> Float {
        let rings = tailRings(tail, first: first)
        var worst: Float = 0
        for v in stride(from: 0, to: n, by: 2) where !skip.contains(v) {
            let p = SIMD3(other[6 * v], other[6 * v + 1], other[6 * v + 2])
            for s in rings where s.w > 0.05 { worst = max(worst, s.w - simd_distance(p, SIMD3(s.x, s.y, s.z))) }
        }
        return worst
    }
}
