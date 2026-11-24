//
//  ParkOpen.swift
//  park-open-r1 (owner 2026-11-24 00:25, bubble-wand play in the Park: "I'm sick of them getting stuck, remove the bench in the back of the park and move the slide back some we need more open space they
//  bunch up too much"; 00:27: "or put the bench behind the bush facing the other way"): the park's open floor.
//    - the bench stands BEHIND the back hedge, its back to the lawn, looking out at the hills: scenery only (no collider on the floor, no seat spot, nothing walks to it);
//    - the slide stands further back (z -0.8, was 1.0), so the middle of the lawn is open;
//    - the player's own toys keep to the back corners that are still free;
//    - in the park the bubble wand's spots are scattered over the open floor (Toys/ParkWandSpots.swift) instead of one row.
//  `-ParkOpen old` (dev builds only) puts every one of these back as it was on fdb1acd0, for a before / after in one build.
//

import Foundation
import simd

nonisolated enum ParkOpen {
    static let old: Bool = DevArgs.enabled && UserDefaults.standard.string(forKey: "ParkOpen") == "old"

    /// The slide's centre z (x stays 2.9): 1.0 before. Its footprint is z -2.2 ... 0.6 now; the climb spot (2.9, -2.97) is still a body inside the floor's back edge (z -3.6).
    static var slideZ: Float { old ? 1.0 : -0.8 }

    /// The player's own floor toys: back corners and the back edge, clear of the slide's new footprint and its climb spot.
    static var ownSpots: [SIMD2<Float>] { old ? [SIMD2(-3.7, 1.9), SIMD2(1.7, -2.8), SIMD2(2.95, -2.65)] : [SIMD2(-3.7, 1.9), SIMD2(-3.5, -2.8), SIMD2(-0.2, -3.1)] }

    /// The bench behind the back hedge (hedges at z -6.0 are 1.04 deep, so the bench's front reaches z -6.71 at most): centre (x, z); `-ParkBenchAt "x,z"` moves it for a capture.
    static var benchAt: SIMD2<Float> {
        if DevArgs.enabled, let s = UserDefaults.standard.string(forKey: "ParkBenchAt") {
            let v = s.split(separator: ",").compactMap { Float($0) }
            if v.count == 2 { return SIMD2(v[0], v[1]) }
        }
        return SIMD2(0.0, -7.0)
    }

    /// The wand's bubbles fan out this much wider in the park (their sideways push, 1 = the home room's): the stream spreads over the open floor instead of one column down the middle.
    static var wandSpread: Float { old ? 1 : 3 }
    /// Nobody goes for a bubble whose standing spot is nearer than this to another body.
    static let standApart: Float = 2.0
}
