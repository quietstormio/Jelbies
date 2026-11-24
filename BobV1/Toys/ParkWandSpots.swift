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
    /// The park's area: the side edges at this fraction of the screen width (home 0.17 / 0.24), minus a body's half width.
    static let sideFraction: CGFloat = 0.10, sideMargin: Float = 0.55
    /// The spots are chosen in the front `slotDepth` of the area: the stream drifts back from the wand at the front for 4 to 6 s and does not reach the far back before it pops (the first take with spots over the whole
    /// depth left two of the three at the back looking up at nothing: 0 chases in 320 s).
    static let slotDepth: Float = 4.2
    /// The area never goes nearer the floor's back edge than this.
    static let backMargin: Float = 0.3
    /// A spot keeps this far off the hopscotch court's edge (a court is flat paint but nobody stands about on it) and off a solid piece's reach.
    static let courtMargin: Float = 0.4, bodyRadius: Float = 0.8
    /// The spread of the picks: a spot counts as well apart at this distance (so the first ones are not driven to the corners).
    static let wellApart: Float = 2.4

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
        // the spread of a set: its least pairwise distance (to each other and to `others`), capped at `wellApart`, less a small pull away from the middle (a tie goes to the more central set)
        func score(_ set: [SIMD2<Float>]) -> Float {
            var m: Float = wellApart
            for i in set.indices {
                for j in set.indices where j > i { m = min(m, simd_distance(set[i], set[j])) }
                for q in others { m = min(m, simd_distance(set[i], q)) }
            }
            let far = set.reduce(Float(0)) { $0 + simd_distance($1, mid) } / Float(set.count)
            return m - 0.05 * far
        }
        // farthest-first start, then swap moves: replace one spot by any candidate while that raises the score (3 spots fit 2.2 apart in the portrait box; the first pick alone left them 1.75 - 1.9 apart)
        var chosen: [SIMD2<Float>] = []
        for _ in 0..<min(count, cands.count) {
            var best: (SIMD2<Float>, Float)?
            for p in cands where !chosen.contains(p) {
                let sc = score(chosen + [p])
                if best == nil || sc > best!.1 { best = (p, sc) }
            }
            if let b = best { chosen.append(b.0) }
        }
        var cur = score(chosen)
        for _ in 0..<12 {
            var improved = false
            for i in chosen.indices {
                for p in cands where !chosen.contains(p) {
                    var t = chosen; t[i] = p
                    let sc = score(t)
                    if sc > cur + 1e-4 { chosen = t; cur = sc; improved = true }
                }
            }
            if !improved { break }
        }
        return chosen
    }

    /// The part of the wand's area the spots are chosen in: the front `slotDepth` of it, where the bubbles are.
    static func slotBox(lo: SIMD2<Float>, hi: SIMD2<Float>) -> (lo: SIMD2<Float>, hi: SIMD2<Float>) { (SIMD2(lo.x, max(lo.y, hi.y - slotDepth)), hi) }
}
