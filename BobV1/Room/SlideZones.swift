//
//  SlideZones.swift
//  no-clip-r1: the two spots a Jelmiko stands on when he uses a slide (the climb spot behind it, where he starts hopping up, and the landing in front) must have no other furniture within
//  a body and an arm's reach, or his arms (and belly) go through it: ClipProbe saw arms 37-48 cm inside a wardrobe and an aquarium standing there. A home slide that fails it is not offered
//  to him on his own (`BlobBrain.decorOffers`); it still stands, and a voice command / tap work; the park's slide is never gated. Position-independent: measured from the slide's own frame.
//

import simd

enum SlideZones {
    /// Reach of a body at the spot: belly 0.55 + arm 0.25. The spots: local z of the climb spot and of the landing (the end of the chute + its coast).
    static let reach: Float = 0.8
    static let climbZ: Float = -2.3, landingZ: Float = 2.45

    static func spots(_ f: DecorFoot) -> [SIMD2<Float>] { [climbZ, landingZ].map { f.centre + f.turned(SIMD2(0, $0)) } }
    /// Kept for the probe's log: the spots as tiny boxes.
    static func zones(_ f: DecorFoot) -> [(lo: SIMD2<Float>, hi: SIMD2<Float>)] { spots(f).map { ($0 - SIMD2(repeating: reach), $0 + SIMD2(repeating: reach)) } }

    private static func dist(_ p: SIMD2<Float>, lo: SIMD2<Float>, hi: SIMD2<Float>) -> Float { simd_length(simd_max(simd_max(lo - p, p - hi), .zero)) }

    /// True when no other solid piece, fixed furniture or cylinder is within `reach` of either spot.
    static func clear(_ f: DecorFoot, among feet: [DecorFoot]) -> Bool {
        let sp = spots(f)
        for g in feet where g.uid != f.uid && g.spec.solid {
            let b = DecorField.shared.position(g), h = g.spec.half
            if sp.contains(where: { dist($0, lo: b - h, hi: b + h) < reach }) { return false }
        }
        var boxes = [RoomLayout.sofa]; boxes.append(contentsOf: RoomLayout.current.boxes)
        for b in boxes where sp.contains(where: { dist($0, lo: SIMD2(b.centre.x - b.halfExtents.x, b.centre.z - b.halfExtents.z), hi: SIMD2(b.centre.x + b.halfExtents.x, b.centre.z + b.halfExtents.z)) < reach }) { return false }
        for cy in RoomLayout.cylinders where sp.contains(where: { simd_distance($0, cy.centre) < reach + cy.radius }) { return false }
        return true
    }
}
