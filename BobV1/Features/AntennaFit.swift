//
//  AntennaFit.swift
//  The hat rule of the green Jelmiko's two antennas (AntennaBean). OWNER'S RULE (2026-11-14): the antennas are NEVER tucked. They poke up THROUGH every hat and stay visible above it, wobbling as
//  usual; items that are not over the roots (bow, bandana, glasses, scarf, sleep mask ...) change nothing.
//    POKE-THROUGH  (lift 0): the hat's top over a root is no more than `freeRise` above the head surface there (beanie, cap, bucket hat, party hat's brim ...): the stalk simply comes out of the
//                  hat's surface (an opaque hat hides the part inside it: no hole, no ring, the two surfaces cross).
//    ROOT LIFT     : the hat is taller than that over the root (top hat, chef hat, witch / viking hat, cowboy crown ...): the whole antenna would be inside it, so the roots are raised along the
//                  antenna's own direction until they sit `freeRise` below the hat's surface there: the ball and the upper stalk stand on the hat (head fillet fades with the lift).
//  Open head pieces (bands, bows, clips, headphones, ears ...) never lift: the stalk passes beside / through them (the report lists the ones that cannot look right).
//

import simd
import Foundation

nonisolated enum AntennaFit {
    /// How much of the antenna (rest units, measured along its root direction) must stay out of the hat: a hat top lower than this over the root is poked through, a taller one lifts the roots.
    static let freeRise: Float = 0.16
    /// Horizontal reach (rest units) round a root within which the hat's top counts as "over the root", and the motion allowance (the crown follows the drawn skin: wider, higher).
    static let rootReach: Float = 0.09
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Float] = [:]
    static func clearCache() { lock.lock(); cache = [:]; lock.unlock() }

    /// The root of the right antenna on the head surface (rest space) and its direction.
    static var root: (p: SIMD3<Float>, dir: SIMD3<Float>) {
        let part = AntennaBean.parts[0]
        let c = part.centre[part.rootIndex], d = part.liftDir
        return (SIMD3(Float(c.x), Float(c.y), Float(c.z)), SIMD3(Float(d.x), Float(d.y), Float(d.z)))
    }

    /// How far the roots are raised under what is worn (`worn` = the shown art ids); 0 = poke through.
    static func lift(worn: [String]) -> Float {
        let key = worn.sorted().joined(separator: ",")
        lock.lock(); let c = cache[key]; lock.unlock()
        if let c { return c }
        var best: Float = 0
        let body = WearBody.shared
        let (rp, dir) = root
        for w in worn {
            guard let look = WearLook.pieces.first(where: { $0.art == w }), look.slot == .head, let piece = WearMeshes.prepare(look, body: body), piece.crownEnclosing else { continue }
            let cloud = TeddyFit.surfacePoints(piece)
            var top: Float = -.infinity
            for q0 in cloud {
                for (k, dy) in [(Float(1), TeddyFit.motionLift), (TeddyFit.motionWiden, Float(0)), (TeddyFit.motionWiden, TeddyFit.motionLift)] {
                    let q = SIMD3(q0.x * k, q0.y + dy, q0.z * k)
                    if abs(q.x - rp.x) < rootReach && abs(q.z - rp.z) < rootReach && q.y > rp.y { top = max(top, q.y) }
                }
            }
            guard top.isFinite else { continue }
            // distance along the antenna's direction from its root to the hat's top over it
            let rise = (top - rp.y) / max(dir.y, 0.5)
            best = max(best, rise - freeRise)
        }
        best = max(best, 0)
        lock.lock(); cache[key] = best; lock.unlock()
        return best
    }
}
