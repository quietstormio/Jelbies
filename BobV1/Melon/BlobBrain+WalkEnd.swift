//
//  BlobBrain+WalkEnd.swift
//  move-crowd-r2: the hand-off from the end of a walk to the stand (the walk itself is locked; this is the settle after it). Switch `BlobBrain.walkEndSettle`
//  (`-WalkEndSettle 0` / env WALKENDSETTLE=0 = the old hand-off).
//

import Foundation
import simd

extension BlobBrain {
    nonisolated(unsafe) static var walkEndSettle: Bool = {
        if let e = ProcessInfo.processInfo.environment["WALKENDSETTLE"] { return e != "0" }
        if DevArgs.enabled, UserDefaults.standard.object(forKey: "WalkEndSettle") != nil { return UserDefaults.standard.integer(forKey: "WalkEndSettle") != 0 }
        return true
    }()
}

/// After a walk the pose pivots on both feet (the walk pivoted on the stance foot, `gaitPose`) and the walk's bob / squash stop at once: the attractor's anchor moved up to ~5 cm and the squash
/// ~0.05 within a few steps, and the drawn feet and body followed in one or two steps (the glitch probe's "walk end" pops). For `window` s after a walk script ends, the anchor may move at most
/// `anchorStep` per step and the squash `squashStep`, so the stand settles in over ~0.2 s. The walk itself (while the script is a walk) and every other hand-off are untouched.
struct WalkEndState {
    var wasWalk = false
    var t: Float = 0          // seconds left of the eased window
    var lastAnchor: SIMD3<Float>?
    var lastSquash: Float?
}

extension BlobBrain {
    static let walkEndWindow: Float = 0.35
    static let walkEndAnchorStep: Float = 0.006          // (u per 60 Hz step: 36 cm/s, a smooth settle)
    static let walkEndSquashStep: Float = 0.004

    func walkEndSquash(_ sq: Float, _ dt: Float) -> Float {
        let walking = isWalkScript
        if social != nil || held { walkEnd.t = 0 }
        if walkEnd.wasWalk && !walking && social == nil && mealFinalYaw == nil && !isDining { walkEnd.t = Self.walkEndWindow }          // (not a stance walk into a touch, not a meal: those own their last centimetres)
        walkEnd.wasWalk = walking
        defer { walkEnd.t = max(0, walkEnd.t - dt) }
        guard walkEnd.t > 0, let last = walkEnd.lastSquash else { walkEnd.lastSquash = sq; return sq }
        let out = last + max(-Self.walkEndSquashStep, min(Self.walkEndSquashStep, sq - last))
        walkEnd.lastSquash = out
        return out
    }
    func walkEndAnchor(_ a: SIMD3<Float>) -> SIMD3<Float> {
        guard walkEnd.t > 0, let last = walkEnd.lastAnchor else { walkEnd.lastAnchor = a; return a }
        let d = a - last, L = simd_length(d)
        let out = L > Self.walkEndAnchorStep ? last + d / L * Self.walkEndAnchorStep : a
        walkEnd.lastAnchor = out
        return out
    }
}

extension BlobBrain {
    /// A meal walk is on (dine / sip job or the dine script).
    var isDining: Bool {
        switch job { case .dine?, .sip?, .eat?, .drink?: return true; default: break }
        if case .dine = script { return true }
        return false
    }
}
