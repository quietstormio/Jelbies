//
//  DecorKind+Soccer.swift
//  The soccer pieces' numbers (from the Blender exports' JSON: soccerball.json, minigoal.json), the goal's geometry in piece-local game coordinates
//  (+z toward the camera = the mouth), its stand points, and the save migration: a football in an old save is a soccer ball now.
//

import Foundation
import simd

nonisolated enum SoccerTuning {
    /// The ball (soccerball.json): radius, the roll's friction, when it stops, the wall bounce, the kick speeds.
    static let radius: Float = 0.18
    static let linearDecayPerS: Float = 1.15
    static let stopSpeed: Float = 0.05
    static let wallRestitution: Float = 0.6
    static let kickSpeed: ClosedRange<Float> = 1.6...3.4
    /// Soft bumps: furniture and the sofa, a Jelly's body (radius of the bump circle round his root).
    static let furnitureRestitution: Float = 0.6
    static let bodyRadius: Float = 0.45
    static let bodyRestitution: Float = 0.4
    /// The longest a sub-step may move the ball (no tunnelling: a third of its radius).
    static let maxSubStep: Float = 0.06
    /// How far a Jelly stands behind the ball to kick (toe tip ~0.26 in front of the root + the stomp step's reach, meeting the ball's surface 0.16 in front of its centre).
    static let standBack: Float = 0.72
    /// The stomp step: forward reach of the planted foot (the sit's `bagFootReach` is 0.27 and inside the FeetAttach envelope), rate and lift.
    static let stompReach: Float = 0.27
    static let stompRate: Float = 3.0
    static let stompPeak: Float = 0.07
    /// The toe reaches the ball from this far (root to ball centre).
    static let kickReach: Float = 1.15
    /// Dribble: the ball is kept about this far ahead; a nudge on each footfall aims for `dribbleAhead` plus a stride.
    static let dribbleAhead: Float = 0.75
    static let dribbleStride: Float = 0.4
    static let dribbleNudge: ClosedRange<Float> = 0.7...1.7
    static let dribbleReach: Float = 1.1
    /// The ball this close to his root is touched on at once, whatever the feet are doing (his belly would walk into it otherwise).
    static let dribbleTouch: Float = 0.72
    /// Stuck: at rest against a wall / in a corner / under furniture this long and a Jelly comes to dribble it out; the boundary nudge is the fallback.
    static let stuckAfter: Float = 20
    static let nudgeAfter: Float = 28
    /// After a goal the ball rolls gently back out of the mouth and stops about 0.6 in front of the goal.
    static let rollOutStop: Float = 0.6
    /// The net puffs by w * maxPush * amount and rings down at ~2.5 Hz.
    static let netPush: Float = 0.16
    static let netHz: Float = 2.5
}

/// The mini goal in piece-local game coordinates (minigoal.json): the mouth plane, the posts, the back of the net and the kick spots.
nonisolated enum GoalGeometry {
    /// The mouth: a plane at z = 0.31 facing +z (out into the room); inner clear half width 0.72.
    static let mouthZ: Float = 0.31
    static let mouthHalfWidth: Float = 0.72
    static let mouthCentreY: Float = 0.43
    /// The ball's centre stops this far behind the mouth plane (the net's back is at z -0.22, ball radius on top).
    static let backZ: Float = -0.22
    /// The frame's outer extents.
    static let outerHalfX: Float = 0.815, frontZ: Float = 0.365, rearZ: Float = -0.36
    /// Flat boxes the ball bounces off (centre xz, half extents): the two posts with their side nets, and the back bar / back net.
    static let solids: [(centre: SIMD2<Float>, half: SIMD2<Float>)] = [
        (SIMD2(-(mouthHalfWidth + outerHalfX) / 2, (frontZ + rearZ) / 2), SIMD2((outerHalfX - mouthHalfWidth) / 2, (frontZ - rearZ) / 2)),
        (SIMD2((mouthHalfWidth + outerHalfX) / 2, (frontZ + rearZ) / 2), SIMD2((outerHalfX - mouthHalfWidth) / 2, (frontZ - rearZ) / 2)),
        (SIMD2(0, (backZ + rearZ) / 2), SIMD2(outerHalfX, (backZ - rearZ) / 2)),
    ]
    /// Where a shot is taken from (`stand_points.kick_spots`): the ball's spot, where the Jelly stands (0.5 behind it) and the aim (the mouth's centre), piece-local xz.
    static let kickSpots: [(ball: SIMD2<Float>, stand: SIMD2<Float>, aim: SIMD2<Float>)] = [
        (SIMD2(-0.5, 1.0), SIMD2(-0.5, 1.5), SIMD2(0, mouthZ)), (SIMD2(0, 1.0), SIMD2(0, 1.5), SIMD2(0, mouthZ)), (SIMD2(0.5, 1.0), SIMD2(0.5, 1.5), SIMD2(0, mouthZ)),
        (SIMD2(-0.5, 1.7), SIMD2(-0.5, 2.2), SIMD2(0, mouthZ)), (SIMD2(0, 1.7), SIMD2(0, 2.2), SIMD2(0, mouthZ)), (SIMD2(0.5, 1.7), SIMD2(0.5, 2.2), SIMD2(0, mouthZ)),
    ]
    /// Is a piece-local ball centre inside the goal's mouth (between the posts, behind the plane, in front of the net)?
    static func inside(_ p: SIMD2<Float>, radius r: Float) -> Bool { abs(p.x) < mouthHalfWidth - r + 0.02 && p.y < mouthZ && p.y > backZ - 0.02 }
}

extension DecorKind {
    /// A football in an old save (removed 2026-10-20) decodes as the soccer ball; anything else unknown fails as before.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let k = DecorKind(rawValue: Self.migrated(raw)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown decor kind \(raw)"))
        }
        self = k
    }
    /// The old id of a removed piece -> the piece it became.
    static func migrated(_ raw: String) -> String { raw == "football" ? DecorKind.soccerball.rawValue : raw }
    /// The old store id of a removed piece -> the store id it became (`decor-football` -> `decor-soccerball`).
    static func migratedStoreID(_ id: String) -> String { id == "decor-football" ? DecorKind.soccerball.storeID : id }
}
