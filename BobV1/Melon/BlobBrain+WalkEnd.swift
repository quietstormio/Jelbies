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

/// (see WalkEndState) After a walk the pose pivots on both feet (the walk pivoted on the stance foot, `gaitPose`) and the walk's bob / squash stop at once: the attractor's anchor moved up to ~5 cm and the squash
/// ~0.05 within a few steps, and the drawn feet and body followed in one or two steps (the glitch probe's "walk end" pops). For `window` s after a walk script ends, the anchor may move at most
/// `anchorStep` per step and the squash `squashStep`, so the stand settles in over ~0.2 s. The walk itself (while the script is a walk) and every other hand-off are untouched.
struct WalkEndState {
    var wasWalk = false
    var t: Float = 0          // seconds left of the blend
    var lastAnchor: SIMD3<Float>?, lastSquash: Float?          // last step's drawn values
    var offA = SIMD3<Float>.zero, offS: Float = 0          // the jump at the hand-off, faded out over the window
    var fresh = false
}

extension BlobBrain {
    static let walkEndWindow: Float = 0.3

    /// The hand-off's jump (anchor and squash) is measured on the first stand step and faded out over `walkEndWindow` (smoothstep): continuous, no catch-up at the end.
    func walkEndSquash(_ sq: Float, _ dt: Float) -> Float {
        let walking = isWalkScript
        if social != nil || held { walkEnd.t = 0 }
        if walkEnd.wasWalk && !walking && social == nil && mealFinalYaw == nil && !isDining { walkEnd.t = Self.walkEndWindow; walkEnd.fresh = true; walkEnd.offS = (walkEnd.lastSquash ?? sq) - sq }
        walkEnd.wasWalk = walking
        var out = sq
        if walkEnd.t > 0 { let u = walkEnd.t / Self.walkEndWindow; out = sq + walkEnd.offS * u * u * (3 - 2 * u) }
        walkEnd.lastSquash = out
        walkEnd.t = max(0, walkEnd.t - dt)
        return out
    }
    func walkEndAnchor(_ a: SIMD3<Float>) -> SIMD3<Float> {
        if walkEnd.fresh { walkEnd.offA = (walkEnd.lastAnchor ?? a) - a; walkEnd.fresh = false }
        var out = a
        if walkEnd.t > 0 { let u = min(1, (walkEnd.t + 1.0 / 60) / Self.walkEndWindow); out = a + walkEnd.offA * u * u * (3 - 2 * u) }
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
