//
//  SnapshotPose.swift
//  The Studio's action shot poses the Jelbie's ARMS for one snapshot (the same arm capsules the idle moves use: `armDirW / armDirEl / armDirSa / armDirOut`, drawn by BlobBrain.driveArms),
//  then puts every piece of the live arm state back, so the room never sees it. The body, the feet and the shoes are not touched: the feet stay on the floor, attached.
//  The hop, the lean and the sway of the picture are SwiftUI (JelbieActionShot).
//

import simd

/// One pose of the action shot: per side arm elevation / sweep (rad, the idle arm convention), the shoulders' outward nudge, and how the camera / picture turns for it.
struct SnapshotArmPose {
    var el: [Float]
    var sa: [Float]
    var out: Float
    /// Camera yaw (rad) from straight in front.
    var yaw: Float
    /// The picture's lean (degrees, SwiftUI), a side lean for the one-arm pose.
    var leanDeg: Double
    /// Arms that stay down are left at rest when `el` is nil on a side (0 = pose the arm).
    var title: String

    /// ta-da (both arms up), a proud side lean (one arm up, one out), a wide cheer (arms flung out and up).
    static let all: [SnapshotArmPose] = [
        SnapshotArmPose(el: [1.05, 1.05], sa: [0.12, 0.12], out: 0.07, yaw: 0.0, leanDeg: 0, title: "ta-da"),
        SnapshotArmPose(el: [1.15, 0.15], sa: [0.10, 0.45], out: 0.06, yaw: 0.28, leanDeg: 5, title: "proud"),
        SnapshotArmPose(el: [0.62, 0.62], sa: [0.55, 0.55], out: 0.06, yaw: -0.28, leanDeg: -4, title: "cheer"),
    ]
    static func pose(_ i: Int) -> SnapshotArmPose { all[min(max(i, 0), all.count - 1)] }
}

/// Everything BlobBrain.driveArms (and prepareArms) writes on the brain and the skinner, saved before a posed snapshot and restored after it.
struct SnapshotArmState {
    var armLift: Float, armLiftV: Float, armG: Float, armHold: Float, armShortW: Float, armGaitW: Float
    var armWalkWant: Float, armDirW: Float, armDirEl: [Float], armDirSa: [Float], armDirOut: Float
    var armLastGeom: [(a: SIMD3<Float>, b: SIMD3<Float>, r1: Float, r2: Float, f: Float)]
    var armLastRawTip: [SIMD3<Float>], armLastS: [Float]
    var armWasOut: Bool, armCollarTick: Int
    var armPos: [[SIMD3<Float>]], armStart: [[SIMD3<Float>]], armBlend: Float, armRetractMatrix: simd_float3x3, armCollarDelta: [SIMD3<Float>]
    var overrideVertices: [Int32], overrideDelta: [SIMD3<Float>], overrideMat: [Float]
}

extension BlobBrain {
    func saveArmState(_ s: Skinner) -> SnapshotArmState {
        SnapshotArmState(armLift: armLift, armLiftV: armLiftV, armG: armG, armHold: armHold, armShortW: armShortW, armGaitW: armGaitW,
                         armWalkWant: armWalkWant, armDirW: armDirW, armDirEl: armDirEl, armDirSa: armDirSa, armDirOut: armDirOut,
                         armLastGeom: armLastGeom, armLastRawTip: armLastRawTip, armLastS: armLastS, armWasOut: armWasOut, armCollarTick: armCollarTick,
                         armPos: s.armPos, armStart: s.armStart, armBlend: s.armBlend, armRetractMatrix: s.armRetractMatrix, armCollarDelta: s.armCollarDelta,
                         overrideVertices: s.overrideVertices, overrideDelta: s.overrideDelta, overrideMat: s.overrideMat)
    }

    func restoreArmState(_ o: SnapshotArmState, _ s: Skinner) {
        armLift = o.armLift; armLiftV = o.armLiftV; armG = o.armG; armHold = o.armHold; armShortW = o.armShortW; armGaitW = o.armGaitW
        armWalkWant = o.armWalkWant; armDirW = o.armDirW; armDirEl = o.armDirEl; armDirSa = o.armDirSa; armDirOut = o.armDirOut
        armLastGeom = o.armLastGeom; armLastRawTip = o.armLastRawTip; armLastS = o.armLastS; armWasOut = o.armWasOut; armCollarTick = o.armCollarTick
        if o.armPos[0].isEmpty { s.clearArmCapsules() } else { s.armPos = o.armPos; s.armStart = o.armStart; s.armCollarDelta = o.armCollarDelta }
        s.armBlend = o.armBlend; s.armRetractMatrix = o.armRetractMatrix
        if o.overrideVertices.isEmpty { s.clearOverride() } else { s.overrideVertices = o.overrideVertices; s.overrideDelta = o.overrideDelta; s.overrideMat = o.overrideMat }
    }

    /// Both arms out in `p` for the next skin update (the capsule arms fully swapped in, no blend wait). False when the feet / arm geometry is not ready (the arms stay as they are).
    @discardableResult
    func poseArmsForSnapshot(_ p: SnapshotArmPose, sim: SoftBody, skinner: Skinner) -> Bool {
        if !geom.valid { geom = FootGeom(sim: sim) }          // (a Jelbie who has not walked yet has none: the same lazy build the idle moves do)
        guard geom.valid else { return false }
        armWalkWant = 1; armLift = 1; armLiftV = 0; armG = 1; armHold = 0.7; armShortW = 1
        armDirW = 1; armDirEl = p.el; armDirSa = p.sa; armDirOut = p.out
        armLastS = [25, 25]
        driveArms(sim, skinner, 1.0 / 60)
        return armWasOut
    }
}
