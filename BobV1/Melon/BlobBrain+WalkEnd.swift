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
        return false          // (OFF: the rig A/B moved little - 6 walks, pops in the 1.5 s after the end 39 -> 35, >= 5 cm 16 -> 16, worst 6.6 -> 6.6; `-WalkEndSettle 1` to try)
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
    static let walkEndWindow: Float = 0.4
    /// (round 3) the low-pass time constant (s) of the anchor and squash in the window: the stand's rise after the walk (the body rose ~3 cm in two steps 3 steps after the end, and the attached
    /// feet with it: the probe's 50 ms foot pop) is followed smoothly; the filter hands back to the raw pose over the window's last 0.1 s (it has converged by then: no catch-up).
    static let walkEndTau: Float = 0.08

    func walkEndSquash(_ sq: Float, _ dt: Float) -> Float {
        let walking = isWalkScript
        if social != nil || held { walkEnd.t = 0 }
        if walkEnd.wasWalk && !walking && social == nil && mealFinalYaw == nil && !isDining { walkEnd.t = Self.walkEndWindow }
        walkEnd.wasWalk = walking
        var out = sq
        if walkEnd.t > 0, let last = walkEnd.lastSquash { out = last + (sq - last) * walkEndAlpha(dt) }
        walkEnd.lastSquash = out
        walkEnd.t = max(0, walkEnd.t - dt)
        return out
    }
    /// The filter's step weight: 1 - e^(-dt / tau), rising to 1 over the window's last 0.1 s.
    func walkEndAlpha(_ dt: Float) -> Float {
        let a = 1 - expf(-dt / Self.walkEndTau)
        let tail = min(1, max(0, (0.1 - walkEnd.t) / 0.1))
        return a + (1 - a) * tail
    }
    func walkEndAnchor(_ a: SIMD3<Float>) -> SIMD3<Float> {
        var out = a
        if walkEnd.t > 0, let last = walkEnd.lastAnchor { out = last + (a - last) * walkEndAlpha(1.0 / 60) }
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
