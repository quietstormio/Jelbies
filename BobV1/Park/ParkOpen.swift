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
    /// `-ParkOpen old` (dev builds), or `PARKOPEN_OLD=1` in a test run's environment (`TEST_RUNNER_PARKOPEN_OLD=1 xcodebuild test ...`: the same suites on fdb1acd0's park, for "red on the old build too").
    static let old: Bool = (DevArgs.enabled && UserDefaults.standard.string(forKey: "ParkOpen") == "old")
        || (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && ProcessInfo.processInfo.environment["PARKOPEN_OLD"] == "1")

    /// The slide's centre z (x stays 2.9): 1.0 before. Its footprint is z -1.7 ... 1.1 now and its climb spot (2.9, -2.47) is the furthest back the placement rule allows (the climb spot must be at z >= walkMinZ + 0.1 = -2.5)
    /// and still on fully free floor rows (further back the top-right HUD cuts the rows: the roam floor's free spans at z -3.0 end at x 2.9, at z -3.2 at 2.7).
    static var slideZ: Float { old ? 1.0 : -0.3 }

    /// The player's own floor toys: back corners and the back edge, clear of the slide's new footprint and its climb spot.
    static var ownSpots: [SIMD2<Float>] { old ? [SIMD2(-3.7, 1.9), SIMD2(1.7, -2.8), SIMD2(2.95, -2.65)] : [SIMD2(-3.7, 1.9), SIMD2(-3.5, -3.0), SIMD2(1.6, -3.2)] }

    /// The bench behind the back hedge (hedges at z -6.0 are 1.04 deep, so the bench's front reaches z -6.71 at most): centre (x, z); `-ParkBenchAt "x,z"` moves it for a capture.
    static var benchAt: SIMD2<Float> {
        if DevArgs.enabled, let s = UserDefaults.standard.string(forKey: "ParkBenchAt") {
            let v = s.split(separator: ",").compactMap { Float($0) }
            if v.count == 2 { return SIMD2(v[0], v[1]) }
        }
        return SIMD2(0.0, -7.0)
    }

    /// The three spots an ex-rider (or a stander asked off the foot) walks to, in the slide's own frame (x to the side, z along the chute): old = the left lawn at the court's side, new = the open middle,
    /// clear of the hopscotch queue (its slots are (-2.1, -1.1), (-0.4, -1.1), (0.45, -2.57) and (-0.4, 0.6): the old second and third spots fell on them).
    static var slideOutSpots: [SIMD2<Float>] { old ? [SIMD2(-3.25, 2.5), SIMD2(-3.4, 1.1), SIMD2(-3.4, -0.35)] : [SIMD2(-3.25, 2.5), SIMD2(-3.0, 4.0), SIMD2(-1.3, 4.0)] }

    /// The wand's bubbles fan out this much wider in the park (their sideways push, 1 = the home room's): the stream spreads over the open floor instead of one column down the middle.
    static var wandSpread: Float { old ? 1 : 3 }
    /// Nobody goes for a bubble whose standing spot is nearer than this to another body.
    static let standApart: Float = 2.0
}
