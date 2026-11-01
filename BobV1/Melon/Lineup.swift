//
//  Lineup.swift
//  Smart line-ups (2026-11-01: "just line up for what's best in the line ... the first goes to the middle and the others come in from the side").
//  Nobody has a fixed spot. Whoever is nearest the middle slot takes it, the others take the free slot on the side they come from, chosen so that the walks do not
//  cross each other and do not run through a standing Jelbie or another one's slot. Re-read a few times a second until each commits (is within `commitDistance`).
//  Pure planning: the walkers steer round each other by themselves (BlobBrain+Contact.swift).
//

import Foundation
import simd

enum Lineup {
    static let commitDistance: Float = 1.0
    static let period: Float = 0.25
    /// A new plan must be at least this much better (u of walking) than the one in force, or nobody changes his mind.
    static let hysteresis: Float = 0.4

    private static func segDist(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a, l2 = simd_dot(ab, ab)
        let t = l2 > 1e-6 ? min(max(simd_dot(p - a, ab) / l2, 0), 1) : 0
        return simd_distance(p, a + ab * t)
    }
    private static func crosses(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, _ d: SIMD2<Float>) -> Bool {
        func o(_ p: SIMD2<Float>, _ q: SIMD2<Float>, _ r: SIMD2<Float>) -> Float { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        return o(a, b, c) * o(a, b, d) < 0 && o(c, d, a) * o(c, d, b) < 0
    }

    /// The cost of a plan: `slotOf[i]` is the slot walker i goes to. Walking length, plus a penalty per pair of walks that cross, plus one for a walk that passes close to
    /// another Jelbie (where he stands now or where he is going) or a bystander, plus extra weight on the middle slot's walk so the nearest takes it.
    static func cost(from: [SIMD2<Float>], slots: [SIMD2<Float>], slotOf: [Int], centre: Int?, bystanders: [SIMD2<Float>]) -> Float {
        var c: Float = 0
        let n = from.count
        for i in 0..<n {
            let to = slots[slotOf[i]]
            let len = simd_distance(from[i], to)
            c += len * (slotOf[i] == centre ? 1.6 : 1.0)
            for j in 0..<n where j != i {
                for q in [from[j], slots[slotOf[j]]] {
                    let d = segDist(q, from[i], to)
                    if d < 0.8 && simd_distance(q, to) > 0.05 { c += 2.5 * (1 - d / 0.8) }
                }
                if j > i, crosses(from[i], to, from[j], slots[slotOf[j]]) { c += 4 }
            }
            for q in bystanders { let d = segDist(q, from[i], to); if d < 0.8 { c += 2.5 * (1 - d / 0.8) } }
        }
        return c
    }

    /// All ways of giving `walkers` (indices) the `free` slots; the cheapest. `locked[i]` = slot already his for good.
    static func best(from: [SIMD2<Float>], slots: [SIMD2<Float>], locked: [Int?], centre: Int?, bystanders: [SIMD2<Float>] = [], current: [Int]? = nil) -> [Int] {
        let n = from.count
        var out = [Int](repeating: -1, count: n)
        var taken = Set<Int>()
        for i in 0..<n { if let s = locked[i] { out[i] = s; taken.insert(s) } }
        let walkers = (0..<n).filter { locked[$0] == nil }
        let free = slots.indices.filter { !taken.contains($0) }
        guard !walkers.isEmpty else { return out }
        var bestPlan = out, bestCost = Float.infinity
        func rec(_ k: Int, _ used: Set<Int>, _ plan: [Int]) {
            if k == walkers.count {
                let c = cost(from: from, slots: slots, slotOf: plan, centre: centre, bystanders: bystanders)
                if c < bestCost { bestCost = c; bestPlan = plan }
                return
            }
            for s in free where !used.contains(s) {
                var p = plan; p[walkers[k]] = s
                rec(k + 1, used.union([s]), p)
            }
        }
        rec(0, [], out)
        if let cur = current, cur.count == n, !cur.contains(-1), Set(cur.enumerated().filter { locked[$0.offset] == nil }.map(\.element)).isSubset(of: Set(free)) {
            var merged = cur; for i in 0..<n { if let s = locked[i] { merged[i] = s } }
            if cost(from: from, slots: slots, slotOf: merged, centre: centre, bystanders: bystanders) - bestCost < hysteresis { return merged }
        }
        return bestPlan
    }
}
