//
//  RaceCamera.swift
//  The follow camera of a curved course. The Puddle keeps its one fixed frame (GameCamera.racePose); Ripple, Splash and Wave are followed:
//  the eye glides a little way DOWN the course ahead of the leader and looks back at the racers (faces to the viewer, as on the straight),
//  framing the player and the leader together, and banks a few degrees into the bend. The eye rides high over the track, above the gantry and
//  the trees, so nothing of the scenery is ever clipped. Portrait and landscape share the framing height (GameCamera.framingAspect).
//

import Foundation
import simd

/// Where the follow camera wants to be: a target on the track, the horizontal direction from it to the eye, and the bank (rad, + = right turn).
struct RaceFollowPose: Equatable {
    var target: SIMD3<Float>
    var toEye: SIMD2<Float>
    var bank: Float

    struct Racer { var pos: SIMD2<Float>; var s: Float; var isPlayer: Bool }

    /// Camera elevation over the track and the distance to the target (set by the width the frame must hold, like the Puddle's frame).
    static let elevation: Float = 24 * .pi / 180
    static let halfWidth: Float = 3.3, fill: Float = 0.94, minDistance: Float = 16
    /// How far down the course (arc length) from the front racer the eye's anchor sits. Short enough that a hairpin (radius 4) does not swing
    /// the eye round to the racers' side: with 3.3 half-width the player stays within |ndc.x| 0.70 in portrait on the Wave (was 0.98 at 8 / 2.9).
    static let lead: Float = 5
    /// The target sits this share of the way from the player toward the leader, but never more than `maxGap` from the player.
    static let leaderShare: Float = 0.4, maxGap: Float = 4.5
    static let targetHeight: Float = 0.45
    /// The final stretch: over the last `finishEase` u the target slides up to `finishPush` u past the line, so the racers ride up the frame and
    /// the finish banner (3.5 u up, between the eye and them) passes ABOVE their heads instead of across them (measured: heads 0.22-0.28 ndc, the
    /// banner 0.31-0.49 in portrait at full push; without it the banner crossed at head height for the last 3-4 s). The ease starts 10 u out so
    /// the push is well in by the time the gantry is close.
    static let finishEase: Float = 10, finishPush: Float = 6
    /// Bank per unit of curvature (1 / radius) at the target, capped.
    static let bankGain: Float = 0.11, bankMax: Float = 4.5 * .pi / 180
    /// Smoothing rates (per second) of the target, the direction and the bank.
    static let targetRate: Float = 5, dirRate: Float = 2.5, bankRate: Float = 3

    static func distance(aspect: Float) -> Float {
        let th = tanf(GameCamera.fovY / 2)
        return max(minDistance, halfWidth / (fill * th * max(GameCamera.framingAspect(aspect), 0.2)))
    }

    /// The pose a frame wants for `racers` on `course`.
    static func aim(course: RaceCourse, racers: [Racer]) -> RaceFollowPose {
        let player = racers.first { $0.isPlayer } ?? racers[0]
        let leader = racers.max { $0.s < $1.s } ?? player
        var t = player.pos + (leader.pos - player.pos) * leaderShare
        let d = simd_length(t - player.pos)
        if d > maxGap { t = player.pos + (t - player.pos) * (maxGap / d) }
        let sFront = max(player.s, leader.s)
        let k = max(0, min(1, (sFront - (course.length - finishEase)) / finishEase))
        let push = finishPush * k
        if k > 0 { t += RaceCourse.forward(course.pose(at: course.length).heading) * push }
        let anchor = course.pose(at: sFront + lead + push).pos                       // the anchor moves with the push: the eye stays `lead` ahead of the target
        var dir = anchor - t
        let len = simd_length(dir)
        dir = len > 0.5 ? dir / len : RaceCourse.forward(course.pose(at: sFront).heading)
        let tS = course.progress(of: t, lane: RaceTuning.playerLane, near: player.s)
        let bank = max(-bankMax, min(bankMax, course.curvature(at: tS) * bankGain))
        return RaceFollowPose(target: SIMD3(t.x, targetHeight, t.y), toEye: dir, bank: bank)
    }

    /// Eased toward `want` by `dt` seconds.
    func smoothed(toward want: RaceFollowPose, dt: Float) -> RaceFollowPose {
        var out = self
        out.target += (want.target - target) * min(1, dt * Self.targetRate)
        let d = toEye + (want.toEye - toEye) * min(1, dt * Self.dirRate)
        let l = simd_length(d)
        out.toEye = l > 1e-4 ? d / l : want.toEye
        out.bank += (want.bank - bank) * min(1, dt * Self.bankRate)
        return out
    }

    /// Eye, target and the rolled up vector for a view of `aspect`.
    func camera(aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let dist = Self.distance(aspect: aspect)
        let eye = target + SIMD3(toEye.x, 0, toEye.y) * (dist * cosf(Self.elevation)) + SIMD3(0, dist * sinf(Self.elevation), 0)
        // bank: roll the up vector about the view axis, into the turn (a right turn dips the right side of the frame)
        let fwd = simd_normalize(target - eye)
        let side = simd_normalize(simd_cross(fwd, SIMD3<Float>(0, 1, 0)))
        let up0 = simd_cross(side, fwd)
        let up = simd_normalize(up0 * cosf(bank) + side * sinf(bank))
        return (eye, target, up)
    }
}
