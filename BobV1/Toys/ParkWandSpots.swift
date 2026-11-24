//
//  ParkWandSpots.swift
//  park-open-r1: the bubble wand in the PARK. At home three Jelmiko stand abreast on one row and chase the bubbles that float down the middle; in the park that row fell between the hopscotch court and the slide
//  (the wand's area is the band of the screen between 40% and 70% of its height, which is the middle of the lawn), one bubble column pulled everybody to the same few steps of ground, and four bodies knotted
//  there (owner 2026-11-24 00:25). In the park the area reaches further back (the lawn the slide no longer takes), every awake Jelmiko gets a spot scattered over the open floor (never on the court, never by
//  the slide), and a bubble is left alone when another body stands nearer than `ParkOpen.standApart` to the spot under it. Pure helpers; BubbleWand.swift calls them from four places. Home is untouched.
//

import simd
import Foundation

enum ParkWand {
    /// The wand's park rules are on: the park is the world, and `-ParkOpen old` is not given.
    static var on: Bool { !ParkOpen.old && GameCamera.parkRoamMaxZ != nil }
    /// The back edge of the wand's area, as a fraction of the screen height from the top (home: 0.40).
    static let topFraction: CGFloat = 0.26
    /// The area never goes nearer the floor's back edge than this.
    static let backMargin: Float = 0.3
    /// A spot keeps this far off the hopscotch court's edge (a court is flat paint but nobody stands about on it) and off a solid piece's reach.
    static let courtMargin: Float = 0.6, bodyRadius: Float = 0.8
    /// The spread of the picks: a spot counts as well apart at this distance (so the first ones are not driven to the corners).
    static let wellApart: Float = 2.8

    /// `count` spots in the box lo...hi, clear of every solid piece and the court, at least `wellApart` from each other and from `others` where the box allows (the farthest-first pick, nearer the middle on a tie).
    /// Fewer than `count` come back only when the box has no clear ground left.
    static func scatter(count: Int, lo: SIMD2<Float>, hi: SIMD2<Float>, others: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard count > 0 else { return [] }
        var cands: [SIMD2<Float>] = []
        var z = lo.y + 0.2
        while z <= hi.y - 0.2 + 1e-4 {
            var x = lo.x + 0.2
            while x <= hi.x - 0.2 + 1e-4 {
                let p = SIMD2<Float>(x, z)
                if ParkClearSpot.inPark, !ParkClearSpot.blocked(p, radius: bodyRadius), !ParkClearSpot.courts.contains(where: { $0.distance(p) < courtMargin }) {
                    let c = GameCamera.constrain(SIMD3(p.x, 0, p.y), radius: 0.6)
                    if simd_distance(SIMD2(c.x, c.z), p) < 0.05 { cands.append(p) }
                }
                x += 0.35
            }
            z += 0.35
        }
        guard !cands.isEmpty else { return [] }
        let mid = (lo + hi) * 0.5
        var chosen: [SIMD2<Float>] = []
        for _ in 0..<count {
            var best: (SIMD2<Float>, Float)?
            for p in cands {
                var m: Float = wellApart
                for q in chosen + others { m = min(m, simd_distance(p, q)) }
                let score = m - 0.05 * simd_distance(p, mid)
                if best == nil || score > best!.1 { best = (p, score) }
            }
            guard let b = best else { break }
            chosen.append(b.0)
        }
        return chosen
    }
}
