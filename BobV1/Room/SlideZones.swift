//
//  SlideZones.swift
//  no-clip-r1: the floor a Jelmiko stands on, hops over and lands on when he uses a slide must be clear of other furniture, or his arms (and belly) go through it: the climb behind the
//  slide (he hops up the steps with his arms out) and the landing in front of it. ClipProbe saw arms 37-48 cm inside a wardrobe and an aquarium standing there. A home slide whose zones are not
//  clear is not offered to him on his own (`BlobBrain.decorOffers`; it still stands, and a voice command / the player's tap still work; the park's slide is never gated). Position-independent: everything is measured from the slide's own frame.
//

import simd

enum SlideZones {
    /// Half width of the zones (the arms-up rider is 1.6 wide), the climb zone behind the slide (piece-local z), the landing zone in front, and the margin kept to other pieces.
    static let halfX: Float = 1.0
    static let climb: ClosedRange<Float> = -3.0 ... -1.9
    static let landing: ClosedRange<Float> = 1.9 ... 3.5
    static let margin: Float = 0.1

    /// The zone boxes in the world (axis-aligned: a quarter turn swaps the half extents).
    static func zones(_ f: DecorFoot) -> [(lo: SIMD2<Float>, hi: SIMD2<Float>)] {
        [climb, landing].map { z in
            let c = f.centre + f.turned(SIMD2(0, (z.lowerBound + z.upperBound) / 2))
            let h = SIMD2<Float>(halfX, (z.upperBound - z.lowerBound) / 2)
            let w = f.quarter & 1 == 1 ? SIMD2(h.y, h.x) : h
            return (c - w - SIMD2(repeating: margin), c + w + SIMD2(repeating: margin))
        }
    }

    /// True when no other solid piece, the room's fixed furniture or a cylinder stands in the climb or landing zone.
    static func clear(_ f: DecorFoot, among feet: [DecorFoot]) -> Bool {
        let zs = zones(f)
        func hit(_ lo: SIMD2<Float>, _ hi: SIMD2<Float>) -> Bool { zs.contains { lo.x < $0.hi.x && hi.x > $0.lo.x && lo.y < $0.hi.y && hi.y > $0.lo.y } }
        for g in feet where g.uid != f.uid && g.spec.solid {
            let b = DecorField.shared.position(g), h = g.spec.half
            if hit(b - h, b + h) { return false }
        }
        let c = RoomLayout.sofa
        var boxes = [c]; boxes.append(contentsOf: RoomLayout.current.boxes)
        for b in boxes where hit(SIMD2(b.centre.x - b.halfExtents.x, b.centre.z - b.halfExtents.z), SIMD2(b.centre.x + b.halfExtents.x, b.centre.z + b.halfExtents.z)) { return false }
        for cy in RoomLayout.cylinders where hit(cy.centre - SIMD2(repeating: cy.radius), cy.centre + SIMD2(repeating: cy.radius)) { return false }
        return true
    }
}
