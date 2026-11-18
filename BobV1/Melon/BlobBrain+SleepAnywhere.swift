//
//  BlobBrain+SleepAnywhere.swift
//  Sleep anywhere (owner 2026-11-17, "I keep saying this": "they don't have to lineup, they can sleep where ever they don't have to be close ... they get buggy and run into
//  each other when trying to line up"). At bedtime (any path: the natural night, Goodnight / Bedtime, a nap, the away arrival, the guest's sleepover) each Jelmiko lies
//  down where he is standing. Only when that spot is not a fair place to lie does he walk, to the NEAREST fair spot (a short walk, under about 1 u). There is no pull
//  toward the others, the rug or a row. `SleepTuning.anywhere` (dev `-SleepAnywhere 0`) = the old row / rug pile.
//
//  A spot is fair when: he can stand there and the whole lying body is on screen; it is clear of the bowls, the call spot, the door, the table, the tray and meal places,
//  the decor and the balls; and the lying body (the footprint ellipse, which holds the flop and the slow toss-and-turn) keeps `anywhereGap` clear of every other sleeper's
//  reserved spot and of every other body that is staying up.
//
//  Who yields: brains pick one after another in the same moment. A body that is also bound for bed (`commandedGoodnight` / `sleepBound`) and has not picked yet is left out
//  of the first one's search (he stays where he is); the first one's reserved spot is then an obstacle for the later ones, so exactly the later caller moves, never both.
//

import Foundation
import simd

extension BlobBrain {
    /// Is `o` going to bed too but has not chosen yet (it will yield to whoever has)?
    private func bedBoundNotDown(_ o: BlobBrain) -> Bool { o.idleState.kind != .sleep && (o.commandedGoodnight || o.sleepBound) }

    /// A fair place to lie down at `p` (see the file header).
    /// `strict`: a mover's candidate also keeps clear of the bodies that are bound for bed and will yield (they are still standing where they are).
    func sleepFairAnywhere(_ p: SIMD2<Float>, strict: Bool = false) -> Bool {
        let T = SleepTuning.self, L = RoomLayout.self
        guard simd_distance(fixed(p), p) < 0.08 else { return false }
        // the lying body, not just the standing one, stays on the visible floor and off the sofa / table
        let big = GameCamera.constrain(SIMD3(p.x, 0, p.y), radius: T.footHalfLen)
        guard simd_distance(SIMD2(big.x, big.z), p) < 0.06 else { return false }
        for s in [GameCamera.foodBowlSpot, GameCamera.waterBowlSpot] where simd_distance(p, s) < 0.7 { return false }
        if simd_distance(p, GameCamera.callSpot) < 0.9 { return false }
        if simd_distance(p, GuestTuning.door) < 0.9 { return false }
        if simd_distance(p, L.table.centre) < 1.2 { return false }
        for b in L.dynamicBoxes where L.boxDistanceXZ(p, b) < 0.8 { return false }          // (the tray and the meal places in use)
        guard L.decorDistance(p, solidOnly: true) > T.decorClearRelaxed, L.decorDistance(p) > T.decorFlatClearRelaxed else { return false }
        for b in L.ballSpheres where simd_distance(p, b.c) < b.r + 0.5 { return false }
        let yaw = faceCameraYaw()
        for o in socialOthers() where o !== self {
            if o.idleState.kind == .sleep, o.sleep.stage <= 4 {
                if Self.lieClash(p - o.sleep.spot, yawA: yaw, yawB: o.sleep.lieYaw, margin: T.anywhereGap) || Self.lieClash(p - o.position, yawA: yaw, yawB: o.sleep.lieYaw, margin: T.anywhereGap) { return false }
            } else if strict || !bedBoundNotDown(o) {          // (a body that stays up: his standing skin must stay clear of my lying skin, with the same gap)
                if Self.lieClash(p - o.position, yawA: yaw, yawB: o.faceCameraYaw(), margin: T.anywhereGap) { return false }
            }
        }
        return true
    }

    /// The walk here -> p never goes through another body's lying footprint or a body standing there (unless he starts inside it: then he must only get farther away).
    private func sleepWalkClear(_ a: SIMD2<Float>, _ p: SIMD2<Float>) -> Bool {
        let d = p - a, n = max(2, Int(simd_length(d) / 0.1)), yaw = faceCameraYaw()
        for o in socialOthers() where o !== self {
            var spots: [SIMD2<Float>] = []
            if o.idleState.kind == .sleep, o.sleep.stage <= 4 { spots = [o.sleep.spot, o.position] } else { spots = [o.position] }
            for s in spots {
                let d0 = simd_distance(a, s), startsInside = Self.lieClash(a - s, yawA: yaw, yawB: o.faceCameraYaw(), margin: 0)
                for i in 1...n {
                    let q = a + d * (Float(i) / Float(n))
                    if Self.lieClash(q - s, yawA: yaw, yawB: o.faceCameraYaw(), margin: 0) {
                        if !startsInside || simd_distance(q, s) < d0 - 0.01 { return false }
                    }
                }
            }
        }
        return true
    }

    /// Where he lies down under the sleep-anywhere rule: here when it is fair, else the nearest fair spot (rings of growing radius, the side away from the closest body first), by a clear leg.
    /// nil = no fair spot within `anywhereFarReach` that he can walk to (the old search is the last resort).
    func chooseSleepSpotAnywhere() -> (spot: SIMD2<Float>, yaw: Float, joined: Bool, partner: BlobBrain?)? {
        let T = SleepTuning.self, here = position, ly = faceCameraYaw()
        if sleepFairAnywhere(here) { return (here, ly, false, nil) }
        var base: Float = .pi / 2          // (toward the camera when nobody is near)
        if let o = socialOthers().filter({ $0 !== self }).min(by: { simd_distance($0.position, here) < simd_distance($1.position, here) }) {
            let v = here - o.position
            if simd_length(v) > 0.02 { base = atan2f(v.y, v.x) }
        }
        var r: Float = 0.1
        while r <= T.anywhereFarReach + 1e-4 {
            let n = min(36, max(8, Int((2 * .pi * r) / 0.14)))
            for k in 0..<n {
                let step = Float((k + 1) / 2) * (2 * .pi / Float(n)) * (k % 2 == 1 ? 1 : -1)
                let a = base + step
                let p = here + SIMD2(cosf(a), sinf(a)) * r
                guard sleepFairAnywhere(p, strict: true), sleepWalkClear(here, p), reachable(here, p) else { continue }
                return (p, ly, false, nil)
            }
            r += r < T.anywhereReach - 1e-4 ? 0.1 : 0.2
        }
        return nil
    }
}
