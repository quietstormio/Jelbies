//
//  ParkClearSpot.swift
//  park-slide-r2: a floor target that other code picked (a zoomies run, a group hug's centre, a trot) can lie INSIDE a solid park piece (the slide above all: a Jelbie who has just ridden it keeps it
//  soft for himself until he is clear of it, `BlobBrain.decorIgnore`, and a pick made in that moment does not see it), and the walk to it then crosses the piece.
//  `ParkClearSpot.clear` returns the nearest clear point. A point that is already clear comes back EXACTLY unchanged, and outside the park (no park slide in the decor field) so does every point.
//  Keep-outs: every solid piece (slide, seesaw, bench, flower bed, pond: the room's own rule) and the hopscotch court's footprint (flat, so the floor rules let a body walk over it, but nobody
//  runs or gathers a hug in the middle of the game).
//

import simd

enum ParkClearSpot {
    /// The park is up when its slide stands in the decor field (the home room never has it).
    static var inPark: Bool { DecorField.shared.foot(ParkToys.slideUID) != nil }

    /// The hopscotch courts standing now (flat pieces the floor rules do not push off).
    static var courts: [DecorFoot] { DecorField.shared.feet.filter { $0.kind == .hopscotch } }

    /// The keep-outs the helper sees, for the tests' printout: "kind uid solid at centre".
    static func keepOuts() -> [String] {
        DecorField.shared.feet.filter { $0.spec.solid || $0.kind == .hopscotch }.map { "\($0.kind) uid \($0.uid) \($0.spec.solid ? "solid" : "flat keep-out") at \($0.centre)" }
    }

    /// A body of `radius` at `p` would be pushed off by a solid piece (the room's own rule, with NOTHING soft: `resolve` without an ignored piece), or stands on a hopscotch court.
    static func blocked(_ p: SIMD2<Float>, radius: Float) -> Bool {
        let q = RoomLayout.resolve(position: SIMD3(p.x, 0, p.y), radius: radius, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: nil)
        if simd_distance(SIMD2(q.x, q.z), p) > 1e-4 { return true }
        return courts.contains { $0.distance(p) < 0 }
    }

    /// How many roam-pick candidates were checked / rejected by `legCrossesSolid` (park only; the tests print them).
    nonisolated(unsafe) static var legChecks = 0, legRejects = 0
    /// Test switch for the "before" measurement (always true in the game).
    nonisolated(unsafe) static var legCheckEnabled = true
    /// The straight leg a-b (sampled every 0.1 m) passes through a keep-out of the park. Always false outside the park. (Not called by the walk code: offered for the wander pick.)
    static func legCrossesSolid(_ a: SIMD2<Float>, _ b: SIMD2<Float>, radius: Float) -> Bool {
        guard inPark, legCheckEnabled else { return false }
        legChecks += 1
        let n = max(1, Int(simd_distance(a, b) / 0.1))
        for i in 0...n where blocked(a + (b - a) * (Float(i) / Float(n)), radius: radius) { legRejects += 1; return true }
        return false
    }

    /// `p` itself when it is clear (and always at home); else the nearest clear point on the roam floor (`GameCamera.constrain`: the solids pushed out of, then the roam floor; a court: the nearest ring point clear of it).
    static func clear(_ p: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        guard inPark, blocked(p, radius: radius) else { return p }
        func floor(_ v: SIMD2<Float>) -> SIMD2<Float> {
            let q = GameCamera.constrain(SIMD3(v.x, 0, v.y), radius: radius, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: nil)
            return SIMD2(q.x, q.z)
        }
        let q = floor(p)
        if !blocked(q, radius: radius) { return q }
        // still blocked (on a court, or squeezed between two pieces): rings outward, the nearest clear floor point
        var r: Float = 0.1
        while r <= 4 {
            var best: SIMD2<Float>?
            for k in 0..<24 {
                let a = Float(k) * .pi / 12
                let c = floor(q + SIMD2(sinf(a), cosf(a)) * r)
                if !blocked(c, radius: radius), simd_distance(c, floor(c)) < 1e-4, best == nil || simd_distance(c, p) < simd_distance(best!, p) { best = c }
            }
            if let best { return best }
            r += 0.1
        }
        return q
    }
}
