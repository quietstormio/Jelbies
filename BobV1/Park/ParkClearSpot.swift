//
//  ParkClearSpot.swift
//  park-slide-r2: a floor target that other code picked (a zoomies run, a group hug's centre) can lie INSIDE a solid park piece (the slide above all: a Jelbie who has just ridden it keeps it
//  soft for himself until he is clear of it, `BlobBrain.decorIgnore`, and a pick made in that moment does not see it), and the walk to it then crosses the piece.
//  `ParkClearSpot.clear` returns the nearest clear point. A point that is already clear comes back EXACTLY unchanged, and outside the park (no park slide in the decor field) so does every point.
//

import simd

enum ParkClearSpot {
    /// The park is up when its slide stands in the decor field (the home room never has it).
    static var inPark: Bool { DecorField.shared.foot(ParkToys.slideUID) != nil }

    /// A body of `radius` at `p` would be pushed off by a solid piece (the room's own rule, with NOTHING soft: `resolve` without an ignored piece).
    static func blocked(_ p: SIMD2<Float>, radius: Float) -> Bool {
        let q = RoomLayout.resolve(position: SIMD3(p.x, 0, p.y), radius: radius, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: nil)
        return simd_distance(SIMD2(q.x, q.z), p) > 1e-4
    }

    /// `p` itself when it is clear (and always at home); else the nearest clear point on the roam floor (`GameCamera.constrain`: the solids pushed out of, then the roam floor).
    static func clear(_ p: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        guard inPark, blocked(p, radius: radius) else { return p }
        let q = GameCamera.constrain(SIMD3(p.x, 0, p.y), radius: radius, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: nil)
        return SIMD2(q.x, q.z)
    }
}
