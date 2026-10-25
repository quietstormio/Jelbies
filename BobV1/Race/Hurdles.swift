//
//  Hurdles.swift
//  The low jelly-bar hurdles of the advanced courses (Splash 3, Wave 6, Tsunami 10), their rules and their look.
//
//    HurdleTuning   the jump: the existing hop (BlobBrain.startHop via BlobBrain+Race raceJump) made a little higher and longer, and how it is judged.
//    Hurdles        where they stand: arc lengths on the straights of a course (never in a bend), laid out by segment index and offset.
//    HurdleModels   the 3D bars: a flat foot, two rounded posts and a fat teal / white bar, one per lane (a rival's lane is as real as yours).
//
//  THE RULE. A racer's front reaches a hurdle `contactLead` before his centre does. If he is in the air then, in the middle of the flight (the
//  `clearWindow` fraction of it), he clears the bar; on the ground, or just taking off / landing, he hits it: the existing trip (a stumble of
//  RaceTuning.stumbleTime, no steps) and then shorter, slower steps for `slowTime`. The jump is the hop gait and nothing else: apex `apex`,
//  `hopDistance` forward, then `recover` of landing before the next step. A hop at ~1 u/s covers more ground than it costs, so jumping beats tripping.
//

import Foundation
import simd

nonisolated enum HurdleTuning {
    /// Hop height of the race jump (u). The roaming hop is 0.10 and the jacks' 0.20; the bar's top is 0.125, so the soles clear it through the middle of the flight.
    static let apex: Float = 0.20
    /// Seconds in the air: the hop's own rule (0.26 s at 0.10 apex, scaled by the square root of the height).
    static var airTime: Float { 0.26 * sqrtf(apex / 0.10) }
    /// Forward travel of the hop (u).
    static let hopDistance: Float = 0.75
    /// The hop's crouch before it leaves the ground (Locomotion.crouchTime): the flight clock starts this far BEHIND zero.
    static let crouch: Float = 0.13
    /// Seconds of landing (the hop's land phase) before the next step.
    static let recover: Float = 0.55
    /// Which part of the flight clears the bar: 20% ... 80% of the air time (the sole is above the bar's top there).
    static let clearWindow: ClosedRange<Float> = 0.2...0.8
    /// His front reaches the bar this far before his centre does (u).
    static let contactLead: Float = 0.2
    /// A Jump press waits this long for his feet to be planted.
    static let jumpBuffer: Float = 0.5
    /// After a hit: shorter, slower steps (applied to the stride and to the rate, so about 0.67 of the speed) for this long.
    static let slowFactor: Float = 0.82
    static let slowTime: Float = 1.5
    /// A rival starts to plan for a bar this close (u).
    static let lookAhead: Float = 1.4
    /// The chance a rival jumps a bar at all, by skill (waddle and focus averaged): 0.55 untrained ... 0.95 fully trained.
    static func rivalSuccess(skill: Float) -> Float { 0.55 + 0.40 * RaceTuning.clamp01(skill) }
    /// The "Jump!" hint shows when the next bar is this close ahead (u).
    static let hintAhead: Float = 1.5
}

nonisolated enum Hurdles {
    /// Arc lengths of hurdles given as `(segment index, offsets from that straight's start)`.
    static func place(_ segments: [CourseSegment], _ at: [(Int, [Float])]) -> [Float] {
        var cum: [Float] = [], s: Float = 0
        for seg in segments { cum.append(s); s += seg.length }
        var out: [Float] = []
        for (i, offs) in at where segments.indices.contains(i) {
            if case .turn = segments[i] { continue }                 // never in a bend
            for o in offs where o > 0.3 && o < segments[i].length - 0.3 { out.append(cum[i] + o) }
        }
        return out.sorted()
    }
}

nonisolated enum HurdleModels {
    static let barHalf: Float = 0.64
    static let barTeal = RaceModels.srgb(0.42, 0.80, 0.76), barWhite = RaceModels.white, footCol = RaceModels.srgb(0.36, 0.66, 0.64)

    /// Every hurdle of `c` across lanes 0, 1 and 2, as rounded boxes (axis-aligned: the hurdles stand on the straights that run along z or x).
    static func emit(_ c: RaceCourse, into b: RoomMeshBuilder) {
        guard c.hasHurdles else { return }
        let saved = b.material
        b.material = .plain
        for h in c.hurdles {
            for lane in 0..<3 {
                let q = c.pose(at: h)
                let p = c.lanePoint(lane, at: h)
                let alongX = abs(sinf(q.heading)) < 0.7           // the bar runs across the track: along x on a z-straight, along z on an x-straight
                func box(_ along: Float, _ y: Float, half: SIMD3<Float>, _ r: Float, _ col: SIMD3<Float>) {
                    let off = SIMD3<Float>(alongX ? along : 0, y, alongX ? 0 : along)
                    let hh = alongX ? half : SIMD3(half.z, half.y, half.x)
                    b.roundedBox(centre: SIMD3(p.x, 0, p.y) + off, half: hh, radius: r, segments: 3, aoFloor: false, color: col)
                }
                // half = (along the bar, up, depth)
                for s in [Float(-1), 1] {
                    box(s * (barHalf - 0.06), 0.02, half: SIMD3(0.13, 0.02, 0.10), 0.02, footCol)              // the flat foot
                    box(s * (barHalf - 0.06), 0.07, half: SIMD3(0.055, 0.065, 0.055), 0.05, RaceModels.post)         // the post
                }
                let n = 3, seg = (barHalf * 2 - 0.1) / Float(n)
                for k in 0..<n {                                                                                    // the bar: fat jelly segments, teal / white
                    box(-barHalf + 0.05 + seg * (Float(k) + 0.5), 0.085, half: SIMD3(seg / 2 + 0.005, 0.04, 0.05), 0.04, k % 2 == 0 ? barTeal : barWhite)
                }
            }
        }
        b.material = saved
    }
}
