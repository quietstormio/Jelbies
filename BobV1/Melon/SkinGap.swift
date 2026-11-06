//
//  SkinGap.swift
//  The gap between two Jelbies' DRAWN skins (the skinned egg vertices + their normals, 6 floats a vertex), the thing the eye sees: + apart, - sunk into each other.
//  The fitted egg is not good enough for the lying snuggle (the soft body drawn lying is a few cm smaller than its rigid egg: 5 cm of floor between two "touching" bodies).
//  For each vertex of one skin near the other: its signed distance to the tangent plane of the nearest vertex of the other skin; the gap is the smallest, both ways.
//  Only the ~0.3 u cap of each skin that faces the other is looked at, so a measure is ~1 ms: it runs a handful of times per lie-down, never per frame.
//

import Foundation
import simd

nonisolated enum SkinGap {
    /// Two skinned streams (`limit` = vertex count of the egg proper, the arm / tail / ear blocks after it are not body).
    static func gap(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, limit: Int) -> Float {
        func centroid(_ s: UnsafePointer<Float>) -> SIMD3<Float> {
            var c = SIMD3<Float>.zero, n: Float = 0
            var i = 0
            while i < limit { c += SIMD3(s[6 * i], s[6 * i + 1], s[6 * i + 2]); n += 1; i += 7 }
            return c / max(n, 1)
        }
        let ca = centroid(a), cb = centroid(b)
        func facing(_ s: UnsafePointer<Float>, toward c: SIMD3<Float>) -> [Int] {
            var d2 = [Float](repeating: 0, count: limit)
            var lo = Float.infinity
            for i in 0..<limit {
                let p = SIMD3(s[6 * i], s[6 * i + 1], s[6 * i + 2]) - c
                let v = simd_dot(p, p); d2[i] = v; lo = min(lo, v)
            }
            let reach = (lo.squareRoot() + 0.3)
            let lim = reach * reach
            return (0..<limit).filter { d2[$0] < lim }
        }
        let fa = facing(a, toward: cb), fb = facing(b, toward: ca)
        func oneWay(_ s: UnsafePointer<Float>, _ si: [Int], _ t: UnsafePointer<Float>, _ ti: [Int]) -> Float {
            var worst = Float.infinity
            for i in si {
                let p = SIMD3(s[6 * i], s[6 * i + 1], s[6 * i + 2])
                var best = Float.infinity, bq = 0
                for j in ti {
                    let q = SIMD3(t[6 * j], t[6 * j + 1], t[6 * j + 2]) - p
                    let v = simd_dot(q, q)
                    if v < best { best = v; bq = j }
                }
                guard best.isFinite else { continue }
                let q = SIMD3(t[6 * bq], t[6 * bq + 1], t[6 * bq + 2]), n = SIMD3(t[6 * bq + 3], t[6 * bq + 4], t[6 * bq + 5])
                worst = min(worst, simd_dot(p - q, n))
            }
            return worst
        }
        return min(oneWay(a, fa, b, fb), oneWay(b, fb, a, fa))
    }
}
